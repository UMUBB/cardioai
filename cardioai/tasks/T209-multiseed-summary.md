---
id: T209
title: Uruchamianie wielu seedów i tabele wyników z MLflow (bramka G3)
epic: training
owner: B
reviewer: A
week: 5
size: S
level: MVP
gate: G3
experiment: E03
depends_on: [T208]
status: todo
---

# T209 — Uruchamianie wielu seedów i tabele wyników z MLflow (bramka G3)

## Kontekst

- `docs/evaluation.md` §6 (wiele seedów, kolumny tabeli, istotność), §8 (bootstrap pacjentów)
- `docs/experiments.md` §1, §5 (znaczniki `<!-- BEGIN:Exx -->`)
- `docs/mlops.md` §2, §3, §5 (tagi, metryki, `git_dirty`)
- `tasks/README.md` §5 (G3)

## Cel

Wyniki w dokumentacji i raporcie pochodzą automatycznie z MLflow (średnia ± std z seedów), a ResNet1D jest potwierdzony jako stabilny.

## Zakres

- `scripts/run_seeds.py --config PATH --seeds 0 1 2 [--set ...]` — kolejne treningi z `--set seed=N`.
- `cardioai.tracking.summary`: pobranie runów, agregacja po `config_hash`, tabela Markdown, podmiana treści między znacznikami w dokumentach.
- `scripts/summarize_runs.py --experiment NAME [--write-docs Exx] [--all]` — kolumny z `docs/evaluation.md` §6; domyślnie bez runów `git_dirty=true`.
- `cardioai.evaluation.bootstrap`: bootstrap pacjentów (B = 1000, seed 0) i wariant sparowany (`docs/evaluation.md` §8) — przeniesione z T801; korzysta z nich T801 (przedziały ufności na teście)
  oraz porównania wariantów na val (reguła istotności z §6).
- Uruchomienie 3 seedów dla wybranego wariantu ResNet1D (po E04) i wpis tabel E02–E04 do `docs/experiments.md`.

## Poza zakresem

- Testy statystyczne poza regułą z `docs/evaluation.md` §6 i bootstrapem z §8; wykresy do raportu (T803).

## Pliki

- `src/cardioai/tracking/summary.py` — nowy
- `src/cardioai/evaluation/bootstrap.py` — nowy
- `scripts/run_seeds.py`, `scripts/summarize_runs.py` — nowe
- `docs/experiments.md` — aktualizacja (tabele E01–E04)
- `tests/unit/tracking/test_summary.py`, `tests/unit/evaluation/test_bootstrap.py` — nowe

## Interfejs (wiążący)

```python
def fetch_runs(experiment_names: Sequence[str], *, filter_tags: Mapping[str, str] | None = None,
               include_dirty: bool = False) -> pd.DataFrame: ...
def aggregate_by_config(runs: pd.DataFrame, metrics: Sequence[str]) -> pd.DataFrame: ...   # mean, std, n_seeds
def to_markdown_table(df: pd.DataFrame, columns: Sequence[str], *, float_fmt: str = "{:.3f}") -> str: ...
def update_doc_section(doc_path: Path, marker: str, content: str) -> None: ...             # BEGIN/END:marker

# cardioai.evaluation.bootstrap (przeniesione z T801)
def patient_bootstrap(y_true: np.ndarray, y_prob: np.ndarray, patient_id: np.ndarray, *,
                      metric: Callable[[np.ndarray, np.ndarray], float], n_boot: int = 1000,
                      seed: int = 0, alpha: float = 0.05) -> tuple[float, float, float]: ...   # (estimate, low, high)
def paired_patient_bootstrap(y_true: np.ndarray, prob_a: np.ndarray, prob_b: np.ndarray, patient_id: np.ndarray, *,
                             metric: Callable[[np.ndarray, np.ndarray], float], n_boot: int = 1000,
                             seed: int = 0) -> tuple[float, float, float]: ...                  # różnica A − B
```

## Kryteria akceptacji

- [ ] Bramka G3: ResNet1D na 3 seedach, odchylenie standardowe macro AUROC val ≤ 0,01 (albo opis przyczyny i plan w PR).
- [ ] Tabele E01–E04 w `docs/experiments.md` wygenerowane skryptem; ponowne uruchomienie bez nowych runów nie zmienia pliku.
- [ ] `update_doc_section` zmienia wyłącznie treść między znacznikami; brak znacznika → czytelny błąd.
- [ ] Runy z `git_dirty=true` pominięte domyślnie (flaga `--include-dirty`).
- [ ] Bootstrap: przedziały zawierają estymację punktową; ten sam seed → te same przedziały (test).

## Testy

- `test_summary.py`: agregacja na sztucznej ramce runów, format liczb, podmiana sekcji w pliku tymczasowym, brak znacznika; jeden test z tymczasowym store MLflow.
- `test_bootstrap.py`: deterministyczność, losowanie po pacjentach (wszystkie rekordy pacjenta razem), zbieżność na prostym przykładzie.

## Weryfikacja

```bash
uv run pytest tests/unit/tracking/test_summary.py tests/unit/evaluation/test_bootstrap.py -q
uv run python scripts/run_seeds.py --config configs/experiment/e03_resnet1d.yaml --seeds 0 1 2
uv run python scripts/summarize_runs.py --experiment e03_resnet1d --write-docs E03
```

## Wskazówki i pułapki

- Grupuj po `config_hash`, nie po nazwie runu — nazwa zawiera seed.
- Ten sam config na różnych urządzeniach ma ten sam hash; filtruj po tagu `device` dla tabel finalnych (D-019).
