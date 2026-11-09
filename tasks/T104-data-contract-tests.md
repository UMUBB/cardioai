---
id: T104
title: Testy kontraktu danych i ochrona przed przeciekiem
epic: data
owner: A
reviewer: C
week: 2
size: S
level: MVP
gate: G1
experiment: E00
depends_on: [T103]
status: todo
---

# T104 — Testy kontraktu danych i ochrona przed przeciekiem

## Kontekst

- `docs/data_contract.md` §5 (niezmienniki), §6 (schemat)
- `AGENTS.md` §2 pkt 1–3
- Specyfikacja §13.1 (rejestr ryzyk: przeciek między pacjentami)

## Cel

Automatyczny dowód, że split jest rozłączny pacjentowo i zgodny z foldami — uruchamiany przy budowie indeksu, w CI (fixture) i lokalnie na prawdziwych danych.

## Zakres

- `check_index_invariants` zwracająca listę naruszeń dla niezmienników 1–4 z §5 oraz: kolejność kolumn etykiet, wartości kategorii `split`, brak duplikatów kolumn.
- `assert_index_invariants` (wyjątek z listą naruszeń) wywoływana w `build_index` przed zapisem.
- Sprawdzenie istnienia plików WFDB dla wszystkich wierszy (tylko test `requires_data`).

## Poza zakresem

- Niezmiennik 5 (źródło statystyk) — sprawdzają T107 i T801.

## Pliki

- `src/cardioai/data/contract.py` — nowy
- `src/cardioai/data/index.py` — zmiana (wywołanie `assert_index_invariants`)
- `tests/unit/data/test_contract.py` — nowy
- `tests/data/test_contract_real.py` — nowy (`requires_data`)

## Interfejs (wiążący)

```python
def check_index_invariants(df: pd.DataFrame) -> list[str]: ...    # pusta lista = OK
def assert_index_invariants(df: pd.DataFrame) -> None: ...        # DataContractError
class DataContractError(ValueError): ...
```

## Kryteria akceptacji

- [ ] Dla każdego niezmiennika istnieje test negatywny: celowo zepsuta ramka → konkretny komunikat (np. pacjent w train i val).
- [ ] Indeks z fixture'a i z prawdziwych danych przechodzi bez naruszeń.
- [ ] `build_index` nie zapisze indeksu łamiącego kontrakt.
- [ ] Test `requires_data` sprawdza, że każdy `filename_lr` i `filename_hr` ma pliki `.hea` i `.dat`.

## Testy

- `test_contract.py`: ramka poprawna; duplikat `ecg_id`; fold 11; pacjent w dwóch splitach; `split` niezgodny z foldem;
  etykieta 2; `n_superclasses` niezgodne z sumą; zła kolejność kolumn etykiet.
- `test_contract_real.py`: niezmienniki + istnienie plików na prawdziwych danych.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_contract.py -q
uv run pytest -m requires_data tests/data/test_contract_real.py
```

## Wskazówki i pułapki

- Komunikaty błędów mają wskazywać przykładowe identyfikatory (max 10), żeby diagnoza była szybka.
