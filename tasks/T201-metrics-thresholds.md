---
id: T201
title: Moduł metryk i doboru progów
epic: training
owner: C
reviewer: B
week: 2
size: M
level: MVP
gate: G2
experiment: none
depends_on: [T001]
status: todo
---

# T201 — Moduł metryk i doboru progów

## Kontekst

- `docs/evaluation.md` §1 (zasady), §2 (definicje), §3 (progi), §5 (plik metryk)
- `docs/mlops.md` §3 (nazwy metryk w MLflow)
- `docs/decisions.md`: D-029, D-035 (metryki bez `torchmetrics`)

## Cel

Jedna, przetestowana implementacja wszystkich metryk klasyfikacji i kalibracji, używana przez trening, ewaluację, niezawodność i raporty.

## Zakres

- Metryki z `docs/evaluation.md` §2 (AUROC macro/micro/per klasa, AP, F1, czułość, swoistość, TP/FP/FN/TN, Brier, ECE klasowe, Hamming loss).
- Dobór progów `f1` / `youden` / `fixed` według §3 (siatka 0,01–0,99, remis → bliżej 0,5) i ich stosowanie.
- Spłaszczanie słownika metryk do kluczy MLflow (`val/macro_auroc`, `val/auroc_MI`, …), w tym `val/hamming_loss`, `val/f1_<KLASA>_tuned`, `val/sensitivity_<KLASA>`,
  `val/specificity_<KLASA>`, `val/macro_f1_tuned` (D-029); nazwy tylko ze znaków `[A-Za-z0-9_./-]`.
- Obsługa przypadków brzegowych (klasa bez pozytywów lub negatywów → `NaN` + ostrzeżenie).

## Poza zakresem

- Bootstrap (T209), krzywe risk–coverage (T502), wykresy kalibracji (T501).

## Pliki

- `src/cardioai/evaluation/__init__.py`, `metrics.py`, `thresholds.py` — nowe
- `tests/unit/evaluation/test_metrics.py`, `test_thresholds.py` — nowe

## Interfejs (wiążący)

```python
def classification_metrics(y_true: np.ndarray, y_prob: np.ndarray, *,
                           thresholds: Mapping[str, float] | None = None,
                           class_names: Sequence[str] = SUPERCLASSES, ece_bins: int = 15) -> dict[str, Any]: ...
    # struktura jak docs/evaluation.md §5 (bez pól run_id/checkpoint)
def per_class_auroc(y_true: np.ndarray, y_prob: np.ndarray) -> np.ndarray: ...
def expected_calibration_error(y_true: np.ndarray, y_prob: np.ndarray, n_bins: int = 15) -> float: ...  # 1D, binarnie
def brier_per_class(y_true: np.ndarray, y_prob: np.ndarray) -> np.ndarray: ...
def tune_thresholds(y_true: np.ndarray, y_prob: np.ndarray, *, method: Literal["f1", "youden", "fixed"] = "f1",
                    fixed: float = 0.5, class_names: Sequence[str] = SUPERCLASSES) -> dict[str, float]: ...
def apply_thresholds(y_prob: np.ndarray, thresholds: Mapping[str, float],
                     class_names: Sequence[str] = SUPERCLASSES) -> np.ndarray: ...   # int8 [N, C]
def metrics_to_flat(metrics: Mapping[str, Any], prefix: str) -> dict[str, float]: ...  # klucze z docs/mlops.md §3
```

## Kryteria akceptacji

- [ ] Wyniki zgodne z scikit-learn (tolerancja 1e-9) na losowych danych dla wszystkich metryk z odpowiednikiem w sklearn.
- [ ] ECE: idealnie skalibrowane dane syntetyczne (N = 200 000) → ECE < 0,01; stała predykcja 0,5 przy częstości 0,2 → ECE ≈ 0,3.
- [ ] Remis w doborze progu rozstrzygany na korzyść progu bliższego 0,5 (test).
- [ ] Klasa bez pozytywów → `NaN` w metrykach tej klasy, macro liczone z pominięciem `NaN`, ostrzeżenie w logu.
- [ ] `metrics_to_flat` produkuje dokładnie klucze z `docs/mlops.md` §3 (test na liście oczekiwanych kluczy; każdy klucz pasuje do `[A-Za-z0-9_./-]+`).
- [ ] Moduł nie importuje `torch` ani pakietów `cardioai.models` / `cardioai.training`.

## Testy

- `test_metrics.py`: porównania ze sklearn, ECE, Brier, przypadki brzegowe, kształty wejścia (N×5), typy wyjścia.
- `test_thresholds.py`: `f1`, `youden`, `fixed`, remisy, `apply_thresholds`.

## Weryfikacja

```bash
uv run pytest tests/unit/evaluation -q
uv run lint-imports
```

## Wskazówki i pułapki

- `roc_auc_score(..., average="macro")` zgłasza wyjątek, gdy któraś klasa ma jedną wartość etykiety — licz per klasa i uśredniaj ręcznie z obsługą `NaN`.
- Tę samą implementację ECE użyje kalibracja (T501) — nie twórz drugiej.
