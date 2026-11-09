---
id: T605
title: Integracja API z prawdziwym Predictorem i rekordami demo
epic: product
owner: C
reviewer: B
week: 12
size: M
level: Core
gate: G5
experiment: none
depends_on: [T603, T604]
status: todo
---

# T605 — Integracja API z prawdziwym Predictorem i rekordami demo

## Kontekst

- `docs/inference_api.md` §5 (kody), §6–§9, §11 (prywatność i limity)
- `docs/decisions.md`: D-017 (demo z foldu 9), D-022, D-026, D-028 (format rekordów demo)
- `docs/data_contract.md` §1 (licencja i przypisanie)

## Cel

API serwuje prawdziwy model z bundla, przyjmuje pliki użytkownika z pełną walidacją i pokazuje rekordy demo z PTB-XL — bez zmiany kontraktu z T604.

## Zakres

- Tryby `auto` i `real`: ładowanie `Predictor.from_bundle(CARDIOAI_BUNDLE_PATH)` w `lifespan`; `auto` + brak bundla → mock z ostrzeżeniem w logu (D-022, D-026);
  `CARDIOAI_PREDICTOR=real` i brak bundla → `MODEL_NOT_LOADED` (503) na `/v1/analyze`.
- `/v1/analyze`: zapis uploadu do `TemporaryDirectory`, `parse_upload` → `validate` → `predict` w `run_in_threadpool` z limitem czasu (`TIMEOUT`), mapowanie wyniku i błędów.
- `scripts/make_demo_records.py`: do 50 rekordów z foldu 9 (seed, warstwowo po klasach, nie według trafności), 100 Hz, zapis jako `int16` w µV (`np.savez_compressed`);
  gdy plik przekracza 1 MB, skrypt zmniejsza liczbę rekordów (minimum 20); `api/demo/` + plik z przypisaniem PTB-XL (CC BY 4.0).
- Logi strukturalne bez sygnału i metadanych (`request_id`, format, status, czasy).

## Poza zakresem

- Komponenty niezawodności w `Predictor` (T610), Docker (T701).

## Pliki

- `api/cardioai_api/main.py`, `routes/analyze.py`, `routes/demo.py` — zmiana
- `scripts/make_demo_records.py` — nowy
- `api/demo/demo_records.npz`, `api/demo/demo_records.json`, `api/demo/ATTRIBUTION.md` — nowe (prawdziwe rekordy demo)
- `tests/api/test_real_mode.py` — nowy

## Kryteria akceptacji

- [ ] Test e2e z bundlem o losowych wagach (tworzony w teście): WFDB, NPZ, CSV → 200 i poprawny schemat; błędne pliki → kody z §5.
- [ ] Pliki tymczasowe usunięte po każdym żądaniu, także przy wyjątku (test).
- [ ] Logi nie zawierają wartości sygnału ani metadanych (test na przechwyconych logach).
- [ ] Rekordy demo wyłącznie z foldu 9; wybór deterministyczny (seed w `demo_records.json`); `ATTRIBUTION.md` z cytowaniem z `docs/data_contract.md` §1.
- [ ] Rozmiar plików demo < 1 MB (przy przekroczeniu mniej rekordów, ale ≥ 20); rekordy w `.npz` jako `int16` w µV, API zwraca je jako `float32` w mV (test round-trip).
- [ ] Kontrakt bez zmian: `api/openapi.json` identyczny z wersją z T604 (albo zmiana opisana w `docs/decisions.md`).

## Testy

- `test_real_mode.py`: tryb real z bundlem testowym, limit czasu (monkeypatch spowolnienia), sprzątanie plików, logi, 503 bez bundla przy `CARDIOAI_PREDICTOR=real`, mock z ostrzeżeniem przy `auto`.

## Weryfikacja

```bash
uv run pytest tests/api -q
uv run python scripts/make_demo_records.py --n 50 --seed 0
CARDIOAI_BUNDLE_PATH=models/bundles/<wersja> uv run uvicorn cardioai_api.main:app
```

## Wskazówki i pułapki

- `make_demo_records.py` czyta dane przez `cardioai.data` — wywołuj go jako skrypt, nie z kodu API.
- Limit czasu przez `anyio.fail_after` wokół wywołania w puli wątków; sam wątek nie zostanie przerwany — loguj przekroczenie.
