---
id: T103
title: Indeks etykiet i splitów (parquet + meta)
epic: data
owner: A
reviewer: B
week: 2
size: M
level: MVP
gate: G1
experiment: E00
depends_on: [T101, T102]
status: todo
---

# T103 — Indeks etykiet i splitów

## Kontekst

- `docs/data_contract.md` §3 (kolumny i obróbka), §4 (etykiety), §5 (split), §6 (schemat indeksu), §11 (flagi jakości), §15 (liczby kontrolne)
- `docs/decisions.md`: D-004, D-016, D-035 (nazwa `build_index.py`)

## Cel

Jeden indeks wszystkich rekordów z etykietami 5 superklas, splitem i metadanymi — budowany raz, czytany przez wszystkie dalsze etapy.

## Zakres

- Parsowanie `scp_codes`, mapowanie kodów diagnostycznych na superklasy (§4), obróbka kolumn (§3), flagi jakości `q_*` (§11).
- Zapis `ptbxl_index_v1.0.3.parquet` i `.meta.json` (§6), z `index_sha256` liczonym z kanonicznej serializacji (nie z bajtów parquet).
- Sprawdzenie `MANIFEST.json` przed budową (flaga `--skip-manifest-check` tylko dla fixture'a).
- `load_index` z walidacją schematu i typów.

## Poza zakresem

- Pełne testy niezmienników (T104) — tu wywołanie podstawowej walidacji schematu.
- Etykiety podklas, rytmu i formy (T403 korzysta z `scp_codes_json`).

## Pliki

- `src/cardioai/data/labels.py`, `src/cardioai/data/index.py` — nowe
- `scripts/build_index.py` — nowy
- `tests/unit/data/test_labels.py`, `tests/unit/data/test_index.py` — nowe
- `tests/data/test_index_real.py` — nowy (`requires_data`)

## Interfejs (wiążący)

```python
def parse_scp_codes(raw: str) -> dict[str, float]: ...                   # ast.literal_eval
def load_scp_statements(root: Path) -> pd.DataFrame: ...
def superclass_mapping(statements: pd.DataFrame) -> dict[str, str]: ...  # kod -> superklasa (diagnostic == 1)
def derive_superclasses(scp: Mapping[str, float], mapping: Mapping[str, str],
                        min_likelihood: float = 0.0) -> list[str]: ...    # w kolejności SUPERCLASSES
def build_index(root: Path, *, min_likelihood: float = 0.0, check_manifest: bool = True) -> pd.DataFrame: ...
def compute_index_sha256(df: pd.DataFrame) -> str: ...
def save_index(df: pd.DataFrame, path: Path) -> Path: ...                 # zapisuje też .meta.json
def load_index(path: Path) -> pd.DataFrame: ...                           # IndexSchemaError przy niezgodności
def default_index_path(cfg: RunConfig) -> Path: ...
class IndexBuildError(RuntimeError): ...
class IndexSchemaError(ValueError): ...
```

CLI: `build_index.py [--data-root PATH] [--out PATH] [--min-likelihood 0.0] [--skip-manifest-check]` — wypisuje tabelę liczebności per split i klasa.

## Kryteria akceptacji

- [ ] Kolumny, typy i kolejność zgodne z `docs/data_contract.md` §6; plik meta z wszystkimi polami.
- [ ] Na prawdziwych danych: 21 799 wierszy, 18 869 pacjentów, liczby klas zgodne z §15 — albo różnica opisana w §15 i w PR (bez zmiany algorytmu na siłę).
- [ ] Wiek ≥ 300 → 90 + `age_90plus = 1`; `patient_id` jako `int32`; `scp_codes_json` jest poprawnym JSON-em.
- [ ] Brak lub niezgodny `MANIFEST.json` → `IndexBuildError` (chyba że `--skip-manifest-check`).
- [ ] `index_sha256` identyczny przy dwóch budowach i na różnych systemach operacyjnych.
- [ ] Na fixture: liczności zgodne z `MINI_EXPECTED`.

## Testy

- `test_labels.py`: parsowanie (w tym `likelihood` 0), mapowanie, kody rytmu ignorowane, rekord bez superklasy, próg `min_likelihood`.
- `test_index.py`: budowa na `mini_ptbxl_root`, schemat, typy, wiek 300, flagi jakości, stabilność `index_sha256`, `load_index` odrzuca uszkodzony plik.
- `test_index_real.py` (`requires_data`): liczby kontrolne z §15.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_labels.py tests/unit/data/test_index.py -q
uv run python scripts/build_index.py
uv run pytest -m requires_data tests/data/test_index_real.py
```

## Wskazówki i pułapki

- `scp_codes` to tekst słownika Pythona — `json.loads` nie zadziała.
- `strat_fold` i `patient_id` rzutuj jawnie; pandas lubi zamieniać int na float przy NaN w innych kolumnach.
- Do `compute_index_sha256` użyj CSV z ustalonym formatem liczb (np. `float_format="%.6g"`) i posortowanymi kolumnami.
