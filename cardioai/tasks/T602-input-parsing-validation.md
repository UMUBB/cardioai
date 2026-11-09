---
id: T602
title: Parsowanie i walidacja wejścia (WFDB, NPZ, CSV)
epic: product
owner: A
reviewer: C
week: 8
size: M
level: Core
gate: G5
experiment: none
depends_on: [T105, T108, T604]
status: todo
---

# T602 — Parsowanie i walidacja wejścia (WFDB, NPZ, CSV)

## Kontekst

- `docs/inference_api.md` §3 (`RawECG`, `ValidatedECG`, `InputValidationError`), §4 (formaty), §5 (kody błędów i ostrzeżeń), §11 (limity)
- `docs/data_contract.md` §7 (kolejność odprowadzeń), §15 (percentyle amplitud z EDA)

## Cel

Dowolny dopuszczalny plik od użytkownika zamienia się w sygnał zgodny z kontraktem modelu — albo w jednoznaczny błąd z kodem, który UI potrafi wyjaśnić.

## Zakres

- `parse_upload` dla WFDB (para `.hea` + `.dat` zapisana w katalogu tymczasowym), NPZ i CSV (separator `,` lub `;`).
- `validate_ecg`: liczba i nazwy odprowadzeń (bez rozróżniania wielkości liter, duplikaty), `fs` w [100, 1000] z resamplingiem do `fs` modelu,
  długość (≥ 10 s, dłuższy → pierwsze 10 s), NaN/Inf, jednostki (`UNITS_SUSPECT`), amplitudy (`AMPLITUDE_HIGH`), kolejność `LEADS`.
- Walidacja metadanych (zakresy z §5).
- Wszystkie kody z §5 jako stałe; komunikaty po polsku.
- Progi amplitud z percentyli EDA (T110) — zmiana względem dokumentacji wymaga wpisu w `docs/decisions.md`.

## Poza zakresem

- Reguły twarde jakości (płaskie odprowadzenia, saturacja — T304), HTTP (T605).

## Pliki

- `src/cardioai/inference/input_io.py`, `src/cardioai/inference/validation.py` — nowe
- `tests/unit/inference/test_input_io.py`, `test_validation.py` — nowe
- `tests/fixtures/inputs/` — małe pliki wejściowe generowane w testach (bez binariów w gicie)

## Interfejs (wiążący)

```python
@dataclass
class UploadedFile:
    filename: str
    content: bytes

def parse_upload(files: Sequence[UploadedFile], *, fs_hint: int | None = None) -> RawECG: ...
def validate_ecg(raw: RawECG, *, target_fs: int, n_seconds: int = 10) -> ValidatedECG: ...
def validate_metadata(meta: Mapping[str, Any]) -> dict[str, float]: ...
ERROR_CODES: Final[Mapping[str, int]]      # kod -> status HTTP (docs/inference_api.md §5)
WARNING_CODES: Final[frozenset[str]]
```

## Kryteria akceptacji

- [ ] Każdy kod błędu z §5 ma test wywołujący go i sprawdzający status HTTP z `ERROR_CODES`.
- [ ] WFDB z kanałami w innej kolejności → sygnał w kolejności `LEADS`; `AVR` rozpoznane jako `aVR`.
- [ ] Wejście 500 Hz dla modelu 100 Hz → `[12, 1000]` + ostrzeżenie `RESAMPLED`; 12 s → pierwsze 10 s + `SIGNAL_TRUNCATED`.
- [ ] Rekord z PTB-XL (fixture) przechodzi walidację bez ostrzeżeń.
- [ ] Pliki tymczasowe WFDB są usuwane po parsowaniu (test).
- [ ] Moduł nie importuje `training` ani `tracking`.

## Testy

- `test_input_io.py`: trzy formaty, błędne kombinacje plików, uszkodzone pliki.
- `test_validation.py`: wszystkie kody błędów i ostrzeżeń, resampling, przycinanie, metadane.

## Weryfikacja

```bash
uv run pytest tests/unit/inference/test_input_io.py tests/unit/inference/test_validation.py -q
uv run lint-imports
```

## Wskazówki i pułapki

- `wfdb.rdsamp` wymaga ścieżki bez rozszerzenia i obu plików w jednym katalogu — zapisz je w `TemporaryDirectory` pod wspólną nazwą bazową z `.hea`.
- CSV z Excela w polskim locale ma przecinek dziesiętny — zwróć `CORRUPTED_FILE` z podpowiedzią zamiast zgadywać.
