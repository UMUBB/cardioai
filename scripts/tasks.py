#!/usr/bin/env python3
"""Task-card tooling for the CardioAI repository (stdlib only).

Commands:
    check                    validate task cards, dependencies and Markdown cross-references
    backlog                  regenerate tasks/BACKLOG.md from task front matter
    next [--owner A]         list `todo` tasks whose dependencies are all `done`
    show T103                show a task, its dependencies and dependents
    set-status T103 review   change the `status` field in a task's front matter
    graph                    print the dependency graph as Mermaid
    issues [--repo org/repo] print `gh` commands that create labels and issues (nothing is executed)

Run from anywhere: paths are resolved relative to the repository root (parent of `scripts/`).
"""

from __future__ import annotations

import argparse
import re
import sys
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TASKS_DIR = ROOT / "tasks"
BACKLOG_PATH = TASKS_DIR / "BACKLOG.md"
TASK_FILE_RE = re.compile(r"^(T\d{3})-[a-z0-9-]+\.md$")

REQUIRED_KEYS = (
    "id",
    "title",
    "epic",
    "owner",
    "reviewer",
    "week",
    "size",
    "level",
    "gate",
    "experiment",
    "depends_on",
    "status",
)
EPICS = (
    "foundation",
    "data",
    "training",
    "quality",
    "extended",
    "reliability",
    "product",
    "deploy",
    "final",
)
EPIC_LABELS = {
    "foundation": "Fundamenty",
    "data": "Dane",
    "training": "Modele i trening",
    "quality": "Jakość i odporność",
    "extended": "Rozszerzenia",
    "reliability": "Wiarygodność",
    "product": "Produkt (API/UI)",
    "deploy": "Wdrożenie",
    "final": "Finalizacja",
}
OWNERS = ("A", "B", "C")
SIZES = {"S": 0.5, "M": 1.5, "L": 3.0}  # planned person-days, used for the critical path
LEVELS = ("MVP", "Core", "Extended")
GATES = ("G1", "G2", "G3", "G4", "G5", "G6", "none")
EXPERIMENTS = tuple(f"E{i:02d}" for i in range(12)) + ("none",)
STATUSES = ("todo", "in_progress", "review", "done", "blocked", "dropped")
STATUS_ICONS = {
    "todo": "⬜",
    "in_progress": "🟨",
    "review": "🟦",
    "done": "✅",
    "blocked": "⛔",
    "dropped": "➖",
}
REQUIRED_SECTIONS = (
    "## Kontekst",
    "## Cel",
    "## Zakres",
    "## Kryteria akceptacji",
    "## Weryfikacja",
)
WEEKS = range(1, 15)


# --------------------------------------------------------------------------- parsing


@dataclass
class Task:
    path: Path
    meta: dict[str, object]
    body: str
    errors: list[str] = field(default_factory=list)

    @property
    def id(self) -> str:
        return str(self.meta.get("id", ""))

    @property
    def title(self) -> str:
        return str(self.meta.get("title", ""))

    @property
    def deps(self) -> list[str]:
        value = self.meta.get("depends_on", [])
        return list(value) if isinstance(value, list) else []

    @property
    def status(self) -> str:
        return str(self.meta.get("status", ""))

    @property
    def week(self) -> int:
        value = self.meta.get("week", 0)
        return value if isinstance(value, int) else 0

    def rel(self) -> str:
        return self.path.relative_to(ROOT).as_posix()


def _parse_scalar(raw: str) -> object:
    value = raw.strip()
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        return (
            [item.strip().strip("'\"") for item in inner.split(",") if item.strip()]
            if inner
            else []
        )
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    return value


def parse_front_matter(text: str) -> tuple[dict[str, object], str, list[str]]:
    """Parse the simple YAML subset used in task cards: `key: scalar` and `key: [a, b]`."""
    errors: list[str] = []
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text, ["missing front matter (first line must be ---)"]
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return {}, text, ["unterminated front matter"]
    meta: dict[str, object] = {}
    for number, line in enumerate(lines[1:end], start=2):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            errors.append(f"line {number}: expected `key: value`")
            continue
        key, raw = line.split(":", 1)
        if " #" in raw and not raw.strip().startswith(("'", '"')):
            raw = raw.split(" #", 1)[0]
        meta[key.strip()] = _parse_scalar(raw)
    body = "\n".join(lines[end + 1 :])
    return meta, body, errors


def load_tasks() -> list[Task]:
    tasks: list[Task] = []
    for path in sorted(TASKS_DIR.glob("T*.md")):
        if not TASK_FILE_RE.match(path.name):
            continue
        meta, body, errors = parse_front_matter(path.read_text(encoding="utf-8"))
        tasks.append(Task(path=path, meta=meta, body=body, errors=errors))
    return tasks


def task_map(tasks: Sequence[Task]) -> dict[str, Task]:
    return {t.id: t for t in tasks}


# --------------------------------------------------------------------------- validation


def validate_tasks(tasks: Sequence[Task]) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    seen: dict[str, Path] = {}
    for t in tasks:
        where = t.rel()
        errors.extend(f"{where}: {e}" for e in t.errors)
        missing = [k for k in REQUIRED_KEYS if k not in t.meta]
        if missing:
            errors.append(f"{where}: missing keys {missing}")
            continue
        file_id = TASK_FILE_RE.match(t.path.name).group(1)  # type: ignore[union-attr]
        if t.id != file_id:
            errors.append(f"{where}: id {t.id!r} does not match file name ({file_id})")
        if t.id in seen:
            errors.append(f"{where}: duplicate id {t.id} (also in {seen[t.id].name})")
        seen[t.id] = t.path
        checks = (
            ("epic", EPICS),
            ("owner", OWNERS),
            ("reviewer", OWNERS),
            ("size", tuple(SIZES)),
            ("level", LEVELS),
            ("gate", GATES),
            ("experiment", EXPERIMENTS),
            ("status", STATUSES),
        )
        for key, allowed in checks:
            if t.meta[key] not in allowed:
                errors.append(f"{where}: {key}={t.meta[key]!r} not in {list(allowed)}")
        if t.meta["owner"] == t.meta["reviewer"]:
            errors.append(f"{where}: reviewer must differ from owner")
        if t.week not in WEEKS:
            errors.append(f"{where}: week={t.meta['week']!r} must be an integer 1-14")
        if not isinstance(t.meta["depends_on"], list):
            errors.append(f"{where}: depends_on must be a list like [T101, T102]")
        heading = f"# {t.id} — "
        if heading not in t.body:
            errors.append(f"{where}: body must contain a heading starting with {heading!r}")
        for section in REQUIRED_SECTIONS:
            if not re.search(rf"^{re.escape(section)}\s*$", t.body, flags=re.M):
                errors.append(f"{where}: missing section {section!r}")

    by_id = task_map(tasks)
    for t in tasks:
        for dep in t.deps:
            if dep == t.id:
                errors.append(f"{t.rel()}: depends on itself")
            elif dep not in by_id:
                errors.append(f"{t.rel()}: unknown dependency {dep}")
            else:
                d = by_id[dep]
                if d.week > t.week:
                    warnings.append(
                        f"{t.id} (week {t.week}) depends on {dep} planned later (week {d.week})"
                    )
                if t.meta.get("level") in ("MVP", "Core") and d.meta.get("level") == "Extended":
                    warnings.append(
                        f"{t.id} ({t.meta.get('level')}) depends on Extended task {dep}"
                    )
                if t.status == "done" and d.status != "done":
                    warnings.append(f"{t.id} is done but dependency {dep} is {d.status}")
    cycle = find_cycle(tasks)
    if cycle:
        errors.append("dependency cycle: " + " -> ".join(cycle))
    return errors, warnings


def find_cycle(tasks: Sequence[Task]) -> list[str] | None:
    by_id = task_map(tasks)
    state: dict[str, int] = {}
    stack: list[str] = []

    def visit(node: str) -> list[str] | None:
        state[node] = 1
        stack.append(node)
        for dep in by_id[node].deps:
            if dep not in by_id:
                continue
            if state.get(dep) == 1:
                return stack[stack.index(dep) :] + [dep]
            if state.get(dep, 0) == 0:
                found = visit(dep)
                if found:
                    return found
        stack.pop()
        state[node] = 2
        return None

    for tid in sorted(by_id):
        if state.get(tid, 0) == 0:
            found = visit(tid)
            if found:
                return found
    return None


PATH_RE = re.compile(r"(?<![\w./-])((?:docs|tasks)/[\w./-]+\.md|AGENTS\.md|CLAUDE\.md|GEMINI\.md)")
SECTION_RE = re.compile(r"§\s*(\d+)(?:\.\d+)?(?:\s*[–-]\s*§?\s*(\d+))?")
DECISION_RE = re.compile(r"\bD-(\d{3})\b")
TASK_REF_RE = re.compile(r"\bT(\d{3})\b")
EXPERIMENT_REF_RE = re.compile(r"\bE(\d{2})\b")
HYPOTHESIS_REF_RE = re.compile(r"\bH(\d)\b")


def markdown_files() -> list[Path]:
    files = [ROOT / "AGENTS.md", ROOT / "CLAUDE.md", ROOT / "GEMINI.md"]
    files += sorted((ROOT / "docs").glob("*.md"))
    files += sorted(TASKS_DIR.glob("*.md"))
    files += sorted((ROOT / ".github").glob("*.md"))
    files += sorted((ROOT / ".claude" / "commands").glob("*.md"))
    return [f for f in files if f.exists()]


def numbered_sections(path: Path) -> set:
    text = path.read_text(encoding="utf-8")
    return {int(m.group(1)) for m in re.finditer(r"^##\s+(\d+)\.", text, flags=re.M)}


def validate_references(tasks: Sequence[Task]) -> list[str]:
    errors: list[str] = []
    task_ids = {t.id for t in tasks}
    decisions_file = ROOT / "docs" / "decisions.md"
    decisions = set()
    if decisions_file.exists():
        decisions = set(
            re.findall(r"^## D-(\d{3})\b", decisions_file.read_text(encoding="utf-8"), flags=re.M)
        )
    section_cache: dict[Path, set] = {}
    for md in markdown_files():
        rel = md.relative_to(ROOT).as_posix()
        if md.name in ("TEMPLATE.md", "BACKLOG.md"):
            continue
        for lineno, line in enumerate(md.read_text(encoding="utf-8").splitlines(), start=1):
            tokens: list[tuple[int, str, object]] = []
            for m in PATH_RE.finditer(line):
                tokens.append((m.start(), "path", m.group(1)))
            for m in SECTION_RE.finditer(line):
                tokens.append(
                    (m.start(), "sec", (int(m.group(1)), int(m.group(2)) if m.group(2) else None))
                )
            tokens.sort(key=lambda item: item[0])
            current: Path | None = None
            for _, kind, value in tokens:
                if kind == "path":
                    target = ROOT / str(value)
                    if any(marker in str(value) for marker in ("{", "*", "___", "...")):
                        current = None
                        continue
                    if not target.exists():
                        errors.append(f"{rel}:{lineno}: missing file {value}")
                        current = None
                    else:
                        current = target
                elif current is not None:
                    start, end = value  # type: ignore[misc]
                    wanted = range(start, (end or start) + 1)
                    if current not in section_cache:
                        section_cache[current] = numbered_sections(current)
                    for number in wanted:
                        if number not in section_cache[current]:
                            target_rel = current.relative_to(ROOT).as_posix()
                            errors.append(f"{rel}:{lineno}: {target_rel} has no section §{number}")
            for m in DECISION_RE.finditer(line):
                if (
                    decisions
                    and m.group(1) not in decisions
                    and "0xx" not in line
                    and "0yy" not in line
                ):
                    errors.append(f"{rel}:{lineno}: unknown decision D-{m.group(1)}")
            for m in TASK_REF_RE.finditer(line):
                ref = f"T{m.group(1)}"
                if ref not in task_ids and ref != "T000":
                    errors.append(f"{rel}:{lineno}: unknown task {ref}")
            for m in EXPERIMENT_REF_RE.finditer(line):
                if int(m.group(1)) > 11:
                    errors.append(f"{rel}:{lineno}: unknown experiment E{m.group(1)}")
            for m in HYPOTHESIS_REF_RE.finditer(line):
                if not 1 <= int(m.group(1)) <= 6:
                    errors.append(f"{rel}:{lineno}: unknown hypothesis H{m.group(1)}")
    return errors


# --------------------------------------------------------------------------- planning


def critical_path(
    tasks: Sequence[Task], levels: Sequence[str] = ("MVP", "Core")
) -> tuple[float, list[str]]:
    """Longest path (sum of planned person-days) through tasks of the given levels."""
    by_id = {t.id: t for t in tasks if t.meta.get("level") in levels}
    best: dict[str, tuple[float, list[str]]] = {}

    def longest(tid: str) -> tuple[float, list[str]]:
        if tid in best:
            return best[tid]
        task = by_id[tid]
        own = SIZES.get(str(task.meta.get("size")), 1.0)
        candidates = [longest(d) for d in task.deps if d in by_id]
        prev = max(candidates, key=lambda c: c[0]) if candidates else (0.0, [])
        best[tid] = (prev[0] + own, prev[1] + [tid])
        return best[tid]

    results = [longest(tid) for tid in sorted(by_id)]
    return max(results, key=lambda r: r[0]) if results else (0.0, [])


def short_title(title: str, limit: int = 38) -> str:
    return title if len(title) <= limit else title[: limit - 1].rstrip() + "…"


def mermaid_graph(tasks: Sequence[Task]) -> str:
    lines = ["flowchart LR"]
    for epic in EPICS:
        members = [t for t in tasks if t.meta.get("epic") == epic]
        if not members:
            continue
        lines.append(f'  subgraph {epic} ["{EPIC_LABELS[epic]}"]')
        for t in members:
            label = short_title(t.title).replace('"', "'")
            lines.append(f'    {t.id}["{t.id} {label}"]')
        lines.append("  end")
    for t in tasks:
        for dep in t.deps:
            lines.append(f"  {dep} --> {t.id}")
    lines.append("  classDef done fill:#d1fae5,stroke:#059669;")
    lines.append("  classDef in_progress fill:#fef3c7,stroke:#d97706;")
    lines.append("  classDef review fill:#dbeafe,stroke:#2563eb;")
    lines.append("  classDef blocked fill:#fee2e2,stroke:#dc2626;")
    lines.append("  classDef extended stroke-dasharray: 4 3;")
    for status in ("done", "in_progress", "review", "blocked"):
        ids = [t.id for t in tasks if t.status == status]
        if ids:
            lines.append(f"  class {','.join(ids)} {status};")
    ext = [
        t.id
        for t in tasks
        if t.meta.get("level") == "Extended"
        and t.status not in ("done", "in_progress", "review", "blocked")
    ]
    if ext:
        lines.append(f"  class {','.join(ext)} extended;")
    return "\n".join(lines)


def render_backlog(tasks: Sequence[Task]) -> str:
    out: list[str] = []
    out.append("# Backlog CardioAI")
    out.append("")
    out.append(
        "> Plik generowany przez `python scripts/tasks.py "
        "backlog` z front matter kart `tasks/T###-*.md`. "
        "Nie edytuj ręcznie —"
    )
    out.append("> zmień kartę i wygeneruj ponownie. Opis procesu: `tasks/README.md`.")
    out.append("")

    total = len(tasks)
    done = sum(1 for t in tasks if t.status == "done")
    out.append("## Podsumowanie")
    out.append("")
    out.append(
        f"Zadań: **{total}**, ukończonych: **{done}** "
        f"({(100 * done / total) if total else 0:.0f}%)."
    )
    out.append("")
    out.append("| Poziom | Zadania | Osobodni (plan) | Ukończone |")
    out.append("|---|---|---|---|")
    for level in LEVELS:
        lv = [t for t in tasks if t.meta.get("level") == level]
        days = sum(SIZES.get(str(t.meta.get("size")), 0) for t in lv)
        out.append(
            f"| {level} | {len(lv)} | {days:.1f} | {sum(1 for t in lv if t.status == 'done')} |"
        )
    out.append("")
    out.append("| Osoba | Rola | Zadania | Osobodni (plan) |")
    out.append("|---|---|---|---|")
    roles = {"A": "Data & Signal ML", "B": "Model & Experiments", "C": "Reliability & Product"}
    for owner in OWNERS:
        ow = [t for t in tasks if t.meta.get("owner") == owner]
        days = sum(SIZES.get(str(t.meta.get("size")), 0) for t in ow)
        out.append(f"| {owner} | {roles[owner]} | {len(ow)} | {days:.1f} |")
    out.append("")

    out.append("## Bramki jakościowe")
    out.append("")
    out.append("| Bramka | Zadania | Postęp |")
    out.append("|---|---|---|")
    for gate in GATES[:-1]:
        gt = [t for t in tasks if t.meta.get("gate") == gate]
        ids = ", ".join(t.id for t in gt)
        out.append(f"| {gate} | {ids} | {sum(1 for t in gt if t.status == 'done')}/{len(gt)} |")
    out.append("")
    out.append("Warunki przejścia bramek: `tasks/README.md` §5.")
    out.append("")

    out.append("## Wszystkie zadania")
    out.append("")
    out.append(
        "| ID | Zadanie | Epik | Wł. | Rec. | Tydz. "
        "| Rozm. | Poziom | Bramka | Eksp. | Zależy "
        "od | Status |"
    )
    out.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for t in sorted(tasks, key=lambda x: x.id):
        m = t.meta
        deps = ", ".join(t.deps) if t.deps else "—"
        icon = STATUS_ICONS.get(t.status, "")
        out.append(
            f"| [{t.id}]({t.path.name}) | {t.title} | {EPIC_LABELS.get(str(m['epic']), m['epic'])} "
            f"| {m['owner']} | {m['reviewer']} "
            f"| {m['week']} | {m['size']} | {m['level']} "
            f"| {m['gate'] if m['gate'] != 'none' else '—'} "
            f"| {m['experiment'] if m['experiment'] != 'none' else '—'} "
            f"| {deps} | {icon} {t.status} |"
        )
    out.append("")

    out.append("## Plan tygodniowy")
    out.append("")
    out.append(
        "Rozmiary: S ≈ 0,5 dnia, M ≈ 1–2 dni, L ≈ "
        "3+ dni pracy z agentem. Zadania Extended "
        "zaznaczono kursywą."
    )
    out.append("")
    out.append(
        "| Tydzień | A — Data & Signal ML | B — Model & Experiments | C — Reliability & Product |"
    )
    out.append("|---|---|---|---|")
    for week in WEEKS:
        cells = []
        for owner in OWNERS:
            items = [t for t in tasks if t.week == week and t.meta.get("owner") == owner]
            parts = []
            for t in sorted(items, key=lambda x: x.id):
                label = f"{t.id} ({t.meta['size']})"
                parts.append(f"*{label}*" if t.meta.get("level") == "Extended" else label)
            cells.append(", ".join(parts) if parts else "—")
        out.append(f"| {week} | {cells[0]} | {cells[1]} | {cells[2]} |")
    out.append("")

    length, path = critical_path(tasks)
    out.append("## Ścieżka krytyczna (MVP + Core)")
    out.append("")
    out.append(f"Najdłuższy łańcuch zależności: **{length:.1f} osobodnia** pracy sekwencyjnej.")
    out.append("")
    by_id = task_map(tasks)
    out.append(" → ".join(f"{tid} {short_title(by_id[tid].title, 30)}" for tid in path))
    out.append("")
    out.append("Opóźnienie dowolnego zadania z tej listy przesuwa zamrożenie modelu (T801).")
    out.append("")

    out.append("## Graf zależności")
    out.append("")
    out.append("```mermaid")
    out.append(mermaid_graph(tasks))
    out.append("```")
    out.append("")
    return "\n".join(out)


# --------------------------------------------------------------------------- commands


def cmd_check(_: argparse.Namespace) -> int:
    tasks = load_tasks()
    errors, warnings = validate_tasks(tasks)
    errors += validate_references(tasks)
    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")
    print(f"{len(tasks)} task cards, {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


def cmd_backlog(_: argparse.Namespace) -> int:
    tasks = load_tasks()
    errors, _warnings = validate_tasks(tasks)
    if errors:
        for e in errors:
            print(f"ERROR {e}")
        print("Fix the errors above before generating the backlog.")
        return 1
    BACKLOG_PATH.write_text(render_backlog(tasks), encoding="utf-8", newline="\n")
    print(f"written {BACKLOG_PATH.relative_to(ROOT).as_posix()} ({len(tasks)} tasks)")
    return 0


def cmd_next(args: argparse.Namespace) -> int:
    tasks = load_tasks()
    by_id = task_map(tasks)
    ready = [
        t
        for t in tasks
        if t.status == "todo"
        and all(by_id.get(d) is not None and by_id[d].status == "done" for d in t.deps)
        and (args.owner is None or t.meta.get("owner") == args.owner)
    ]
    if not ready:
        print("no ready tasks")
        return 0
    for t in sorted(ready, key=lambda x: (x.week, x.id)):
        m = t.meta
        print(f"{t.id}  week {m['week']:>2}  {m['owner']}  {m['size']}  {m['level']:<8}  {t.title}")
    return 0


def find_task(tasks: Sequence[Task], tid: str) -> Task | None:
    tid = tid.upper()
    return next((t for t in tasks if t.id == tid), None)


def cmd_show(args: argparse.Namespace) -> int:
    tasks = load_tasks()
    t = find_task(tasks, args.task_id)
    if t is None:
        print(f"unknown task {args.task_id}")
        return 1
    by_id = task_map(tasks)
    print(f"{t.id} — {t.title}")
    print(f"file:     {t.rel()}")
    for key in (
        "epic",
        "owner",
        "reviewer",
        "week",
        "size",
        "level",
        "gate",
        "experiment",
        "status",
    ):
        print(f"{key + ':':<10}{t.meta.get(key)}")
    print("depends on:")
    if not t.deps:
        print("  (none)")
    blocked = False
    for dep in t.deps:
        d = by_id.get(dep)
        status = d.status if d else "UNKNOWN"
        blocked = blocked or status != "done"
        print(f"  {dep}  {status:<11} {d.title if d else ''}")
    dependents = [x for x in tasks if t.id in x.deps]
    print("needed by:")
    for x in dependents or []:
        print(f"  {x.id}  {x.status:<11} {x.title}")
    if not dependents:
        print("  (none)")
    print("READY" if not blocked else "BLOCKED: not all dependencies are done")
    return 0


def cmd_set_status(args: argparse.Namespace) -> int:
    if args.status not in STATUSES:
        print(f"status must be one of {list(STATUSES)}")
        return 1
    tasks = load_tasks()
    t = find_task(tasks, args.task_id)
    if t is None:
        print(f"unknown task {args.task_id}")
        return 1
    text = t.path.read_text(encoding="utf-8")
    new_text, count = re.subn(
        r"^status:\s*\S+\s*$", f"status: {args.status}", text, count=1, flags=re.M
    )
    if count != 1:
        print(f"{t.rel()}: status line not found")
        return 1
    t.path.write_text(new_text, encoding="utf-8", newline="\n")
    print(f"{t.id}: {t.status} -> {args.status}")
    return 0


def cmd_graph(_: argparse.Namespace) -> int:
    print(mermaid_graph(load_tasks()))
    return 0


def _quote(value: str) -> str:
    return '"' + value.replace('"', '\\"') + '"'


def cmd_issues(args: argparse.Namespace) -> int:
    tasks = load_tasks()
    repo = f" --repo {args.repo}" if args.repo else ""
    labels = set()
    for t in tasks:
        m = t.meta
        labels.update(
            {f"epic:{m['epic']}", f"owner:{m['owner']}", f"size:{m['size']}", f"level:{m['level']}"}
        )
        if m["gate"] != "none":
            labels.add(f"gate:{m['gate']}")
    print("#!/usr/bin/env bash")
    print("# Review before running. Requires an authenticated GitHub CLI (gh auth login).")
    print("set -euo pipefail")
    for label in sorted(labels):
        print(f"gh label create {_quote(label)}{repo} --force")
    for t in sorted(tasks, key=lambda x: x.id):
        m = t.meta
        flags = [
            f"--label {_quote(lbl)}"
            for lbl in (
                f"epic:{m['epic']}",
                f"owner:{m['owner']}",
                f"size:{m['size']}",
                f"level:{m['level']}",
            )
        ]
        if m["gate"] != "none":
            flags.append(f"--label {_quote('gate:' + str(m['gate']))}")
        title = _quote(f"[{t.id}] {t.title}")
        print(
            f"gh issue create{repo} --title {title} --body-file {_quote(t.rel())} {' '.join(flags)}"
        )
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check").set_defaults(func=cmd_check)
    sub.add_parser("backlog").set_defaults(func=cmd_backlog)
    p_next = sub.add_parser("next")
    p_next.add_argument("--owner", choices=OWNERS)
    p_next.set_defaults(func=cmd_next)
    p_show = sub.add_parser("show")
    p_show.add_argument("task_id")
    p_show.set_defaults(func=cmd_show)
    p_set = sub.add_parser("set-status")
    p_set.add_argument("task_id")
    p_set.add_argument("status")
    p_set.set_defaults(func=cmd_set_status)
    sub.add_parser("graph").set_defaults(func=cmd_graph)
    p_issues = sub.add_parser("issues")
    p_issues.add_argument("--repo")
    p_issues.set_defaults(func=cmd_issues)
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
