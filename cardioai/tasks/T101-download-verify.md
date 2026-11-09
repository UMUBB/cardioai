---
id: T101
title: Pobieranie PTB-XL 1.0.3, weryfikacja SHA-256 i manifest
epic: data
owner: A
reviewer: C
week: 1
size: M
level: MVP
gate: G1
experiment: none
depends_on: [T001]
status: todo
---

# T101 — Pobieranie PTB-XL 1.0.3, weryfikacja SHA-256 i manifest

## Kontekst

- `docs/data_contract.md` §1 (źródło, licencja), §2 (układ na dysku, `MANIFEST.json`)
- `docs/environment.md` §5 (dane na każdej maszynie)
- `AGENTS.md` §2 pkt 8 (dane poza gitem)

## Cel

Każda osoba odtwarza identyczne dane jedną komendą, a skrypty budujące indeks odmawiają pracy na niezweryfikowanych danych.

## Zakres

- Pobranie ZIP-a wersji 1.0.3 (wznawianie przez nagłówek `Range`, gdy serwer go obsługuje), rozpakowanie i przeniesienie do `data/raw/ptb-xl-1.0.3/`.
- Tryb `--from-zip` (ZIP pobrany ręcznie) i `--force`; idempotencja (ponowne uruchomienie przy poprawnym manifeście nic nie robi).
- Weryfikacja wszystkich plików względem `SHA256SUMS.txt`; tryb `--quick` (CSV + 2% losowych rekordów, seed 0).
- Zapis `MANIFEST.json` według `docs/data_contract.md` §2; kod wyjścia 1 przy brakach lub niezgodnościach.
- Sprawdzenie wolnego miejsca na dysku przed pobraniem (≥ 6 GB).

## Poza zakresem

- Budowa indeksu (T103), cache (T106). Pobieranie z AWS (opcjonalny wariant ręczny opisany w docs).

## Pliki

- `src/cardioai/data/download.py`, `src/cardioai/data/checksums.py` — nowe
- `scripts/download_ptbxl.py`, `scripts/verify_checksums.py` — nowe
- `tests/unit/data/test_checksums.py`, `tests/unit/data/test_download.py` — nowe

## Interfejs (wiążący)

```python
PTBXL_ZIP_URL: str            # stała w download.py; zweryfikuj link „Download the ZIP file” na stronie projektu

def download_file(url: str, dest: Path, *, chunk_size: int = 1 << 20, resume: bool = True,
                  timeout_s: float = 60.0) -> Path: ...
def extract_dataset(zip_path: Path, dest_root: Path) -> Path: ...         # zwraca data/raw/ptb-xl-1.0.3
def parse_sha256sums(path: Path) -> dict[str, str]: ...                   # ścieżka względna -> hash hex
def sha256_file(path: Path, chunk_size: int = 1 << 20) -> str: ...

@dataclass
class VerificationReport:
    n_files: int; n_ok: int; n_missing: int; n_mismatch: int; total_bytes: int
    missing: list[str]; mismatched: list[str]; quick: bool

def verify_dataset(root: Path, *, quick: bool = False, seed: int = 0) -> VerificationReport: ...
def write_manifest(root: Path, report: VerificationReport) -> Path: ...
def read_manifest(root: Path) -> dict[str, Any]: ...                      # ManifestError, gdy brak lub niezgodny
```

CLI: `download_ptbxl.py [--dest data/raw] [--url URL] [--from-zip PATH] [--force]`,
`verify_checksums.py [--root PATH] [--quick]`.

## Kryteria akceptacji

- [ ] Na prawdziwych danych: `verify_checksums.py` (pełny) daje `n_mismatch == 0`, `n_missing == 0` i zapisuje `MANIFEST.json`.
- [ ] `MANIFEST.json` zawiera wszystkie pola z `docs/data_contract.md` §2.
- [ ] Ponowne `download_ptbxl.py` przy kompletnych danych kończy się bez pobierania.
- [ ] Przerwane pobieranie wznawia się (lub zaczyna od nowa z ostrzeżeniem, gdy serwer nie wspiera `Range`).
- [ ] `--from-zip` działa na ZIP-ie pobranym przeglądarką.
- [ ] Testy nie korzystają z internetu.
- [ ] Wartości `sha256sums_sha256` z trzech maszyn porównane i zgodne (komentarz w PR).

## Testy

- `test_checksums.py`: `sha256_file` na znanych bajtach; parsowanie `SHA256SUMS.txt` (spacje, ścieżki z `/`); wykrycie braku i niezgodności; tryb `quick`.
- `test_download.py`: pobieranie z lokalnego `http.server` w wątku albo z mockiem `urlopen`; wznawianie; rozpakowanie ZIP-a z długą nazwą katalogu głównego.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_checksums.py tests/unit/data/test_download.py -q
uv run python scripts/download_ptbxl.py
uv run python scripts/verify_checksums.py
```

## Wskazówki i pułapki

- Katalog główny w ZIP-ie ma długą nazwę (`ptb-xl-a-large-publicly-available-electrocardiography-dataset-1.0.3`) — przenieś zawartość, nie kopiuj dwa razy.
- Ścieżki w `SHA256SUMS.txt` mają `/` — na Windows łącz przez `root / Path(rel)`.
- Pełna weryfikacja ~3 GB trwa od kilkudziesięciu sekund do kilku minut — loguj postęp co 1000 plików.
