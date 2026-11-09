---
id: T107
title: Statystyki normalizacji z train i transformacja Normalize
epic: data
owner: A
reviewer: B
week: 3
size: S
level: MVP
gate: G1
experiment: none
depends_on: [T105]
status: todo
---

# T107 — Statystyki normalizacji z train i transformacja Normalize

## Kontekst

- `docs/data_contract.md` §8 (krok 6), §9 (tryby i plik statystyk)
- `AGENTS.md` §2 pkt 3 (statystyki tylko z train)

## Cel

Normalizacja per odprowadzenie liczona wyłącznie na train, zapisana w wersjonowanym pliku i weryfikowana przy użyciu —
ta sama w treningu, ewaluacji i inferencji.

## Zakres

- Strumieniowe liczenie średniej i odchylenia per odprowadzenie (float64 w NumPy, np. algorytm Welforda lub sumy) na datasecie train
  z pipeline'em bez augmentacji, bez korupcji i bez normalizacji.
- `NormStats` z zapisem i odczytem JSON (§9) oraz kontrolą zgodności `sampling_rate`, `preprocessing_id`, `leads`.
- `Normalize` (Transform): tryby `per_lead_train`, `per_record`, `none`; wynik float32.
- `scripts/compute_norm_stats.py` (ścieżka domyślna z §2).
- `PREPROCESSING_CODE_VERSION`, `preprocessing_id` i `preprocessing_version` (np. `"1:none"`) — jedyne źródło tych wartości w projekcie;
  T108 je importuje i rozszerza o identyfikatory filtrów.

## Poza zakresem

- Identyfikatory wariantów z filtrami w `preprocessing_id` (T108 rozszerza funkcję; tu wystarcza `"none"`, a dla ustawionego `bandpass` lub `notch_hz` — `NotImplementedError` do czasu T108).

## Pliki

- `src/cardioai/data/normalization.py` — nowy (także `PREPROCESSING_CODE_VERSION`, `preprocessing_id`, `preprocessing_version`)
- `scripts/compute_norm_stats.py` — nowy
- `tests/unit/data/test_normalization.py` — nowy

## Interfejs (wiążący)

```python
@dataclass(frozen=True)
class NormStats:
    sampling_rate: int
    preprocessing_id: str
    leads: tuple[str, ...]
    mean: np.ndarray        # [12] float64 w pliku, float32 przy użyciu
    std: np.ndarray         # [12]
    split: str
    folds: tuple[int, ...]
    n_records: int
    index_sha256: str
    std_floor: float = 1e-6
    def to_dict(self) -> dict[str, Any]: ...          # typy proste (do checkpointu i bundla)
    @classmethod
    def from_dict(cls, d: Mapping[str, Any]) -> "NormStats": ...
    def to_json(self, path: Path) -> None: ...
    @classmethod
    def from_json(cls, path: Path) -> "NormStats": ...

def compute_lead_stats(dataset: PTBXLDataset, *, preprocessing_id: str, index_sha256: str,
                       batch_size: int = 256) -> NormStats: ...       # ValueError, gdy dataset.split != "train"
class Normalize:                                                      # Transform
    def __init__(self, mode: Literal["per_lead_train", "per_record", "none"], stats: NormStats | None = None,
                 *, expected_fs: int | None = None, expected_preprocessing_id: str | None = None,
                 eps: float = 1e-6) -> None: ...
def default_norm_stats_path(cfg: RunConfig, preprocessing_id: str) -> Path: ...
class NormStatsMismatchError(ValueError): ...

PREPROCESSING_CODE_VERSION: Final = 1
def preprocessing_id(cfg: PreprocessingConfig) -> str: ...        # T107: "none"; T108 dodaje filtry (np. "bp0.5-40_n50")
def preprocessing_version(cfg: PreprocessingConfig) -> str: ...   # f"{PREPROCESSING_CODE_VERSION}:{preprocessing_id(cfg)}"
```

## Kryteria akceptacji

- [ ] `compute_lead_stats` na datasecie val lub test → `ValueError`; plik ma `split: "train"` i foldy 1–8.
- [ ] Na fixture średnie i odchylenia zgodne z referencją NumPy liczoną na całej tablicy train (`rtol=1e-6`).
- [ ] Plik JSON ma wszystkie pola z `docs/data_contract.md` §9.
- [ ] `Normalize` z niezgodnym `fs` lub `preprocessing_id` → `NormStatsMismatchError`.
- [ ] `per_record` dla płaskiego odprowadzenia nie daje NaN (dolna granica odchylenia).
- [ ] Wyjście zawsze float32.
- [ ] `preprocessing_version(cfg)` daje `"1:none"` dla configu bez filtrów; funkcja jest jedynym źródłem wartości trafiającej do checkpointu (T204) i bundla (T601).

## Testy

- `test_normalization.py`: zgodność z referencją, odmowa dla val/test, round-trip JSON, niezgodności, tryb `per_record`, `none`; `preprocessing_id` i `preprocessing_version` dla configu bez filtrów.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_normalization.py -q
uv run python scripts/compute_norm_stats.py --config configs/experiment/e00_smoke.yaml
```

## Wskazówki i pułapki

- Sumy kwadratów w float32 tracą precyzję przy 17 tys. rekordów × 1000 próbek — akumuluj w float64.
- Statystyki zależą od filtra (krok 4) — nazwa pliku zawiera `preprocessing_id` (D-011).
