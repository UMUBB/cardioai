# MLOps: tracking, rejestr, CI/CD, Docker

Status: **wiążący** (§2, §3). Kod: `src/cardioai/tracking/`, `.github/workflows/`, `docker/`, `compose.yaml`. Właściciel: C.

## 1. MLflow — serwer zespołowy

Trzy maszyny prowadzą eksperymenty równolegle i logują do **jednego** serwera MLflow. Kod nie zna adresu serwera —
czyta go ze zmiennej `MLFLOW_TRACKING_URI`. Bez tej zmiennej logujemy lokalnie (katalog ignorowany przez git) z ostrzeżeniem.

Warianty hostingu (wybór i uzasadnienie w T004, wpis `docs/decisions.md` D-007):

| Wariant | Opis | Plusy | Minusy |
|---|---|---|---|
| A. Serwer na jednej maszynie zespołu | `docker/mlflow.compose.yaml`: backend SQLite, artefakty serwowane przez serwer (`--serve-artifacts`), dostęp przez VPN typu mesh (np. Tailscale) | pełna kontrola, brak kont zewnętrznych | maszyna musi być włączona |
| B. Hostowane MLflow | zewnętrzna usługa z darmowym planem (do sprawdzenia przy wyborze) | dostęp zawsze | limity planu, konto zewnętrzne |

Niezależnie od wariantu: kopia zapasowa bazy i artefaktów raz w tygodniu; uwierzytelnienie przez zmienne
`MLFLOW_TRACKING_USERNAME` / `MLFLOW_TRACKING_PASSWORD` w `.env` (poza gitem).

## 2. Konwencje: eksperymenty, runy, tagi

- **Eksperyment MLflow** = `experiment.name` z configu, np. `e03_resnet1d` — jeden na pozycję Exx (`eNN_<opis>`); wariant wyłącznie w `experiment.variant` i w nazwie runu (D-031).
- **Run** = jedno uruchomienie treningu lub ewaluacji; nazwa według `docs/config.md` §6, np. `resnet1d-100hz-base-s0`.
- Ewaluacja (`evaluate.py`, kalibracja, robustness) loguje do **tego samego runu** co trening (artefakty w podkatalogach),
  a gdy to niemożliwe — do runu potomnego z tagiem `source_run_id`.

Tagi obowiązkowe (ustawia `start_run`, T004):

| Tag | Przykład | Opis |
|---|---|---|
| `exp_id` | `E03` | identyfikator eksperymentu |
| `variant` | `base` | wariant |
| `owner` | `B` | osoba odpowiedzialna |
| `hypotheses` | `H1` | hipotezy (po przecinku) |
| `task_id` | `T207` | zadanie, w którym powstał kod (opcjonalnie) |
| `git_sha`, `git_dirty` | `a1b2c3d`, `false` | stan repo; `git_dirty=true` → run nie trafia do tabel finalnych |
| `dataset_version` | `1.0.3` | wersja PTB-XL |
| `sampling_rate` | `100` | fs |
| `preprocessing_version` | `1:none` | wersja preprocessingu |
| `config_hash` | `a1b2c3d4e5f6` | `docs/config.md` §6 |
| `seed` | `0` | seed |
| `device`, `device_name`, `host` | `cuda`, `RTX 2060`, `laptop-a` | urządzenie |
| `stage` | `dev` / `final` | `final` tylko w T801 |

## 3. Parametry, metryki, artefakty

- **Parametry:** spłaszczony config (`training.optimizer.lr`, `model.params.widths`, …) + `n_params`, `mflops`.
- **Metryki** (klucze stałe — na nich opiera się `summarize_runs.py`). Nazwy metryk składają się wyłącznie ze znaków `[A-Za-z0-9_./-]` (bez `@` i `:`; D-029):

| Grupa | Klucze |
|---|---|
| trening | `train/loss`, `train/loss_diag`, `train/loss_quality`, `train/loss_aux`, `lr`, `epoch_time_s`, `throughput_samples_s`, `peak_memory_mb` |
| walidacja | `val/loss`, `val/macro_auroc`, `val/micro_auroc`, `val/macro_ap`, `val/auroc_<KLASA>`, `val/ap_<KLASA>`, `val/macro_f1_tuned`, `val/f1_<KLASA>_tuned`, `val/sensitivity_<KLASA>`, `val/specificity_<KLASA>`, `val/hamming_loss`, `val/brier_macro`, `val/ece_macro` |
| jakość | `val/quality_auroc_<ETYKIETA>`, `val/quality_auroc_synth_<ETYKIETA>`, `val/gate_reject_rate`, `val/gate_frr_clean` |
| głowy pomocnicze | `val/aux_<nazwa>_macro_auroc` (np. `val/aux_rhythm_macro_auroc`) |
| niezawodność | `val/ece_macro_cal`, `val/brier_macro_cal`, `val/aurc`, `val/selective_risk_cov095`, `val/selective_risk_cov090`, `val/selective_risk_cov080` |
| robustness | `robust/<test>/<wartość>/macro_auroc` (pełna tabela w artefakcie CSV) |
| finał | `test/...` — tylko z tagiem `stage=final` |

- **Artefakty** (ścieżki w runie):

| Ścieżka | Zawartość |
|---|---|
| `config/resolved.yaml` | rozwiązany config |
| `env/env_info.json` | wersje bibliotek, urządzenie, git |
| `checkpoints/best.pt` | najlepszy checkpoint (gdy `tracking.log_checkpoints`) |
| `eval/<split>/` | `predictions_<split>.parquet`, `metrics_<split>.json`, `per_class.md`, wykresy |
| `calibration/`, `thresholds/`, `quality_gate/`, `abstention/` | pliki JSON z `docs/reliability.md` i `docs/evaluation.md` §3 + wykresy |
| `robustness/` | `robustness.csv` + wykresy |
| `bundle/` | eksportowany bundle (tylko runy, z których powstał bundle) |

## 4. Rejestr modeli i promocja

- Model zarejestrowany: `cardioai-diagnosis`. Wersja rejestru = bundle zalogowany jako model pyfunc
  (wrapper ładujący `Predictor` z bundla); sprawdź różnice API między MLflow 2.x a 3.x przy `log_model`.
- Aliasy: `candidate` (kandydat po walidacji) i `champion` (model w demo). Bez użycia przestarzałych „stages”.
- Promocja (`scripts/promote_model.py`, T702): raport walidacyjny (metryki val, kalibracja, robustness, czas) →
  ręczna akceptacja drugiej osoby w PR → ustawienie aliasu `champion` → wydanie (§8).

## 5. Reprodukowalność

Każdy wynik musi dać się przypisać do: git SHA (czyste drzewo), `uv.lock`, `config_hash`, seeda, `MANIFEST.json` danych
i urządzenia. Run z `git_dirty=true` może służyć do eksploracji, ale nie trafia do tabel w raporcie.
Wyniki finalne liczymy na jednej klasie urządzenia (`docs/decisions.md` D-019).

## 6. CI/CD

| Wyzwalacz | Pipeline | Zadanie |
|---|---|---|
| Pull request | ruff → format check → lint-imports → mypy → pytest (bez danych, bez GPU) → test kontraktów danych na fixture → smoke test modelu → aktualność `api/openapi.json` → frontend: lint, typecheck, test, build | T005, T702 |
| Push do `main` | jak wyżej + budowa obrazów Docker (bez publikacji) | T702 |
| Tag `v*` | budowa i publikacja obrazów w GHCR, wydanie GitHub z bundlem i kartą modelu | T702 |
| Promocja modelu | raport walidacyjny → ręczna akceptacja → alias w rejestrze | T702 |

CI instaluje PyTorch w wersji CPU (`uv sync --locked --extra cpu --extra all`, razem z extra `tracking`), nigdy nie pobiera PTB-XL i kończy się w ≤ 10 minut.

## 7. Docker i compose

| Usługa | Obraz | Rola |
|---|---|---|
| `api` | `docker/api.Dockerfile` — Python slim, PyTorch CPU, użytkownik bez uprawnień root | FastAPI na porcie 8000, healthcheck `/v1/health` |
| `web` | `docker/web.Dockerfile` — build Node → Caddy | pliki statyczne + reverse proxy `/api/*` → `api:8000`, port 8080 |
| `mlflow` (profil `tracking`) | oficjalny obraz MLflow | opcjonalny lokalny serwer trackingu |

- Bundle montowany tylko do odczytu: `./models/bundles/current:/bundle:ro`, `CARDIOAI_BUNDLE_PATH=/bundle`. `models/bundles/current` to zwykły katalog (kopia bundla), nie dowiązanie symboliczne (D-034).
- Przy domyślnym `CARDIOAI_PREDICTOR=auto` brak bundla → API startuje w trybie mock (`docs/inference_api.md` §9), więc `docker compose up` działa zawsze
  (`CARDIOAI_PREDICTOR=real` bez bundla daje 503 `MODEL_NOT_LOADED`); prawdziwy model pochodzi z wydania (`scripts/fetch_bundle.py`)
  albo z obrazu z GHCR (`docs/decisions.md` D-022, D-026).
- Obraz API nie zawiera kodu treningowego ani danych; rozmiar raportowany w T701.

## 8. Wydania

- Wersja aplikacji: tag `vMAJOR.MINOR.PATCH` (semver), niezależna od `model_version` bundla.
- Wydanie GitHub zawiera: bundle (`.zip`), `model_card.md`, `CHANGELOG` wydania, skrót metryk val (i test — tylko po T801).
- `scripts/fetch_bundle.py --version <tag>` pobiera bundle do `models/bundles/<model_version>/` i kopiuje go do `models/bundles/current/` (zwykły katalog, nie dowiązanie symboliczne; D-034).
