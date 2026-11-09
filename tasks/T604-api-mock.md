---
id: T604
title: FastAPI v1 z MockPredictorem i typami inferencji (kontrakt-first)
epic: product
owner: C
reviewer: A
week: 3
size: M
level: Core
gate: G5
experiment: none
depends_on: [T001, T102]
status: todo
---

# T604 — FastAPI v1 z MockPredictorem i typami inferencji

## Kontekst

- `docs/inference_api.md` §3 (typy), §6 (endpointy), §7 (odpowiedź), §8 (błędy), §9 (mock i demo), §10 (OpenAPI), §11 (prywatność, limity)
- `docs/decisions.md`: D-018, D-021, D-022, D-026, D-028, D-035 (status `REJECTED`)
- Specyfikacja §13.1 (ryzyko „integracja za późno” — API mock od tygodnia 3)

## Cel

Kontrakt API istnieje i działa od tygodnia 3, zanim powstanie prawdziwy model — frontend i backend rozwijają się równolegle na tym samym schemacie.

## Zakres

- `cardioai.inference.types`: wszystkie typy z `docs/inference_api.md` §3 (`Issue`, `RawECG`, `ValidatedECG`, `InputValidationError`,
  `QualityResult`, `UncertaintyResult`, `ExplanationResult`, `SignalPayload`, `PredictionResult`, `ModelInfo`, `PredictorProtocol`).
- `MockPredictor`: deterministyczne wyniki zależne od skrótu sygnału, wszystkie trzy statusy osiągalne (np. przez parametr demo), pełny kształt odpowiedzi.
- Aplikacja FastAPI: `create_app(settings)`, `lifespan` ładujący predyktor (mock, gdy `CARDIOAI_PREDICTOR=mock` albo `auto` i brak bundla; `real` bez bundla → `MODEL_NOT_LOADED`; D-026),
  endpointy z §6, modele Pydantic odpowiedzi z §7, koperta błędów z §8 (także dla błędów walidacji żądania), `request_id`, limity rozmiaru, CORS dla dev.
- Demo: `api/demo/` z 5 syntetycznymi rekordami z generatora mini-PTB-XL (T102) — zastąpione prawdziwymi w T605.
- `scripts/export_openapi.py` → `api/openapi.json` (commitowany); test sprawdzający aktualność pliku.

## Poza zakresem

- Parsowanie plików użytkownika (T602) — w trybie mock upload zwraca wynik dla syntetycznego sygnału z ostrzeżeniem; prawdziwy `Predictor` (T603, T605).

## Pliki

- `src/cardioai/inference/types.py`, `src/cardioai/inference/mock.py` — nowe
- `api/cardioai_api/main.py`, `settings.py`, `schemas.py`, `errors.py`, `routes/health.py`, `routes/analyze.py`, `routes/demo.py` — nowe
- `api/demo/demo_records.npz`, `api/demo/demo_records.json` — nowe (syntetyczne, małe)
- `api/openapi.json`, `scripts/export_openapi.py` — nowe
- `tests/api/test_endpoints.py`, `tests/api/test_openapi_up_to_date.py` — nowe

## Interfejs (wiążący)

```python
def create_app(settings: Settings | None = None) -> FastAPI: ...
app = create_app()                       # na poziomie modułu main.py — `uvicorn cardioai_api.main:app`
class Settings(BaseSettings):            # zmienne z docs/environment.md §4 (prefiks CARDIOAI_)
    predictor: Literal["auto", "real", "mock"] = "auto"
    bundle_path: Path = Path("models/bundles/current")
    max_upload_mb: int = 10
    timeout_s: int = 30
    demo_dir: Path = Path("api/demo")
    cors_origins: list[str] = ["http://localhost:5173"]
class MockPredictor:                      # PredictorProtocol
    def __init__(self, *, seed: int = 0) -> None: ...
```

## Kryteria akceptacji

- [ ] Wszystkie endpointy z §6 odpowiadają zgodnie ze schematami; `/v1/health` zwraca `predictor_mode: "mock"`.
- [ ] Odpowiedzi `/v1/analyze` i `/v1/demo/records/{id}/analyze` przechodzą walidację modeli Pydantic dla statusów `OK`, `ABSTAIN`, `REJECTED`.
- [ ] Każdy błąd (także 422 z FastAPI) ma kopertę z §8 i `request_id`.
- [ ] Upload > `max_upload_mb` → 413 `FILE_TOO_LARGE`.
- [ ] `api/openapi.json` aktualny (test porównuje z wygenerowanym schematem).
- [ ] `lint-imports`: `cardioai_api` importuje tylko `cardioai.inference` i `cardioai.constants`.

## Testy

- `test_endpoints.py` (TestClient): każdy endpoint, trzy statusy, błędy, limity, nieznany `ecg_id` → 404.
- `test_openapi_up_to_date.py`: zgodność pliku z `app.openapi()`.

## Weryfikacja

```bash
uv run pytest tests/api -q
CARDIOAI_PREDICTOR=mock uv run uvicorn cardioai_api.main:app --reload
uv run python scripts/export_openapi.py
```

## Wskazówki i pułapki

- `UploadFile` czytaj z limitem (strumieniowo), zanim zapiszesz cokolwiek na dysk.
- `cors_origins: list[str]` jest czytane z `CARDIOAI_CORS_ORIGINS` jako JSON (`["http://localhost:5173"]`), nie jako lista rozdzielona przecinkami (`docs/environment.md` §4).
- Rekordy demo w `.npz` trzymaj jako `int16` w µV (`np.savez_compressed`), ≤ 50 rekordów (D-028) — hook `check-added-large-files` blokuje pliki > 1 MB; przy odczycie konwertuj do `float32` w mV.
