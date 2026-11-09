---
id: T105
title: Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu
epic: data
owner: A
reviewer: B
week: 2
size: M
level: MVP
gate: G1
experiment: none
depends_on: [T002, T003, T103]
status: todo
---

# T105 — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu

## Kontekst

- `docs/data_contract.md` §7 (sygnał, kolejność odprowadzeń), §8 (próbka, pipeline, determinizm), §13 (brakujące odprowadzenia)
- `docs/evaluation.md` §7 (blokada testu)
- `docs/environment.md` §6 (Windows: spawn, pickle)
- `docs/decisions.md`: D-010, D-020

## Cel

Dataset zwracający próbki w formacie z kontraktu, z deterministyczną losowością niezależną od liczby workerów,
punktami rozszerzeń dla kolejnych zadań (pipeline, cache, metadane) i twardą blokadą foldu 10.

## Zakres

- `read_record` z porządkowaniem kanałów po nazwach z nagłówka (bez rozróżniania wielkości liter), kontrolą `fs`, długości, jednostek i NaN/Inf.
- `SignalSample`, protokół `Transform`, `Compose`, `ApplyLeadMask` (krok 8 z §8) — fundament pipeline'u rozwijanego w T107–T109.
- `SignalSource` + `WFDBSource`; `PTBXLDataset` z filtrowaniem splitu i rekordów bez etykiet; `FieldProvider` dla dodatkowych pól (T402, T403).
- `EpochAwareSampler` zwracający `(epoch, index)`; `build_dataset`, `build_dataloader`, `build_dataloaders` z fabryką pipeline'u.
- `cardioai.data.test_lock` (`docs/evaluation.md` §7): `split="test"` bez odblokowania → `LockedSplitError`.

## Poza zakresem

- Cache (T106), normalizacja (T107), filtry i `build_pipeline` (T108), augmentacje (T109), etykiety jakości (T301), metadane (T402).

## Pliki

- `src/cardioai/data/wfdb_io.py`, `transforms.py`, `samplers.py`, `dataset.py`, `datamodule.py`, `test_lock.py` — nowe
- `tests/unit/data/test_wfdb_io.py`, `test_dataset.py`, `test_samplers.py`, `test_test_lock.py` — nowe

## Interfejs (wiążący)

```python
def canonicalize_leads(signal: np.ndarray, names: Sequence[str]) -> np.ndarray: ...   # [12, T] w kolejności LEADS
def read_record(root: Path, rel_path: str, *, expected_fs: int | None = None) -> tuple[np.ndarray, int]: ...
class RecordFormatError(ValueError): ...

@dataclass
class SignalSample:
    x: np.ndarray            # [12, T] float32
    fs: int
    lead_mask: np.ndarray    # [12] bool, True = obecne
    quality: np.ndarray      # [4] int8, etykiety z korupcji (kolejność QUALITY_LABELS)

class Transform(Protocol):
    def __call__(self, s: SignalSample, rng: np.random.Generator) -> SignalSample: ...
class Compose:
    def __init__(self, transforms: Sequence[Transform]) -> None: ...
class ApplyLeadMask: ...                     # x[~lead_mask] = 0.0

class SignalSource(Protocol):
    def get(self, ecg_id: int, rel_path: str) -> np.ndarray: ...   # [12, T] float32, mV
class WFDBSource:
    def __init__(self, root: Path, sampling_rate: int) -> None: ...

class FieldProvider(Protocol):
    def __call__(self, row: Mapping[str, Any]) -> dict[str, torch.Tensor]: ...

class PTBXLDataset(torch.utils.data.Dataset):
    def __init__(self, index: pd.DataFrame, split: Literal["train", "val", "test"], *, sampling_rate: int,
                 source: SignalSource, pipeline: Transform | None = None, seed: int = 0,
                 drop_unlabeled: bool = True, return_quality: bool = False,
                 extra_fields: Sequence[FieldProvider] = ()) -> None: ...
    def __getitem__(self, key: int | tuple[int, int]) -> dict[str, Any]: ...   # key = idx albo (epoch, idx)

class EpochAwareSampler(torch.utils.data.Sampler[tuple[int, int]]):
    def __init__(self, n: int, *, shuffle: bool, seed: int) -> None: ...
    def set_epoch(self, epoch: int) -> None: ...

def build_dataset(cfg: RunConfig, split: str, *, index: pd.DataFrame | None = None,
                  pipeline: Transform | None = None) -> PTBXLDataset: ...
def build_dataloader(dataset: PTBXLDataset, *, batch_size: int, shuffle: bool, num_workers: int,
                     seed: int) -> DataLoader: ...
def build_dataloaders(cfg: RunConfig, splits: Sequence[str] = ("train", "val"), *,
                      pipeline_factory: Callable[[str], Transform | None] | None = None) -> dict[str, DataLoader]: ...

class LockedSplitError(RuntimeError): ...
def is_test_unlocked(repo_root: Path | None = None) -> bool: ...   # CARDIOAI_ALLOW_TEST=1 i release/final_freeze.json
def require_test_unlocked(context: str) -> None: ...
```

## Kryteria akceptacji

- [ ] Próbka ma klucze i kształty z `docs/data_contract.md` §8 (`x`, `y`, `lead_mask`, `ecg_id`, `patient_id`, `fold`; `y_quality` gdy `return_quality`).
- [ ] Rekord z permutowaną kolejnością kanałów w nagłówku (fixture) daje tę samą tablicę co rekord wzorcowy.
- [ ] `drop_unlabeled=True` usuwa rekordy z `n_superclasses == 0`.
- [ ] Te same `(seed, epoch)` → identyczne batche przy `num_workers=0` i `num_workers=2` (z transformem losowym w teście).
- [ ] `split="test"` bez odblokowania → `LockedSplitError` z instrukcją (T801).
- [ ] `PTBXLDataset` i źródła są picklowalne (test `pickle.dumps`).
- [ ] `build_dataloaders` działa na `mini_ptbxl_root` z `e00_smoke.yaml`.

## Testy

- `test_wfdb_io.py`: kształty 100/500 Hz, jednostki, permutacja kanałów, zły `fs`, NaN → `RecordFormatError`.
- `test_dataset.py`: filtrowanie splitów, `drop_unlabeled`, klucze próbki, pickle, `FieldProvider`.
- `test_samplers.py`: deterministyczna permutacja per epoka; klucze `(epoch, idx)`.
- `test_test_lock.py`: brak zmiennej, brak pliku, oba obecne (w `tmp_path`).

## Weryfikacja

```bash
uv run pytest tests/unit/data -q
```

## Wskazówki i pułapki

- RNG próbki: `np.random.default_rng([seed, epoch, ecg_id])` — nie używaj `torch.initial_seed()` w workerze.
- Na Windows DataLoader z `num_workers > 0` wymaga picklowalnych obiektów — żadnych lambd w `pipeline` i `extra_fields`.
- `collate` domyślny PyTorch obsłuży słownik z tensorami i intami; nie dokładaj własnego bez potrzeby.
