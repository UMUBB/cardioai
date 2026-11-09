---
id: T206
title: Ewaluacja checkpointu, pliki predykcji i metryk
epic: training
owner: B
reviewer: C
week: 4
size: M
level: MVP
gate: G2
experiment: none
depends_on: [T204]
status: todo
---

# T206 — Ewaluacja checkpointu, pliki predykcji i metryk

## Kontekst

- `docs/evaluation.md` §3 (progi), §4 (plik predykcji), §5 (plik metryk), §7 (blokada testu)
- `docs/mlops.md` §2, §3 (logowanie do runu treningowego, artefakty `eval/<split>/`)
- `docs/experiments.md` §4 (E08 — podgrupy używane przez `subgroup_metrics`)

## Cel

Standardowy plik predykcji i metryk dla dowolnego checkpointu — wejście dla progów, kalibracji, quality gate, abstention,
robustness i raportów. Bez tego każda analiza liczyłaby predykcje po swojemu.

## Zakres

- Budowa, zapis i odczyt ramki predykcji (schemat §4, metadane w schemacie parquet).
- Raport per klasa w Markdown, zapis `metrics_<split>.json` (§5), `thresholds.json` (§3) przy `--thresholds tune`.
- `scripts/evaluate.py`: ładowanie checkpointu, odtworzenie pipeline'u z configu w checkpoincie, predykcja przez `predict_loader`,
  metryki, logowanie do runu źródłowego (`resume_run`) w `eval/<split>/`.
- Split `test` wyłącznie przez `require_test_unlocked`.
- `cardioai.evaluation.subgroups.subgroup_metrics` — metryki (n, macro AUROC, ECE) per podgrupa na ramce predykcji; korzysta z niej T402 (E08).
  Obowiązkowe podgrupy (budowane przez wywołującego jako `groups`): płeć i wiek (< 40, 40–60, 60–75, > 75); `device` i `site` opcjonalnie.

## Poza zakresem

- Kalibracja (T501), predykcje na zbiorze z korupcjami (T303).

## Pliki

- `src/cardioai/evaluation/predictions.py`, `src/cardioai/evaluation/report.py`, `src/cardioai/evaluation/subgroups.py` — nowe
- `scripts/evaluate.py` — nowy
- `tests/unit/evaluation/test_predictions.py`, `tests/unit/evaluation/test_subgroups.py`, `tests/integration/test_evaluate_smoke.py` — nowe

## Interfejs (wiążący)

```python
def build_prediction_frame(*, ecg_id: np.ndarray, patient_id: np.ndarray, strat_fold: np.ndarray, y_true: np.ndarray,
                           logits: np.ndarray, quality_logits: np.ndarray | None = None,
                           y_quality: np.ndarray | None = None, prob_cal: np.ndarray | None = None) -> pd.DataFrame: ...
def save_predictions(df: pd.DataFrame, path: Path, *, metadata: Mapping[str, str]) -> None: ...
def load_predictions(path: Path) -> tuple[pd.DataFrame, dict[str, str]]: ...      # walidacja schematu
def arrays_from_frame(df: pd.DataFrame, kind: Literal["y", "logit", "prob", "prob_cal", "qlogit", "yq"]) -> np.ndarray: ...
def per_class_table_md(metrics: Mapping[str, Any]) -> str: ...
def save_metrics_json(metrics: Mapping[str, Any], path: Path, *, run_meta: Mapping[str, str]) -> None: ...

# evaluation/subgroups.py (przeniesione z T402; używane w E08)
def subgroup_metrics(pred: pd.DataFrame, groups: pd.Series, *, min_size: int = 50) -> pd.DataFrame: ...   # n, macro AUROC, ECE per grupa; grupy < min_size oznaczone
```

CLI: `evaluate.py --checkpoint PATH --split {val,test} [--thresholds tune|PATH] [--out DIR] [--run-id ID] [--batch-size N]`.

## Kryteria akceptacji

- [ ] Kolumny i typy pliku predykcji zgodne z `docs/evaluation.md` §4; `load_predictions` odrzuca plik niezgodny.
- [ ] Ewaluacja `best.pt` na val odtwarza najlepszy `val/macro_auroc` z treningu (|Δ| < 1e-6 na CPU).
- [ ] `--thresholds tune` zapisuje `thresholds.json` (`fitted_on: "val"`); `--thresholds PATH` stosuje progi bez ich zmiany.
- [ ] `--split test` bez odblokowania kończy się `LockedSplitError` i kodem wyjścia ≠ 0.
- [ ] Artefakty w MLflow w `eval/val/`: predykcje, metryki, tabela Markdown.

## Testy

- `test_predictions.py`: round-trip parquet z metadanymi, walidacja schematu, `arrays_from_frame`.
- `test_subgroups.py`: metryki per grupa, pominięcie (oznaczenie) małych grup, podgrupy płci i wieku (progi 40 / 60 / 75).
- `test_evaluate_smoke.py`: checkpoint z T204 na fixture → predykcje i metryki; odmowa dla `test`.

## Weryfikacja

```bash
uv run pytest tests/unit/evaluation/test_predictions.py tests/unit/evaluation/test_subgroups.py tests/integration/test_evaluate_smoke.py -q
uv run python scripts/evaluate.py --checkpoint outputs/e02_cnn_small/<run>/checkpoints/best.pt --split val --thresholds tune
```

## Wskazówki i pułapki

- Pipeline odtwarzaj z configu zapisanego w checkpoincie, nie z bieżących plików YAML — inaczej ewaluacja może użyć innego preprocessingu.
- Metadane parquet (`schema.metadata`) są bajtami — koduj UTF-8 i dekoduj przy odczycie.
