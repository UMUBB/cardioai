---
id: T203
title: Baseline klasyczny na cechach sygnałowych (E01)
epic: training
owner: C
reviewer: B
week: 3
size: M
level: MVP
gate: G2
experiment: E01
depends_on: [T004, T105, T201]
status: todo
---

# T203 — Baseline klasyczny na cechach sygnałowych (E01)

## Kontekst

- `docs/experiments.md` §4 (E01)
- `docs/evaluation.md` §2, §4 (plik predykcji)
- Specyfikacja §5.1

## Cel

Szybki, niezależny od sieci neuronowych sanity check etykiet, splitu i metryk. Jego wynik to dolny punkt odniesienia dla modeli głębokich.

## Zakres

- Cechy (z surowych mV, per odprowadzenie): średnia, odchylenie, min, max, percentyle (1, 5, 50, 95, 99), skośność, kurtoza, RMS,
  częstość przejść przez zero, względna moc w pasmach 0,5–5 / 5–15 / 15–40 Hz (Welch); globalnie: tętno i odchylenie RR z odprowadzenia II (`find_peaks`).
- Model: `StandardScaler` + `OneVsRestClassifier(LogisticRegression(max_iter=2000))` dopasowany na train; opcjonalnie LightGBM (extra `lgbm`).
  Dopasowanie i predykcja (logity) to czyste funkcje na tablicach NumPy w `cardioai.evaluation.classical` — `scripts/train_classical.py` tylko ładuje dane, wywołuje je i loguje wyniki (skrypt pozostaje cienki).
- Ewaluacja na val: metryki (T201), plik predykcji (logity = log-odds z `predict_proba`, przycięte), log do MLflow.
- Config `configs/experiment/e01_classical.yaml` (`model.name: classical_logreg`, parametry w `model.params`).

## Poza zakresem

- Strojenie hiperparametrów poza `C ∈ {0.1, 1, 10}`.

## Pliki

- `src/cardioai/data/features.py` — nowy
- `src/cardioai/evaluation/classical.py` — nowy (dopasowanie i predykcja na tablicach NumPy)
- `scripts/train_classical.py` — nowy
- `configs/experiment/e01_classical.yaml` — nowy
- `tests/unit/data/test_features.py`, `tests/unit/evaluation/test_classical.py` — nowe

## Interfejs (wiążący)

```python
FEATURE_NAMES: tuple[str, ...]                                   # stała kolejność cech
def extract_features(x: np.ndarray, fs: int) -> np.ndarray: ...  # [12, T] mV -> [F] float32
def extract_feature_matrix(dataset: PTBXLDataset) -> tuple[np.ndarray, np.ndarray, np.ndarray]: ...  # X, y, ecg_id
```

## Kryteria akceptacji

- [ ] macro AUROC na val > 0,70 (sanity); niższy wynik → przegląd etykiet i splitu przed dalszą pracą (komentarz w PR).
- [ ] Scaler i model dopasowane wyłącznie na train (test sprawdza, że funkcja dopasowania dostaje tylko wiersze train).
- [ ] Run w MLflow z tagami (`exp_id=E01`), metrykami `val/...` i artefaktem `eval/val/predictions_val.parquet` w formacie `docs/evaluation.md` §4.
- [ ] Cechy deterministyczne; brak NaN (odprowadzenie płaskie → wartości skończone).
- [ ] Czas na CPU < 15 min dla 100 Hz (podany w PR).

## Testy

- `test_features.py`: kształt i kolejność cech, sygnał płaski, sinus o znanej częstotliwości (moc w paśmie), tętno z syntetycznego EKG fixture'a.
- `test_classical.py`: dopasowanie scalera i modelu wyłącznie na przekazanych wierszach (train), kształt i skończoność logitów na danych syntetycznych.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_features.py tests/unit/evaluation/test_classical.py -q
uv run python scripts/train_classical.py --config configs/experiment/e01_classical.yaml
```

## Wskazówki i pułapki

- `scripts/train_classical.py` nie używa `build_model` — `model.name` służy tylko do nazwy runu.
- Ekstrakcję cech równoległą przez `joblib` rób tylko w skrypcie; funkcje w `features.py` mają być czyste.
