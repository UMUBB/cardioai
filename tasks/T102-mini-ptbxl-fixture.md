---
id: T102
title: Syntetyczny mini-PTB-XL jako fixture testów
epic: data
owner: A
reviewer: B
week: 1
size: M
level: MVP
gate: G1
experiment: none
depends_on: [T001]
status: todo
---

# T102 — Syntetyczny mini-PTB-XL jako fixture testów

## Kontekst

- `docs/data_contract.md` §2 (układ plików), §3 (kolumny), §7 (sygnał), §14 (pułapki — fixture ma je odtwarzać)
- `AGENTS.md` §8 (testy bez prawdziwych danych)

## Cel

Mały, deterministyczny zbiór o strukturze identycznej z PTB-XL, generowany w trakcie testów. Dzięki niemu każde zadanie
(i CI) testuje pełny pipeline danych bez pobierania 3 GB i bez commitowania binariów.

## Zakres

- Funkcja generująca w katalogu docelowym: `ptbxl_database.csv` (wszystkie 28 kolumn), `scp_statements.csv`
  (te same kolumny co oryginał, ok. 15 kodów: `NORM`, `IMI`, `ASMI`, `NDT`, `NST_`, `ISC_`, `LAFB`, `IRBBB`, `CLBBB`, `LVH`, `RVH`
  oraz rytm i forma, np. `SR`, `AFIB`, `PVC`, `LVOLT`), pliki WFDB 100 Hz (`records100/00000/xxxxx_lr`) i 500 Hz (`records500/00000/xxxxx_hr`), `SHA256SUMS.txt`.
- Treść: 40 rekordów, ok. 30 pacjentów (część z 2 rekordami w tym samym foldzie), każdy fold 1–10 z ≥ 3 rekordami (fold 9 z ≥ 5 — razem co najmniej 32 z 40),
  wszystkie 5 superklas, ≥ 5 rekordów wieloetykietowych, ≥ 2 rekordy bez superklasy, `likelihood` 0 w części kodów.
  Fold 9 (val) zawiera dla każdej z 5 superklas co najmniej 1 rekord pozytywny i 1 negatywny — inaczej AUROC i metryki jakości na val byłyby `NaN`.
- Pułapki z §14: `patient_id` jako float, `scp_codes` jako tekst słownika Pythona, wiek 300 i NaN, puste `height`/`weight`,
  pola jakości puste i niepuste (różne formaty), nazwy kanałów `AVR/AVL/AVF` wielkimi literami; jeden rekord z permutowaną kolejnością kanałów w nagłówku.
- Sygnał EKG-podobny (suma funkcji Gaussa na uderzenie, 50–100 bpm, różne wzmocnienia per odprowadzenie), mV, `fmt="16"`, 1 µV/LSB.
- Fixture pytest o zasięgu sesji oraz słownik oczekiwanych wartości do asercji.

## Poza zakresem

- Realistyczna morfologia patologii — etykiety są przypisane, sygnał nie musi ich odzwierciedlać.

## Pliki

- `tests/fixtures/make_mini_ptbxl.py` — nowy (funkcja + uruchamianie jako skrypt)
- `tests/conftest.py` — nowy (fixture `mini_ptbxl_root`)
- `tests/unit/data/test_mini_ptbxl.py` — nowy

## Interfejs (wiążący)

```python
def make_mini_ptbxl(root: Path, *, n_records: int = 40, seed: int = 0) -> Path: ...

MINI_EXPECTED: dict[str, Any]    # n_records, n_patients, per_class_counts, n_unlabeled, folds_per_split

@pytest.fixture(scope="session")
def mini_ptbxl_root(tmp_path_factory: pytest.TempPathFactory) -> Path: ...
```

## Kryteria akceptacji

- [ ] Generowanie trwa < 3 s i jest deterministyczne (dwa przebiegi z tym samym seedem → identyczny `SHA256SUMS.txt`).
- [ ] `wfdb.rdsamp` czyta rekordy: `[1000, 12]` przy 100 Hz i `[5000, 12]` przy 500 Hz, `units == "mV"`.
- [ ] Każdy pacjent jest w jednym foldzie; każdy fold ma ≥ 3 rekordy, a fold 9 ≥ 5 rekordów z ≥ 1 pozytywem i ≥ 1 negatywem każdej superklasy.
- [ ] `MINI_EXPECTED` zgadza się z wygenerowanymi plikami (test).
- [ ] Żaden plik binarny nie jest commitowany — wszystko powstaje w `tmp_path_factory`.

## Testy

- `test_mini_ptbxl.py`: odczyt CSV i WFDB, deterministyczność, rozłączność pacjentów między foldami, zgodność z `MINI_EXPECTED`, pozytywy i negatywy każdej superklasy w foldzie 9.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_mini_ptbxl.py -q
uv run python tests/fixtures/make_mini_ptbxl.py --out /tmp/mini_ptbxl
```

## Wskazówki i pułapki

- `wfdb.wrsamp` zapisuje w bieżącym katalogu lub w `write_dir` — ustaw `write_dir` jawnie.
- Wersję 100 Hz generuj przez decymację wersji 500 Hz (`scipy.signal.decimate` lub `resample_poly`), żeby obie były spójne.
- Fixture będzie używana przez większość zadań — zmiany w niej wymagają uruchomienia całego zestawu testów.
