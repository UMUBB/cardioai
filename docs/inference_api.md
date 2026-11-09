# Inferencja i API

Status: **wiążący** (§2, §3, §5–§8). Kod: `src/cardioai/inference/`, `api/cardioai_api/`. Właściciel: C.

## 1. Zasady

1. Serwowanie korzysta wyłącznie z **bundla** — nie z checkpointu, nie z MLflow.
2. Preprocessing w inferencji to ten sam kod co w treningu (`cardioai.data.preprocessing`, `train=False`).
3. API zwraca zawsze wersję modelu, wersję preprocessingu, status i flagę abstention — UI nie interpretuje surowych logitów.
4. Kontrakt JSON jest zdefiniowany tutaj i w modelach Pydantic (`api/cardioai_api/schemas.py`); `api/openapi.json` jest generowany.

## 2. Bundle inferencyjny

```text
models/bundles/resnet1d-1.0.0/      # poza gitem; dystrybucja: wydanie GitHub / rejestr MLflow
├── bundle.json                     # specyfikacja (poniżej)
├── weights.pt                      # state_dict modelu (torch.load(weights_only=True))
├── model.onnx                      # opcjonalnie (T703)
└── README.md                       # generowany: wersja, pochodzenie, metryki val
```

```json
{
  "bundle_format": 1,
  "model_version": "resnet1d-1.0.0",
  "created_at": "2026-12-01T12:00:00Z",
  "model": {"name": "resnet1d", "params": {}, "heads": {"quality": true, "aux": []},
            "metadata": {"enabled": false}, "dropout_head": 0.0,
            "aux_sizes": {}, "n_metadata": 0,
            "weights_file": "weights.pt", "backend": "torch"},
  "classes": ["NORM", "MI", "STTC", "CD", "HYP"],
  "quality_labels": ["static_noise", "burst_noise", "baseline_drift", "electrode_problem"],
  "leads": ["I", "II", "III", "aVR", "aVL", "aVF", "V1", "V2", "V3", "V4", "V5", "V6"],
  "sampling_rate": 100,
  "n_samples": 1000,
  "preprocessing": {"version": "1:none", "normalization": "per_lead_train", "bandpass": null, "notch_hz": null,
                    "norm_stats": {"mean": [], "std": [], "preprocessing_id": "none", "index_sha256": "…"}},
  "metadata_encoder": null,
  "calibration": {"method": "temperature", "per_class": true, "temperature": [], "fitted_on": "val"},
  "thresholds": {"method": "f1", "on_calibrated": true, "fitted_on": "val", "values": {}},
  "quality_gate": {"enabled": true, "t_warn": 0.8, "t_reject": 0.5, "rules": {}, "fitted_on": "val"},
  "abstention": {"enabled": true, "method": "max_entropy", "tau": 0.62, "target_coverage": 0.9, "fitted_on": "val"},
  "explanation": {"method": "integrated_gradients", "n_steps": 50, "baseline": "zeros"},
  "provenance": {"mlflow_run_id": "…", "git_sha": "…", "config_hash": "…", "dataset_version": "1.0.3",
                 "train_folds": [1, 2, 3, 4, 5, 6, 7, 8], "val_fold": 9, "test_evaluated": false,
                 "val_metrics": {"macro_auroc": 0.0}}
}
```

- Sekcje `calibration`, `quality_gate`, `abstention` mogą mieć postać wyłączoną (`{"method": "identity"}`, `{"enabled": false}`),
  dzięki czemu bundle da się zbudować przed ukończeniem warstwy niezawodności (T601).
- Sekcja `model` zawiera `aux_sizes` (`{nazwa: liczba etykiet}` głów pomocniczych, puste bez głów aux) i `n_metadata` (liczba cech metadanych `M`, 0 bez metadanych) —
  argumenty `build_model` (`docs/modeling.md` §2), dzięki którym `Predictor` odtwarza model bez checkpointu. `age_90plus` jest osobną cechą metadanych
  (`docs/data_contract.md` §12), więc po włączeniu metadanych z domyślną listą cech `n_metadata = 5` (D-032, status: proponowana).
- **Wersjonowanie** `{model}-MAJOR.MINOR.PATCH`: MAJOR — zmiana kontraktu wejścia, klas lub semantyki preprocessingu;
  MINOR — nowe wagi; PATCH — tylko kalibracja, progi, gate lub abstention.
- `Predictor` obsługuje `bundle_format == 1`; inna wartość → `BundleFormatError`.
- Bundle nie zawiera obiektów pickle — wszystkie parametry są w JSON.

## 3. Predictor

Typy w `cardioai.inference.types` (tworzone w T604, zanim powstanie prawdziwy model):

```python
@dataclass
class Issue:                    # ostrzeżenie lub błąd walidacji
    code: str
    message: str                # po polsku, do pokazania w UI
    details: dict[str, Any] = field(default_factory=dict)

@dataclass
class RawECG:
    signal: np.ndarray          # [n_leads, T] float32, mV
    fs: int
    leads: list[str]
    source_format: Literal["wfdb", "npz", "csv", "demo"]

@dataclass
class ValidatedECG:
    signal: np.ndarray          # [12, n_samples] float32, mV, kolejność LEADS, fs modelu
    fs: int
    original_fs: int
    warnings: list[Issue]

class InputValidationError(Exception):
    code: str; message: str; details: dict[str, Any]; http_status: int

@dataclass
class PredictionResult:
    status: Literal["OK", "ABSTAIN", "REJECTED"]
    model_version: str
    preprocessing_version: str
    quality: QualityResult                    # status, score, artifacts, reasons
    probabilities: dict[str, float] | None    # None przy REJECTED
    calibrated: bool
    thresholds: dict[str, float]
    positive_labels: list[str]
    abstain: bool
    abstain_reasons: list[str]
    uncertainty: UncertaintyResult | None     # method, score, threshold
    explanation: ExplanationResult | None     # method, target_class, lead_importance, attribution_fs, attribution, note
    signal: SignalPayload                     # fs, units, leads, data [12][T] — sygnał po walidacji (mV)
    warnings: list[Issue]
    timing_ms: dict[str, float]

class PredictorProtocol(Protocol):
    @property
    def info(self) -> ModelInfo: ...          # model_version, sampling_rate, classes, predictor_mode, ...
    def validate(self, raw: RawECG) -> ValidatedECG: ...
    def predict(self, ecg: ValidatedECG, *, metadata: Mapping[str, float] | None = None,
                explain: Literal["auto", "always", "never"] = "auto",
                explain_class: str | None = None) -> PredictionResult: ...
```

`Predictor.from_bundle(path, device="cpu")` ładuje bundle; `MockPredictor` (T604) implementuje ten sam protokół.

## 4. Formaty wejścia

| Format | Pliki | Wymagania |
|---|---|---|
| WFDB | para `*.hea` + `*.dat` o tej samej nazwie bazowej | jednostki mV; nazwy kanałów z nagłówka |
| NPZ | jeden `*.npz` | klucze: `signal` (`[12, T]`), `fs` (int); opcjonalnie `leads` (12 nazw); brak `leads` → kolejność `LEADS` |
| CSV | jeden `*.csv` | nagłówek z nazwami odprowadzeń, wiersz = próbka, separator `,` lub `;`, kropka dziesiętna, mV; `fs` w polu formularza `sampling_rate` |

Nazwy odprowadzeń porównujemy bez rozróżniania wielkości liter (`AVR` = `aVR`).

## 5. Walidacja wejścia — kody

Błędy (żądanie odrzucone, brak predykcji):

| Kod | HTTP | Warunek |
|---|---|---|
| `UNSUPPORTED_FORMAT` | 400 | rozszerzenie lub zestaw plików spoza §4 |
| `MISSING_COMPANION_FILE` | 400 | `.hea` bez `.dat` lub odwrotnie |
| `CORRUPTED_FILE` | 400 | plik nie daje się odczytać |
| `FILE_TOO_LARGE` | 413 | suma plików > `CARDIOAI_MAX_UPLOAD_MB` (domyślnie 10) |
| `INVALID_LEAD_COUNT` | 422 | liczba kanałów ≠ 12 |
| `UNKNOWN_LEAD_NAMES` / `DUPLICATE_LEADS` | 422 | nazwy spoza `LEADS` / powtórzenia |
| `SAMPLING_RATE_REQUIRED` | 422 | CSV bez `sampling_rate` |
| `UNSUPPORTED_SAMPLING_RATE` | 422 | `fs` poza przedziałem [100, 1000] Hz |
| `SIGNAL_TOO_SHORT` | 422 | krócej niż 10 s |
| `NON_FINITE_VALUES` | 422 | NaN lub Inf |
| `UNITS_SUSPECT` | 422 | `max \|x\| > 50` — prawdopodobnie µV zamiast mV |
| `INVALID_METADATA` | 422 | metadane spoza zakresu (wiek 0–120, płeć 0/1, wzrost 30–250 cm, waga 1–300 kg) |
| `UNKNOWN_CLASS` | 422 | `explain_class` spoza `classes` |

Ostrzeżenia (predykcja jest wykonywana, `warnings[]` w odpowiedzi):

| Kod | Warunek |
|---|---|
| `SIGNAL_TRUNCATED` | dłużej niż 10 s — używamy pierwszych 10 s |
| `RESAMPLED` | `fs` ≠ `fs` modelu — `resample_poly` |
| `AMPLITUDE_HIGH` | `max \|x\| > 10 mV` |
| `FLAT_LEAD` / `SATURATION` | reguły twarde quality gate (`docs/reliability.md` §4) |
| `QUALITY_WARN` | quality gate zwrócił `WARN` |
| `METADATA_IGNORED` | podano metadane, a model ich nie używa |
| `EXPLANATION_SKIPPED` | XAI pominięte (status ≠ OK przy `explain=auto`) |

Progi amplitud doprecyzowuje EDA (`docs/data_contract.md` §15); zmiana progów = wpis w `docs/decisions.md`.

## 6. Endpointy API

| Metoda i ścieżka | Opis | Odpowiedź |
|---|---|---|
| `GET /v1/health` | stan usługi | `{"status": "ok", "model_loaded": true, "predictor_mode": "real"}` |
| `GET /v1/version` | wersje | `{"api_version": "1.0.0", "model_version": "…", "preprocessing_version": "…", "git_sha": "…", "bundle_format": 1}` |
| `GET /v1/models` | dostępne modele | `{"default": "…", "models": [ModelInfo]}` |
| `POST /v1/analyze` | analiza wgranego pliku (multipart) | `AnalyzeResponse` (§7) |
| `GET /v1/demo/records` | lista rekordów demo | `{"records": [{"ecg_id", "labels", "fold", "quality_flags", "description"}]}` |
| `GET /v1/demo/records/{ecg_id}` | sygnał rekordu demo | `{"ecg_id", "labels", "signal": SignalPayload}` |
| `POST /v1/demo/records/{ecg_id}/analyze` | analiza rekordu demo | `AnalyzeResponse` + `"ground_truth": {"labels": [...]}` |

Pola formularza `POST /v1/analyze`: `files` (1–2 pliki), `sampling_rate` (CSV), `age`, `sex`, `height`, `weight` (opcjonalne),
`explain` (`auto` | `always` | `never`, domyślnie `auto`), `explain_class` (opcjonalne), `return_signal` (domyślnie `true`).
Endpoint demo przyjmuje `explain` i `explain_class` jako parametry zapytania.

## 7. Odpowiedź `/v1/analyze`

```json
{
  "request_id": "6f0c1a2e-4b1d-4a53-9a0e-2f1d8c7b9e10",
  "api_version": "1.0.0",
  "model_version": "resnet1d-1.0.0",
  "preprocessing_version": "1:none",
  "status": "OK",
  "signal_quality": {
    "status": "ACCEPT",
    "score": 0.94,
    "artifacts": {"static_noise": 0.03, "burst_noise": 0.01, "baseline_drift": 0.06, "electrode_problem": 0.02},
    "reasons": []
  },
  "predictions": {"NORM": 0.03, "MI": 0.86, "STTC": 0.71, "CD": 0.12, "HYP": 0.08},
  "calibrated": true,
  "thresholds": {"NORM": 0.55, "MI": 0.41, "STTC": 0.38, "CD": 0.47, "HYP": 0.29},
  "positive_labels": ["MI", "STTC"],
  "abstain": false,
  "abstain_reasons": [],
  "uncertainty": {"method": "max_entropy", "score": 0.21, "threshold": 0.62},
  "explanation": {
    "method": "integrated_gradients",
    "target_class": "MI",
    "lead_importance": {"I": 0.04, "II": 0.11, "III": 0.09, "aVR": 0.03, "aVL": 0.05, "aVF": 0.10,
                        "V1": 0.12, "V2": 0.15, "V3": 0.11, "V4": 0.08, "V5": 0.07, "V6": 0.05},
    "attribution_fs": 100,
    "attribution": [[0.0]],
    "note": "Mapa atrybucji pokazuje wrażliwość modelu na fragmenty sygnału, a nie przyczynę kliniczną."
  },
  "signal": {"fs": 100, "units": "mV", "leads": ["I", "II", "III", "aVR", "aVL", "aVF", "V1", "V2", "V3", "V4", "V5", "V6"], "data": [[0.0]]},
  "warnings": [],
  "timing_ms": {"total": 85.2, "parse": 4.0, "preprocess": 3.1, "inference": 12.0, "explain": 60.1}
}
```

- Prawdopodobieństwa w przykładzie są ilustracyjne; `attribution` i `signal.data` mają kształt `[12][T]` (skrócone).
- `status = "REJECTED"` → `predictions`, `positive_labels`, `uncertainty` i `explanation` są `null` lub puste.
- `status = "ABSTAIN"` → `predictions` są zwracane do wglądu, `abstain = true`, `abstain_reasons` niepuste.
- Względem przykładu ze specyfikacji API v1 dodaje pola `status`, `explanation`, `signal`, `timing_ms` (`docs/decisions.md` D-021).

## 8. Błędy

Wszystkie błędy (również walidacja żądania przez FastAPI) mają jedną kopertę:

```json
{"error": {"code": "INVALID_LEAD_COUNT", "message": "Oczekiwano 12 odprowadzeń, otrzymano 8.",
           "details": {"n_leads": 8}, "request_id": "…"}}
```

| Kod | HTTP | Kiedy |
|---|---|---|
| kody z §5 | 400 / 413 / 422 | walidacja wejścia |
| `REQUEST_VALIDATION_ERROR` | 422 | błędne pola formularza lub parametry |
| `DEMO_RECORD_NOT_FOUND` | 404 | nieznany `ecg_id` demo |
| `MODEL_NOT_LOADED` | 503 | `CARDIOAI_PREDICTOR=real` i brak bundla (przy `auto` brak bundla oznacza tryb mock — §9) |
| `TIMEOUT` | 504 | przekroczony limit czasu analizy |
| `INTERNAL_ERROR` | 500 | nieoczekiwany wyjątek (szczegóły tylko w logu, z `request_id`) |

## 9. Tryb mock i demo

- `CARDIOAI_PREDICTOR ∈ {auto, real, mock}`, domyślnie `auto` (D-026): `mock` → zawsze `MockPredictor`; `auto` + brak bundla w `CARDIOAI_BUNDLE_PATH`
  → `MockPredictor` z ostrzeżeniem w logu i `predictor_mode: "mock"`; `real` + brak bundla → 503 `MODEL_NOT_LOADED` (§8).
- `MockPredictor`: deterministyczne wyniki zależne
  od skrótu sygnału, pełny kształt odpowiedzi, `predictor_mode: "mock"` w `/v1/health` i w `ModelInfo`. UI pokazuje baner „TRYB DEMONSTRACYJNY (MOCK)”.
- Rekordy demo: `api/demo/demo_records.npz` + `api/demo/demo_records.json` — do 50 rekordów z **foldu 9** wybranych losowo
  z seedem (warstwowo po klasach, nie według trafności modelu), 100 Hz, z atrybucją PTB-XL (CC BY 4.0). Generuje je
  `scripts/make_demo_records.py` (T605); do tego czasu syntetyczne rekordy z generatora mini-PTB-XL (T604).
- Format rekordów w `.npz`: `int16` w µV (`np.savez_compressed`); API konwertuje je do `float32` w mV (dzielenie przez 1000). Jeśli plik przekracza 1 MB,
  zmniejszamy liczbę rekordów (minimum 20); limit hooka pre-commit (`check-added-large-files`) pozostaje bez zmian (D-028).

## 10. OpenAPI i wersjonowanie

- `scripts/export_openapi.py` zapisuje `api/openapi.json`; CI sprawdza, czy plik jest aktualny.
- Frontend generuje typy TypeScript z tego pliku (`docs/frontend.md` §6).
- Wszystkie ścieżki mają prefiks `/v1`. Zmiana łamiąca kontrakt → `/v2` + wpis w `docs/decisions.md`. `api_version` w semver.

## 11. Prywatność i limity

- Pliki z żądania trafiają do `tempfile.TemporaryDirectory` i są usuwane w bloku `finally`; nic nie jest utrwalane.
- Logi zawierają: `request_id`, format wejścia, status, czasy — **bez** sygnału i wartości metadanych.
- Limity: rozmiar wejścia `CARDIOAI_MAX_UPLOAD_MB` (10), maks. 2 pliki, czas analizy `CARDIOAI_TIMEOUT_S` (30 s).
- Inferencja działa w puli wątków (`run_in_threadpool`), żeby nie blokować pętli zdarzeń.
- CORS: w trybie dev tylko `http://localhost:5173`; w compose frontend i API mają wspólne pochodzenie przez reverse proxy.
