---
id: T108
title: Pipeline preprocessingu, filtry zerofazowe i resampling
epic: data
owner: A
reviewer: B
week: 4
size: M
level: MVP
gate: G3
experiment: none
depends_on: [T107]
status: todo
---

# T108 — Pipeline preprocessingu, filtry zerofazowe i resampling

## Kontekst

- `docs/data_contract.md` §8 (kolejność transformacji), §9 (`preprocessing_id`), §14 pkt 8 (notch przy 100 Hz)
- `docs/decisions.md`: D-010, D-011, D-023
- `AGENTS.md` §2 pkt 7 (jedna implementacja preprocessingu)

## Cel

Jedna funkcja budująca pipeline z configu — używana przez Dataset w treningu, ewaluacji, robustness i przez `Predictor` w inferencji.

## Zakres

- Filtry: pasmowy Butterworth (`butter(..., output="sos")` + `sosfiltfilt`), notch (`iirnotch` + `filtfilt`), resampling (`resample_poly`).
- Rozszerzenie `preprocessing_id` o identyfikatory filtrów (np. `"bp0.5-40_n50"`, wersja np. `"1:bp0.5-40_n50"`); `PREPROCESSING_CODE_VERSION`, `preprocessing_id` i `preprocessing_version` są zdefiniowane w T107 — T108 je importuje, nie definiuje ich ponownie.
- `build_pipeline` składający kroki 2–9 z `docs/data_contract.md` §8, z miejscami na augmentacje oraz korupcje przekazywane z zewnątrz (T109, T302):
  `corruption` (trening, `train=True`) i `robustness_corruption` (ewaluacja, stosowana w kroku 3 **tylko** przy `train=False`; D-023).
- Domyślna fabryka pipeline'u w `build_dataloaders` (train / eval) korzystająca z `build_pipeline` i pliku statystyk.

## Poza zakresem

- Implementacje augmentacji (T109) i korupcji (T302).

## Pliki

- `src/cardioai/data/filters.py`, `src/cardioai/data/preprocessing.py` — nowe
- `src/cardioai/data/normalization.py` — zmiana (identyfikatory filtrów w `preprocessing_id`)
- `scripts/compute_norm_stats.py` — zmiana (statystyki liczone z filtrem z configu, bez normalizacji; `preprocessing_id` wariantu w nazwie i treści pliku)
- `src/cardioai/data/datamodule.py` — zmiana (domyślna fabryka)
- `tests/unit/data/test_filters.py`, `tests/unit/data/test_preprocessing.py` — nowe

## Interfejs (wiążący)

```python
def bandpass(x: np.ndarray, fs: int, low_hz: float, high_hz: float, order: int = 4) -> np.ndarray: ...
def notch(x: np.ndarray, fs: int, freq_hz: float, quality: float = 30.0) -> np.ndarray: ...
def resample(x: np.ndarray, fs_in: int, fs_out: int) -> np.ndarray: ...       # oś czasu = ostatnia

from cardioai.data.normalization import (       # definiowane w T107; tu tylko import
    PREPROCESSING_CODE_VERSION, preprocessing_id, preprocessing_version)

def build_pipeline(pp_cfg: PreprocessingConfig, *, sampling_rate: int, train: bool, stats: NormStats | None,
                   fs_in: int | None = None, corruption: Transform | None = None,
                   robustness_corruption: Transform | None = None,
                   physical_augs: Sequence[Transform] = (),
                   normalized_augs: Sequence[Transform] = ()) -> Compose: ...
```

Funkcja przyjmuje tylko sekcję `preprocessing` (a nie cały `RunConfig`), bo `Predictor` (T603) odtwarza ją z `bundle.json`.

Krok 3 (korupcje): przy `train=True` działa `corruption`, a `robustness_corruption` jest ignorowane z ostrzeżeniem; przy `train=False`
działa wyłącznie `robustness_corruption` (przed filtrem i normalizacją), a `corruption` oraz wszystkie augmentacje są ignorowane (D-023).

## Kryteria akceptacji

- [ ] Kolejność kroków dokładnie jak w `docs/data_contract.md` §8; przy `train=False` augmentacje i `corruption` są ignorowane (nawet jeśli przekazane) z ostrzeżeniem, a `robustness_corruption` jest stosowane w kroku 3 (D-023).
- [ ] Filtr pasmowy 0,5–40 Hz przy 100 Hz: sinus 10 Hz zachowany (amplituda ±1%, przesunięcie fazowe 0 próbek), składowa 0,05 Hz stłumiona ≥ 20 dB.
- [ ] `notch_hz ≥ fs/2` → `ConfigError` przy budowie pipeline'u.
- [ ] `resample(x, 500, 100)` daje `[12, 1000]` dla `[12, 5000]`; kształty i float32 zachowane we wszystkich krokach.
- [ ] `preprocessing_id` rozróżnia warianty z filtrami (np. `bp0.5-40_n50`); `preprocessing_version` trafia do checkpointu (T204) i bundla (T601) — funkcja z T107 jest jedynym źródłem tej wartości (T108 jej nie redefiniuje).
- [ ] Bez filtrów (`bandpass: null`) pipeline nie wywołuje żadnej funkcji z `filters.py` (D-011).

## Testy

- `test_filters.py`: zero-phase (korelacja wzajemna), tłumienie, notch przy 500 Hz, resampling (długość, energia).
- `test_preprocessing.py`: kolejność kroków (transformy-szpiedzy zapisujące wywołania), `train=False`, `preprocessing_id` dla kilku configów;
  przy `train=False` korupcja z `robustness_corruption` jest stosowana przed filtrem i normalizacją, a augmentacje nie są stosowane;
  zgodność `preprocessing_id`: plik statystyk policzony przez `compute_norm_stats.py` dla configu z filtrem ma `preprocessing_id` równy `preprocessing_id(cfg)`
  i jest akceptowany przez `Normalize` w `build_pipeline` z tym samym configiem (a dla innego wariantu filtra → `NormStatsMismatchError`).

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_filters.py tests/unit/data/test_preprocessing.py -q
```

## Wskazówki i pułapki

- `sosfiltfilt` działa wzdłuż `axis=-1` — sygnał ma kształt `[12, T]`.
- Przy 100 Hz górna częstotliwość 40 Hz jest blisko Nyquista (50 Hz) — test zbocza rób na częstotliwościach w paśmie i daleko poza nim.
