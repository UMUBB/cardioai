---
id: T603
title: Predictor — pipeline inferencji z bundla
epic: product
owner: C
reviewer: B
week: 9
size: M
level: Core
gate: G5
experiment: none
depends_on: [T601, T602]
status: todo
---

# T603 — Predictor: pipeline inferencji z bundla

## Kontekst

- `docs/inference_api.md` §1, §3 (`PredictorProtocol`, `PredictionResult`), §7 (pola odpowiedzi)
- `docs/architecture.md` §6 (kroki inferencji), §7 (statusy)
- `AGENTS.md` §2 pkt 7 (jedna implementacja preprocessingu)

## Cel

`Predictor.from_bundle(...)` daje wynik identyczny z ewaluacją offline tego samego modelu — to dowód, że API używa zamrożonego preprocessingu (bramka G5).

## Zakres

- Ładowanie bundla: `BundleSpec`, budowa modelu z rejestru, wagi (`weights_only=True`), pipeline `build_pipeline(train=False)` ze statystykami z bundla.
- `validate` (deleguje do `validate_ecg` z `fs` modelu) i `predict`: preprocessing → forward → sigmoid → progi → `PredictionResult` z czasami (`timing_ms`).
- Kroki niezawodności (gate, kalibracja, abstention, XAI) jako komponenty opcjonalne — tu w postaci wyłączonej/identycznościowej; pełna integracja w T610.
- `ModelInfo` (`predictor_mode: "real"`).

## Poza zakresem

- HTTP (T605), integracja komponentów niezawodności (T610), backend ONNX (T703).

## Pliki

- `src/cardioai/inference/predictor.py` — nowy
- `tests/unit/inference/test_predictor.py` — nowy
- `tests/integration/test_predictor_parity.py` — nowy

## Interfejs (wiążący)

```python
class Predictor:                                     # implementuje PredictorProtocol
    @classmethod
    def from_bundle(cls, bundle_dir: Path, *, device: str = "cpu") -> "Predictor": ...
    @property
    def info(self) -> ModelInfo: ...
    def validate(self, raw: RawECG) -> ValidatedECG: ...
    def predict(self, ecg: ValidatedECG, *, metadata: Mapping[str, float] | None = None,
                explain: Literal["auto", "always", "never"] = "auto",
                explain_class: str | None = None) -> PredictionResult: ...
```

## Kryteria akceptacji

- [ ] Parzystość: dla 5 rekordów fixture'a prawdopodobieństwa z `Predictor` = prawdopodobieństwa z `scripts/evaluate.py` dla tego samego checkpointu (tolerancja 1e-5).
- [ ] `PredictionResult` kompletny dla statusu `OK` (pola z §3); `signal` zawiera sygnał po walidacji w mV.
- [ ] Bundle z metadanymi: `predict` bez metadanych działa (maski 0); bundle bez metadanych + metadane → ostrzeżenie `METADATA_IGNORED`.
- [ ] Moduł nie importuje `training`, `tracking`, `mlflow` (`lint-imports`).
- [ ] Inicjalizacja z bundla < 3 s na CPU; predykcja bez XAI < 100 ms dla 100 Hz (pomiar w PR).

## Testy

- `test_predictor.py`: ładowanie bundla z losowymi wagami (tworzony w teście), kształt wyniku, ostrzeżenia, `explain="never"`.
- `test_predictor_parity.py`: zgodność z `evaluate.py` na fixture.

## Weryfikacja

```bash
uv run pytest tests/unit/inference/test_predictor.py tests/integration/test_predictor_parity.py -q
uv run lint-imports
```

## Wskazówki i pułapki

- Model ustaw w `eval()` i licz w `torch.inference_mode()` (poza XAI, które potrzebuje gradientów).
- Kolejność klas i odprowadzeń bierz z `BundleSpec` i sprawdzaj zgodność z `cardioai.constants` przy ładowaniu.
