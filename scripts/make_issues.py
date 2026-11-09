#!/usr/bin/env python3
"""Generate `scripts/create_issues.sh` — a bash script that creates one detailed GitHub issue per task card.

The issue bodies are assembled from the task cards (`tasks/T###-*.md`) and enriched with facts taken from the
project documents (`docs/`, `AGENTS.md`, `tasks/README.md`): linked context sections, decision titles, the decision
rule of the related experiment, the gate condition, binding project rules for the task's epic and the dependency graph.

Nothing is sent to GitHub by this generator. The generated script is a dry run unless called with `--apply`.

Usage:
    python3 scripts/make_issues.py [--out scripts/create_issues.sh]

Stdlib only; run from anywhere (paths are resolved relative to the repository root).
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "scripts" / "create_issues.sh"
HEREDOC_END = "__ISSUE_BODY_EOF__"
TABLE_END = "__TABLE_EOF__"
LABELS_END = "__LABELS_EOF__"
REPO_TOKEN = "__REPO__"
MAX_BODY_CHARS = 60000  # GitHub limit is 65536

ROLES = {"A": "Data & Signal ML", "B": "Model & Experiments", "C": "Reliability & Product"}
SIZE_TEXT = {
    "S": "S (do pół dnia, ok. 0,5 osobodnia)",
    "M": "M (1–2 osobodni)",
    "L": "L (3+ osobodni) — zacznij od planu do akceptacji (`AGENTS.md` §6 pkt 3), rozważ podział",
}
LEVEL_TEXT = {
    "MVP": "MVP (obowiązkowe)",
    "Core": "Core (obowiązkowe)",
    "Extended": "Extended (po ustabilizowaniu Core)",
}

# Binding rules from AGENTS.md §2, shortened. Keys are the rule numbers.
RULES = {
    1: "**Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.",
    2: "**Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.",
    3: "**Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.",
    4: "**Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.",
    5: "**Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.",
    6: "**Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.",
    7: "**Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.",
    8: "**Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.",
    9: "**Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.",
    10: "**Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.",
    11: "**Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.",
    12: "**Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.",
}
EPIC_RULES = {
    "foundation": (5, 6, 8, 9, 10),
    "data": (1, 2, 3, 4, 6, 7, 8, 9),
    "training": (1, 2, 3, 4, 5, 6, 9, 10),
    "quality": (2, 3, 4, 6, 7, 9),
    "extended": (2, 3, 5, 6, 9, 10),
    "reliability": (2, 3, 5, 6, 11),
    "product": (6, 7, 8, 10, 11, 12),
    "deploy": (8, 10, 12),
    "final": (2, 10, 11),
}
LABEL_COLORS = {
    "epic": "5319e7", "owner": "0e8a16", "gate": "006b75", "exp": "bfd4f2", "week": "ededed", "size": "c5def5",
    "level:MVP": "b60205", "level:Core": "d93f0b", "level:Extended": "fbca04",
}

DOC_FILES = ["AGENTS.md", "tasks/README.md"] + [f"docs/{p.name}" for p in sorted((ROOT / "docs").glob("*.md"))]
SECTION_HEADING_RE = re.compile(r"^(?:##|###)\s+(\d+(?:\.\d+)?)\.\s+(.*?)\s*$")
DECISION_HEADING_RE = re.compile(r"^##\s+(D-\d{3})\s+—\s+(.*?)\s*$")
LINK_TOKEN_RE = re.compile(
    r"`((?:docs|tasks)/[\w./-]+\.md|AGENTS\.md)`"
    r"|§\s*(\d+(?:\.\d+)?)(?:\s*[–-]\s*§?\s*\d+)?"
    r"|\b(D-\d{3})\b"
)
TASK_ID_RE = re.compile(r"\bT\d{3}\b")


def load_tasks_module():
    spec = importlib.util.spec_from_file_location("cardioai_tasks", ROOT / "scripts" / "tasks.py")
    if spec is None or spec.loader is None:  # pragma: no cover
        raise SystemExit("cannot load scripts/tasks.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["cardioai_tasks"] = module  # required by dataclasses with postponed annotations
    spec.loader.exec_module(module)
    return module


def slugify(heading: str) -> str:
    """GitHub heading anchor: lower-case, drop punctuation, spaces to hyphens."""
    return re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")


class DocIndex:
    """Heading anchors of the project documents, so references like `docs/x.md` §8 become deep links."""

    def __init__(self) -> None:
        self.sections: Dict[str, Dict[str, str]] = {}
        self.decisions: Dict[str, Tuple[str, str]] = {}
        for rel in DOC_FILES:
            path = ROOT / rel
            if not path.exists():
                continue
            found: Dict[str, str] = {}
            in_code = False
            for line in path.read_text(encoding="utf-8").splitlines():
                if line.startswith("```"):
                    in_code = not in_code
                if in_code:
                    continue
                m = SECTION_HEADING_RE.match(line)
                if m:
                    found[m.group(1)] = slugify(f"{m.group(1)}. {m.group(2)}")
                d = DECISION_HEADING_RE.match(line)
                if d and rel == "docs/decisions.md":
                    self.decisions[d.group(1)] = (d.group(2), slugify(f"{d.group(1)} — {d.group(2)}"))
            self.sections[rel] = found

    def link_line(self, line: str) -> str:
        """Link paths, `§N` references (to the last path on the line) and D-xxx decisions in one Markdown line."""
        current: Optional[str] = None
        out: List[str] = []
        last = 0
        for m in LINK_TOKEN_RE.finditer(line):
            out.append(line[last:m.start()])
            last = m.end()
            if m.group(1):
                current = m.group(1)
                out.append(f"[`{current}`](https://github.com/{REPO_TOKEN}/blob/main/{current})")
            elif m.group(2):
                anchor = None
                if current:
                    number = m.group(2)
                    table = self.sections.get(current, {})
                    anchor = table.get(number) or table.get(number.split(".")[0])
                if current and anchor:
                    out.append(f"[{m.group(0)}](https://github.com/{REPO_TOKEN}/blob/main/{current}#{anchor})")
                else:
                    out.append(m.group(0))
            else:
                did = m.group(3)
                if did in self.decisions:
                    out.append(f"[{did}](https://github.com/{REPO_TOKEN}/blob/main/docs/decisions.md#{self.decisions[did][1]})")
                else:
                    out.append(did)
        out.append(line[last:])
        return "".join(out)


def split_sections(body: str) -> Dict[str, str]:
    sections: Dict[str, List[str]] = {}
    current: Optional[str] = None
    in_code = False
    for line in body.splitlines():
        if line.startswith("```"):
            in_code = not in_code
        m = None if in_code else re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            current = m.group(1)
            sections[current] = []
        elif current is not None:
            sections[current].append(line)
    return {name: "\n".join(lines).strip("\n") for name, lines in sections.items()}


def mark_task_ids(text: str, own: str, known: set) -> str:
    """Replace `T123` in prose (not in code) with a `{{T123}}` token that the bash script resolves to `T123 (#N)`."""
    out: List[str] = []
    in_fence = False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            out.append(line)
            continue
        if in_fence:
            out.append(line)
            continue
        parts = line.split("`")
        for i in range(0, len(parts), 2):  # even parts are outside inline code
            parts[i] = TASK_ID_RE.sub(
                lambda m: "{{%s}}" % m.group(0) if m.group(0) in known and m.group(0) != own else m.group(0), parts[i]
            )
        out.append("`".join(parts))
    return "\n".join(out)


def parse_experiments() -> Tuple[Dict[str, Tuple[str, List[str]]], Dict[str, str], Dict[str, List[str]], Dict[str, List[str]]]:
    """Return (cards, registry, hypotheses_by_experiment, hypothesis_text) from docs/experiments.md."""
    text = (ROOT / "docs" / "experiments.md").read_text(encoding="utf-8").splitlines()
    cards: Dict[str, Tuple[str, List[str]]] = {}
    registry: Dict[str, str] = {}
    hyp_text: Dict[str, str] = {}
    hyp_by_exp: Dict[str, List[str]] = {}
    current: Optional[str] = None
    for line in text:
        h = re.match(r"^###\s+(E\d{2})\s+—\s+(.*?)\s*$", line)
        if h:
            current = h.group(1)
            cards[current] = (h.group(2), [])
            continue
        if line.startswith("## "):
            current = None
        if current:
            if "<!--" in line or line.strip().startswith("_Brak wyników"):
                continue
            cards[current][1].append(line)
        row = re.match(r"^\|\s*(E\d{2})\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|$", line)
        if row:
            registry[row.group(1)] = (
                f"**Cel decyzyjny:** {row.group(6)} · zadania: {row.group(3)} · właściciel eksperymentu: {row.group(4)} · tydzień: {row.group(5)}"
            )
        hyp = re.match(r"^\|\s*(H\d)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|$", line)
        if hyp:
            hyp_text[hyp.group(1)] = hyp.group(2)
            for exp in re.findall(r"E\d{2}", hyp.group(3)):
                hyp_by_exp.setdefault(exp, []).append(hyp.group(1))
    for key, (title, lines) in cards.items():
        while lines and not lines[-1].strip():
            lines.pop()
        while lines and not lines[0].strip():
            lines.pop(0)
    return cards, registry, hyp_by_exp, hyp_text  # type: ignore[return-value]


def parse_gates() -> Dict[str, Tuple[str, str, str]]:
    gates: Dict[str, Tuple[str, str, str]] = {}
    for line in (ROOT / "tasks" / "README.md").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\|\s*(G\d)\s+—\s+([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|$", line)
        if m:
            gates[m.group(1)] = (m.group(2), m.group(3), m.group(4))
    return gates


def commit_scope(files_section: str) -> str:
    m = re.search(r"src/cardioai/(\w+)/", files_section)
    if m:
        return m.group(1)
    for needle, scope in (("api/cardioai_api", "api"), ("web/", "web"), ("docker/", "deploy"), ("compose.yaml", "deploy"),
                          (".github/", "ci"), ("configs/", "configs"), ("docs/", "docs"), ("scripts/", "scripts")):
        if needle in files_section:
            return scope
    return "repo"


def render_body(task, tasks_by_id, dependants, docs: DocIndex, experiments, gates, known: set) -> str:
    meta = task.meta
    tid = task.id
    sec = split_sections(task.body)
    prose = lambda s: mark_task_ids(s, tid, known)  # noqa: E731
    card_rel = task.rel()
    stem = task.path.stem.lower()  # t103-label-index
    scope = commit_scope(sec.get("Pliki", ""))
    owner, reviewer = str(meta["owner"]), str(meta["reviewer"])
    epic_labels = sys.modules["cardioai_tasks"].EPIC_LABELS
    parts: List[str] = []

    def add(text: str = "") -> None:
        parts.append(text)

    add(f"> Karta zadania w repozytorium (`{card_rel}`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań "
        f"(`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.")
    add()
    # --- Objective -------------------------------------------------------------------------------------------
    add("## 🎯 Cel")
    add()
    add(prose(sec["Cel"]))
    add()
    gate_txt = str(meta["gate"])
    exp_txt = str(meta["experiment"])
    add("| Pole | Wartość |")
    add("|---|---|")
    add(f"| Zadanie | **{tid}** — {task.title} |")
    add(f"| Epik | {epic_labels.get(str(meta['epic']), meta['epic'])} (`{meta['epic']}`) |")
    add(f"| Poziom | {LEVEL_TEXT[str(meta['level'])]} |")
    add(f"| Planowany tydzień | {meta['week']} z 14 |")
    add(f"| Rozmiar | {SIZE_TEXT[str(meta['size'])]} |")
    add(f"| Bramka | {gate_txt if gate_txt == 'none' else gate_txt + ' — ' + gates[gate_txt][0]} |")
    add(f"| Eksperyment | {exp_txt if exp_txt != 'none' else '—'} |")
    add(f"| Właściciel | {owner} ({ROLES[owner]}) |")
    add(f"| Recenzent | {reviewer} ({ROLES[reviewer]}) |")
    add()
    # --- Context ---------------------------------------------------------------------------------------------
    add("## 📚 Kontekst — przeczytaj przed rozpoczęciem")
    add()
    add("Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).")
    add()
    for line in sec["Kontekst"].splitlines():
        add(docs.link_line(prose(line)))
    add()
    # --- Technical details -----------------------------------------------------------------------------------
    add("## 🛠️ Szczegóły techniczne")
    add()
    add("### Zakres")
    add()
    add(prose(sec["Zakres"]))
    add()
    add("### Poza zakresem (wiążące)")
    add()
    add(prose(sec["Poza zakresem"]))
    add()
    add("### Pliki")
    add()
    add(prose(sec["Pliki"]))
    add()
    if "Interfejs (wiążący)" in sec:
        add("### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)")
        add()
        add(prose(sec["Interfejs (wiążący)"]))
        add()
    add("### Testy do napisania")
    add()
    add(prose(sec["Testy"]))
    add()
    add("### Weryfikacja")
    add()
    add(sec["Weryfikacja"])
    add()
    add("### Wskazówki i pułapki")
    add()
    add(prose(sec["Wskazówki i pułapki"]))
    add()
    # --- Experiment ------------------------------------------------------------------------------------------
    cards, registry, hyp_by_exp, hyp_text = experiments
    if exp_txt != "none" and exp_txt in cards:
        title, lines = cards[exp_txt]
        add(f"## 🧪 Eksperyment {exp_txt} — {title}")
        add()
        if exp_txt in registry:
            add(docs.link_line(prose(registry[exp_txt])))
            add()
        hyps = hyp_by_exp.get(exp_txt, [])
        if hyps:
            add("**Hipotezy powiązane z eksperymentem:**")
            add()
            for h in hyps:
                add(f"- {h}: {hyp_text[h]}")
            add()
        add(f"Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):")
        add()
        for line in lines:
            add(prose(line))
        add()
        add("Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w "
            "`docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.")
        add()
    # --- Rules -----------------------------------------------------------------------------------------------
    add("## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu")
    add()
    add("Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:")
    add()
    for number in EPIC_RULES[str(meta["epic"])]:
        add(f"{number}. {RULES[number]}")
    add()
    # --- Sources / decisions ---------------------------------------------------------------------------------
    add("## 🔎 Źródła i decyzje")
    add()
    add(f"- Karta zadania: [`{card_rel}`](https://github.com/{REPO_TOKEN}/blob/main/{card_rel})")
    decision_ids = sorted(set(re.findall(r"\bD-\d{3}\b", task.body)))
    # decisions mentioned only inside prose of enriched sections are also covered by task.body
    for did in decision_ids:
        if did in docs.decisions:
            name, anchor = docs.decisions[did]
            add(f"- Decyzja [{did}](https://github.com/{REPO_TOKEN}/blob/main/docs/decisions.md#{anchor}) — {name}")
    add("- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/" + REPO_TOKEN + "/blob/main/tasks/BACKLOG.md)")
    add("- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`")
    add()
    # --- Size ------------------------------------------------------------------------------------------------
    add(f"📏 **Szacowany rozmiar:** {SIZE_TEXT[str(meta['size'])]}")
    add()
    # --- Acceptance criteria ---------------------------------------------------------------------------------
    add("## ✅ Kryteria akceptacji")
    add()
    add(prose(sec["Kryteria akceptacji"]))
    add()
    add("**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:")
    add()
    add("- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).")
    add("- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.")
    add("- [ ] `uv run lint-imports` bez naruszeń.")
    add("- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.")
    add('- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.')
    if "web/" in sec.get("Pliki", ""):
        add("- [ ] Frontend: `cd web && npm run lint && npm run typecheck && npm test` bez błędów.")
    add("- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.")
    add("- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).")
    add("- [ ] Brak danych, checkpointów i sekretów w diffie.")
    add("- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.")
    add(f"- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status {tid} review`); PR zatwierdzony przez recenzenta ({reviewer}); CI zielone.")
    add()
    # --- Dependencies ----------------------------------------------------------------------------------------
    add("## 🔗 Zależności")
    add()
    deps = task.deps
    if deps:
        add("**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):")
        add()
        for d in deps:
            dt = tasks_by_id[d]
            add(f"- {{{{{d}}}}} — {dt.title} (tydzień {dt.week}, właściciel {dt.meta['owner']})")
    else:
        add("**Blokowane przez:** brak — zadanie można zacząć od razu.")
    add()
    nxt = dependants.get(tid, [])
    if nxt:
        add("**Odblokowuje:**")
        add()
        for d in nxt:
            dt = tasks_by_id[d]
            add(f"- {{{{{d}}}}} — {dt.title} (tydzień {dt.week}, właściciel {dt.meta['owner']})")
    else:
        add("**Odblokowuje:** brak bezpośrednich zależnych kart.")
    add()
    if gate_txt != "none":
        gname, gcond, gweek = gates[gate_txt]
        members = sorted(t.id for t in tasks_by_id.values() if t.meta["gate"] == gate_txt)
        add(f"**Bramka {gate_txt} — {gname}** (tydzień {gweek}): {gcond}.")
        add()
        add("Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek "
            "(przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). "
            "Zadania bramki: " + ", ".join("{{%s}}" % m for m in members) + ".")
    else:
        add("**Bramka:** zadanie nie należy do żadnej bramki jakościowej.")
    add()
    # --- Workflow --------------------------------------------------------------------------------------------
    add("## 🧭 Jak zacząć")
    add()
    add(f"1. `python3 scripts/tasks.py show {tid}` — sprawdź, czy zależności mają status `done`.")
    add("2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.")
    add("3. Wypisz krótki plan (pliki, publiczne interfejsy, testy)" + (" i **poczekaj na jego akceptację** (rozmiar L)." if meta["size"] == "L" else "."))
    add(f"4. Gałąź: `{stem}`; status karty `in_progress` (`python3 scripts/tasks.py set-status {tid} in_progress`).")
    add("5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.")
    add("6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.")
    add(f"7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat({scope}): <description> [{tid}]`.")
    add(f"8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task {tid}`.")
    add()
    add(f"W Claude Code zadanie realizuje komenda `/task {tid}`.")
    body = "\n".join(parts).rstrip() + "\n"
    if HEREDOC_END in body:
        raise SystemExit(f"{tid}: body contains heredoc terminator")
    if len(body) > MAX_BODY_CHARS:
        raise SystemExit(f"{tid}: body too long ({len(body)} chars)")
    return body


def topological_order(tasks) -> List:
    by_id = {t.id: t for t in tasks}
    done: List[str] = []
    remaining = sorted(by_id)
    while remaining:
        ready = [i for i in remaining if all(d in done for d in by_id[i].deps)]
        if not ready:
            raise SystemExit("dependency cycle")
        chosen = ready[0]
        done.append(chosen)
        remaining.remove(chosen)
    return [by_id[i] for i in done]


def label_specs(tasks, gates, experiments) -> List[Tuple[str, str, str]]:
    cards, _, _, _ = experiments
    epic_labels = sys.modules["cardioai_tasks"].EPIC_LABELS
    specs: Dict[str, Tuple[str, str]] = {}
    for t in tasks:
        m = t.meta
        specs[f"epic:{m['epic']}"] = (LABEL_COLORS["epic"], f"Epik: {epic_labels.get(str(m['epic']), m['epic'])}")
        specs[f"owner:{m['owner']}"] = (LABEL_COLORS["owner"], f"Właściciel {m['owner']} — {ROLES[str(m['owner'])]}")
        specs[f"size:{m['size']}"] = (LABEL_COLORS["size"], f"Rozmiar {SIZE_TEXT[str(m['size'])].split(' — ')[0]}")
        specs[f"level:{m['level']}"] = (LABEL_COLORS[f"level:{m['level']}"], f"Poziom: {LEVEL_TEXT[str(m['level'])]}")
        specs[f"week:{m['week']}"] = (LABEL_COLORS["week"], f"Planowany tydzień {m['week']}")
        if m["gate"] != "none":
            specs[f"gate:{m['gate']}"] = (LABEL_COLORS["gate"], f"Bramka {m['gate']} — {gates[str(m['gate'])][0]}")
        if m["experiment"] != "none":
            title = cards.get(str(m["experiment"]), ("", []))[0]
            specs[f"exp:{m['experiment']}"] = (LABEL_COLORS["exp"], f"Eksperyment {m['experiment']} — {title}"[:100])
    return [(name, color, desc[:100]) for name, (color, desc) in sorted(specs.items())]


def task_labels(task) -> str:
    m = task.meta
    labels = [f"epic:{m['epic']}", f"level:{m['level']}", f"size:{m['size']}", f"owner:{m['owner']}", f"week:{m['week']}"]
    if m["gate"] != "none":
        labels.append(f"gate:{m['gate']}")
    if m["experiment"] != "none":
        labels.append(f"exp:{m['experiment']}")
    return ",".join(labels)


SCRIPT_HEAD = r'''#!/usr/bin/env bash
# =============================================================================
# CardioAI — tworzenie GitHub Issues z kart zadań (tasks/T###-*.md)
#
# PLIK GENEROWANY przez scripts/make_issues.py — nie edytuj go ręcznie.
# Zmień kartę (tasks/T###-*.md) i wygeneruj ponownie:  python3 scripts/make_issues.py
#
# Domyślnie skrypt działa na sucho (nic nie jest wysyłane do GitHuba).
#
# Użycie:
#   bash scripts/create_issues.sh --dump ./issues-preview      # podgląd treści issues jako pliki .md (dry run)
#   bash scripts/create_issues.sh --apply --repo ORG/REPO      # utworzenie etykiet i issues
#
# Opcje:
#   --apply        faktycznie wykonaj polecenia `gh` (wymaga `gh auth login`)
#   --repo ORG/R   repozytorium docelowe (domyślnie bieżące repo wykryte przez `gh repo view`)
#   --only T103,T104  ogranicz do wskazanych zadań
#   --dump DIR     zapisz wyrenderowane treści issues do DIR/T###.md
#   --refresh      nadpisz treść już istniejących issues (domyślnie istniejące są pomijane)
#   --yes          nie pytaj o potwierdzenie przy --apply
#   -h, --help     ta pomoc
#
# Zmienne środowiskowe (opcjonalne): ASSIGNEE_A, ASSIGNEE_B, ASSIGNEE_C — loginy GitHub osób A/B/C,
# SLEEP_S — przerwa między tworzonymi issues (domyślnie 2 s, omija limity GitHuba).
#
# Zachowanie:
#  * issues tworzone są w kolejności zależności, więc „Blokowane przez” zawiera od razu linki #N;
#  * po utworzeniu wszystkich issues treść nowych issues jest odświeżana, żeby „Odblokowuje” też miało linki #N;
#  * skrypt jest idempotentny: issue z tytułem zaczynającym się od „[T###]” już istnieje → pomijane.
# =============================================================================
set -euo pipefail

REPO="${REPO:-}"
APPLY=0
DUMP_DIR=""
ONLY=""
REFRESH=0
ASSUME_YES=0
SLEEP_S="${SLEEP_S:-2}"
ASSIGNEE_A="${ASSIGNEE_A:-}"
ASSIGNEE_B="${ASSIGNEE_B:-}"
ASSIGNEE_C="${ASSIGNEE_C:-}"

usage() { awk '/^# ====/ { n++; next } n == 1 { sub(/^# ?/, ""); print } n == 2 { exit }' "$0"; }
die() { echo "BŁĄD: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --repo) [ $# -ge 2 ] || die "--repo wymaga wartości ORG/REPO"; REPO="$2"; shift ;;
    --only) [ $# -ge 2 ] || die "--only wymaga listy zadań"; ONLY="$2"; shift ;;
    --dump) [ $# -ge 2 ] || die "--dump wymaga katalogu"; DUMP_DIR="$2"; shift ;;
    --refresh) REFRESH=1 ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "nieznany argument: $1 (zobacz --help)" ;;
  esac
  shift
done

if [ "$APPLY" = 1 ]; then
  command -v gh >/dev/null 2>&1 || die "brak GitHub CLI (gh) — https://cli.github.com"
  gh auth status >/dev/null 2>&1 || die "zaloguj się: gh auth login"
  if [ -z "$REPO" ]; then
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" || die "nie wykryto repozytorium — podaj --repo ORG/REPO"
  fi
fi
[ -n "$REPO" ] || REPO="ORG/REPO"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MAP="$WORK/map.txt"        # linie: "T103 17" (zadanie, numer issue)
CREATED="$WORK/created.txt"
SED="$WORK/map.sed"
TABLE="$WORK/table.txt"
: > "$MAP"; : > "$CREATED"

build_sed() {
  local tid num
  {
    echo "s|$REPO_TOKEN|$REPO|g"
    while read -r tid num; do
      [ -n "${tid:-}" ] && echo "s|{{$tid}}|$tid (#$num)|g"
    done < "$MAP"
    echo 's|{{\(T[0-9][0-9][0-9]\)}}|\1|g'
  } > "$SED"
}

render() { build_sed; "body_$1" | sed -f "$SED"; }
issue_no() { awk -v id="$1" '$1 == id { print $2 }' "$MAP" | tail -n 1; }
selected() { [ -z "$ONLY" ] && return 0; case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
assignee_for() {
  case "$1" in A) echo "$ASSIGNEE_A" ;; B) echo "$ASSIGNEE_B" ;; C) echo "$ASSIGNEE_C" ;; *) echo "" ;; esac
}

write_labels() { cat > "$WORK/labels.txt" <<'__LABELS_EOF__'
@@LABELS@@
__LABELS_EOF__
}

write_table() { cat > "$TABLE" <<'__TABLE_EOF__'
@@TABLE@@
__TABLE_EOF__
}

# --- treści issues -----------------------------------------------------------------------------------------------
'''.replace("$REPO_TOKEN", REPO_TOKEN)

SCRIPT_TAIL = r'''
# --- wykonanie ---------------------------------------------------------------------------------------------------
write_labels
write_table

TOTAL="$(wc -l < "$TABLE" | tr -d ' ')"
echo "Repozytorium: $REPO · zadań w pliku: $TOTAL · tryb: $([ "$APPLY" = 1 ] && echo APPLY || echo 'dry-run')"

if [ "$APPLY" = 1 ]; then
  if [ "$ASSUME_YES" != 1 ]; then
    printf 'Utworzyć etykiety i issues w %s? [y/N] ' "$REPO"
    read -r answer
    case "$answer" in y|Y|yes|YES) ;; *) echo "Przerwano."; exit 0 ;; esac
  fi
  gh issue list --repo "$REPO" --state all --limit 1000 --json number,title \
    --jq '.[] | select(.title | test("^\\[T[0-9]{3}\\] ")) | "\(.title | .[1:5]) \(.number)"' >> "$MAP" </dev/null
  echo "Istniejące issues z tytułem [T###]: $(wc -l < "$MAP" | tr -d ' ')"
fi

# 1) etykiety
while IFS='|' read -r name color desc; do
  if [ "$APPLY" = 1 ]; then
    gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force </dev/null >/dev/null
  else
    echo "[dry-run] gh label create \"$name\" --repo $REPO --color $color --description \"$desc\" --force"
  fi
done < "$WORK/labels.txt"

# 2) issues w kolejności zależności
[ -z "$DUMP_DIR" ] || mkdir -p "$DUMP_DIR"
while IFS='|' read -r id title labels owner; do
  selected "$id" || continue
  full_title="[$id] $title"
  if [ -n "$(issue_no "$id")" ]; then
    echo "pomijam $id — już istnieje jako #$(issue_no "$id")"
    continue
  fi
  body="$WORK/$id.md"
  render "$id" > "$body"
  [ -z "$DUMP_DIR" ] || cp "$body" "$DUMP_DIR/$id.md"
  assignee="$(assignee_for "$owner")"
  args=(--repo "$REPO" --title "$full_title" --label "$labels" --body-file "$body")
  [ -z "$assignee" ] || args+=(--assignee "$assignee")
  if [ "$APPLY" = 1 ]; then
    url="$(gh issue create "${args[@]}" </dev/null)"
    num="${url##*/}"
    echo "$id $num" >> "$MAP"
    echo "$id $num" >> "$CREATED"
    echo "utworzono $id → $url"
    sleep "$SLEEP_S"
  else
    echo "[dry-run] gh issue create --repo $REPO --title \"$full_title\" --label \"$labels\"${assignee:+ --assignee $assignee} --body-file <$(wc -l < "$body" | tr -d ' ') linii>"
  fi
done < "$TABLE"

# 3) odświeżenie treści: nowe issues dostają linki #N także w sekcji „Odblokowuje”
if [ "$APPLY" = 1 ]; then
  if [ "$REFRESH" = 1 ]; then cp "$MAP" "$WORK/refresh.txt"; else cp "$CREATED" "$WORK/refresh.txt"; fi
  while read -r id num; do
    [ -n "${id:-}" ] || continue
    selected "$id" || continue
    render "$id" > "$WORK/$id.refresh.md"
    gh issue edit "$num" --repo "$REPO" --body-file "$WORK/$id.refresh.md" </dev/null >/dev/null
    echo "odświeżono $id (#$num)"
    sleep "$SLEEP_S"
  done < "$WORK/refresh.txt"
fi

echo "Gotowe."
'''


def generate(out: Path) -> None:
    mod = load_tasks_module()
    tasks = mod.load_tasks()
    errors, warnings = mod.validate_tasks(tasks)
    if errors:
        raise SystemExit("task cards are invalid; run `python3 scripts/tasks.py check` first:\n" + "\n".join(errors))
    tasks_by_id = {t.id: t for t in tasks}
    known = set(tasks_by_id)
    dependants: Dict[str, List[str]] = {}
    for t in tasks:
        for d in t.deps:
            dependants.setdefault(d, []).append(t.id)
    for k in dependants:
        dependants[k].sort()
    docs = DocIndex()
    experiments = parse_experiments()
    gates = parse_gates()
    ordered = topological_order(tasks)

    table_lines: List[str] = []
    functions: List[str] = []
    for t in ordered:
        if "|" in t.title:
            raise SystemExit(f"{t.id}: title contains '|'")
        table_lines.append(f"{t.id}|{t.title}|{task_labels(t)}|{t.meta['owner']}")
        body = render_body(t, tasks_by_id, dependants, docs, experiments, gates, known)
        functions.append(f"body_{t.id}() {{ cat <<'{HEREDOC_END}'\n{body}{HEREDOC_END}\n}}\n")
    labels = "\n".join(f"{n}|{c}|{d}" for n, c, d in label_specs(tasks, gates, experiments))
    head = SCRIPT_HEAD.replace("@@LABELS@@", labels).replace("@@TABLE@@", "\n".join(table_lines))
    out.write_text(head + "\n".join(functions) + SCRIPT_TAIL, encoding="utf-8")
    out.chmod(0o755)
    print(f"wrote {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out} ({len(ordered)} issues)")


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output path (default: scripts/create_issues.sh)")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    generate(args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
