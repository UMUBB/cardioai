---
id: T501
title: Kalibracja prawdopodobieństw i diagramy niezawodności (E09)
epic: reliability
owner: C
reviewer: B
week: 10
size: M
level: Core
gate: G4
experiment: E09
depends_on: [T201, T206]
status: todo
---

# T501 — Kalibracja prawdopodobieństw i diagramy niezawodności (E09)

## Kontekst

- `docs/reliability.md` §1 (kolejność dopasowania, cross-fitting), §5 (metody, format JSON)
- `docs/evaluation.md` §2 (Brier, ECE), §3 (progi po kalibracji)
- `docs/decisions.md`: D-015

## Cel

Prawdopodobieństwa modelu dają się interpretować (0,8 ≈ 80% przypadków pozytywnych), a efekt kalibracji jest zmierzony uczciwie (cross-fitting).

## Zakres

- Protokół `Calibrator` i implementacje `TemperatureScaler` (globalny i per klasa, optymalizacja log T, ograniczenie `[0.05, 20]`),
  `IsotonicCalibrator` (zapis punktów, `np.interp`), `IdentityCalibrator`; serializacja do/z JSON bez pickle.
- `scripts/calibrate.py --predictions predictions_val.parquet --method ...`: dopasowanie na val, ponowny dobór progów na prawdopodobieństwach po kalibracji,
  zapis `calibration.json` i `thresholds.json`, metryki przed/po (Brier, ECE per klasa i macro), wynik cross-fitting (2 połowy val patient-wise),
  reliability diagrams per klasa (15 przedziałów + histogram), log do MLflow (`calibration/`).
- Porównanie metod w E09.

## Poza zakresem

- Abstention (T502), integracja z `Predictor` (T610).

## Pliki

- `src/cardioai/reliability/calibration.py` — nowy
- `scripts/calibrate.py` — nowy
- `tests/unit/reliability/test_calibration.py` — nowy

## Interfejs (wiążący)

```python
class Calibrator(Protocol):
    method: str
    def fit(self, logits: np.ndarray, y: np.ndarray) -> "Calibrator": ...
    def predict_proba(self, logits: np.ndarray) -> np.ndarray: ...       # [N, 5]
    def to_dict(self) -> dict[str, Any]: ...

class TemperatureScaler:
    def __init__(self, *, per_class: bool = True, t_min: float = 0.05, t_max: float = 20.0) -> None: ...
class IsotonicCalibrator:
    def __init__(self, *, min_positives: int = 200) -> None: ...         # klasa z < min_positives pozytywami → metoda niedostępna dla całego modelu: ValueError z listą klas
class IdentityCalibrator: ...

def calibrator_from_dict(d: Mapping[str, Any]) -> Calibrator: ...
def cross_fit_calibration(logits: np.ndarray, y: np.ndarray, patient_id: np.ndarray, *, method: str,
                          seed: int = 0, **kwargs: Any) -> dict[str, float]: ...   # metryki out-of-fold
def reliability_diagram(y_true: np.ndarray, y_prob: np.ndarray, *, n_bins: int = 15, ax: Any | None = None) -> Any: ...
```

## Kryteria akceptacji

- [ ] Odzyskanie znanej temperatury: logity syntetyczne z prawdziwym T = 2 → dopasowane T w przedziale 1,9–2,1.
- [ ] `predict_proba` po `to_dict` → `calibrator_from_dict` identyczne (tolerancja 1e-7).
- [ ] Temperatura nie zmienia AUROC (test); isotonic jest monotoniczna.
- [ ] Isotonic: jeśli którakolwiek klasa ma < 200 pozytywów, `fit` zgłasza `ValueError` z listą tych klas (metoda niedostępna dla całego modelu, `docs/reliability.md` §5); `calibrate.py` raportuje to czytelnie.
- [ ] Cross-fitting dzieli val patient-wise (żaden pacjent w obu połowach).
- [ ] Tabela E09 (kalibracja): ECE i Brier przed/po dla każdej metody, w tym out-of-fold; wybór metody według reguły E09.
- [ ] `calibration.json` i `thresholds.json` (`on_calibrated: true`) zgodne z formatami z dokumentacji.

## Testy

- `test_calibration.py`: odzyskanie T, round-trip JSON, niezmienność AUROC, isotonic, podział cross-fitting, ograniczenie T.

## Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_calibration.py -q
uv run python scripts/calibrate.py --predictions <eval/val/predictions_val.parquet> --method temperature --per-class
```

## Wskazówki i pułapki

- Optymalizuj w NumPy/SciPy (`minimize`, L-BFGS-B na log T) — to mały problem, nie potrzebuje PyTorch.
- Logity bardzo duże (|z| > 30) → licz BCE stabilnie (`np.logaddexp`).
