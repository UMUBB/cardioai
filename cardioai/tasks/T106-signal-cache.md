---
id: T106
title: Cache sygnałów NPY z dostępem memmap
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

# T106 — Cache sygnałów NPY z dostępem memmap

## Kontekst

- `docs/data_contract.md` §10 (format cache, zasady memmap)
- `docs/environment.md` §1 (16 GB RAM), §6 (Windows: spawn)

## Cel

Szybki odczyt sygnałów bez parsowania tysięcy plików WFDB w każdej epoce i bez ładowania całego zbioru do RAM
(500 Hz to ok. 5,2 GB).

## Zakres

- `build_cache`: zapis `signals.npy` przez `np.lib.format.open_memmap` (bez trzymania całości w pamięci), `ecg_ids.npy`, `meta.json`.
- `CacheSource` (implementuje `SignalSource`): memmap otwierany leniwie przy pierwszym `get` w danym procesie; mapowanie `ecg_id → wiersz`.
- Kontrola zgodności z indeksem (`index_sha256`) → `CacheMismatchError` z poleceniem przebudowy.
- `build_dataloaders` wybiera `CacheSource`, gdy `data.cache_dir` jest ustawione i cache istnieje; w przeciwnym razie `WFDBSource` z ostrzeżeniem.
- `scripts/build_cache.py --sampling-rate {100,500}`.

## Poza zakresem

- Cache po preprocessingu lub normalizacji — cache przechowuje wyłącznie surowe mV.

## Pliki

- `src/cardioai/data/cache.py` — nowy
- `src/cardioai/data/datamodule.py` — zmiana (wybór źródła)
- `scripts/build_cache.py` — nowy
- `tests/unit/data/test_cache.py` — nowy

## Interfejs (wiążący)

```python
def default_cache_dir(cache_root: Path, sampling_rate: int) -> Path: ...    # .../ptbxl_v1.0.3_{fs}hz
def build_cache(index: pd.DataFrame, root: Path, sampling_rate: int, out_dir: Path) -> Path: ...
class CacheSource:
    def __init__(self, cache_dir: Path, *, expected_index_sha256: str | None = None) -> None: ...
    def get(self, ecg_id: int, rel_path: str | None = None) -> np.ndarray: ...   # kopia [12, T] float32
class CacheMismatchError(RuntimeError): ...
```

## Kryteria akceptacji

- [ ] Na fixture: `CacheSource.get` i `WFDBSource.get` zwracają identyczne tablice (`np.array_equal`) dla wszystkich rekordów.
- [ ] `pickle.dumps(CacheSource(...))` ma < 10 KB (memmap nie jest serializowany).
- [ ] Niezgodny `index_sha256` → `CacheMismatchError`.
- [ ] Budowa cache 100 Hz na prawdziwych danych zakończona; czas i rozmiar zapisane w PR.
- [ ] Trening na cache z `num_workers=2` działa na Windows (potwierdzenie z laptopa RTX).

## Testy

- `test_cache.py`: zgodność z WFDB, meta, pickle, niezgodny hash, brak katalogu → czytelny błąd.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_cache.py -q
uv run python scripts/build_cache.py --sampling-rate 100
```

## Wskazówki i pułapki

- `np.load(path, mmap_mode="r")` w `__init__` + pickle → kopia całej tablicy do workera. Otwieraj w `get`, gdy atrybut jest `None`, i usuń go w `__getstate__`.
- `get` zwraca kopię (`np.array(view, dtype=np.float32)`), bo transformy modyfikują tablice.
