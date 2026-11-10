# Środowisko i sprzęt

Właściciel: C. Dotyczy wszystkich osób i agentów uruchamiających kod lokalnie.

## 1. Sprzęt zespołu i podział pracy

Nie trenujemy rozproszenie między maszynami — każda prowadzi własne eksperymenty i loguje do wspólnego MLflow.

| Maszyna | OS | Backend | Preferowane zadania | Uwagi |
|---|---|---|---|---|
| MacBook M4 Pro, 24 GB pamięci zunifikowanej | macOS | MPS | Transformer, większe batche przy 100 Hz, EDA, API/UI | trening natywnie (Docker na macOS nie ma MPS) |
| Laptop A: RTX 2060 (6 GB VRAM), i5, 16 GB RAM | Windows | CUDA | ResNet1D, CNN, **finalne benchmarki** (urządzenie kanoniczne) | AMP fp16; `grad_accum_steps` przy dużych modelach |
| Laptop B: RTX 2060 (6 GB VRAM), i5, 16 GB RAM | Windows | CUDA | model jakości, robustness, XAI, ONNX | równoległe eksperymenty, bez decyzji na teście |
| CPU (wszystkie) | wszystkie | CPU | preprocessing, indeksy, baseline klasyczny, testy, inferencja CPU | memmap zamiast ładowania do RAM |

## 2. Instalacja (wszystkie systemy)

Wspierane cele instalacji z T001 i specyfikacji §10, dla **64-bitowego Pythona 3.11 lub 3.12**:

| System / architektura | Wariant PyTorch | Wymagania |
|---|---|---|
| macOS ARM64 (Apple Silicon) | `cpu` — CPU i MPS z PyPI | macOS ≥ 14 dla całego `all`; M4 Pro wymaga macOS obsługującego ten model |
| Windows x86_64 (AMD64) | `cpu` albo `cuda` | 64-bitowy Python; dla CUDA sterownik NVIDIA z §3 |
| Linux x86_64 | `cpu` albo `cuda` | dystrybucja z glibc ≥ 2.28 i OpenMP; dla CUDA zgodny sterownik |
| Linux ARM64 (aarch64) | `cpu` | dystrybucja z glibc ≥ 2.28 i OpenMP |

`required-environments` w `pyproject.toml` pilnuje dostępności wheels podczas rozwiązywania zależności.
Test `tests/integration/test_installation.py` sprawdza także konkretny lockfile dla docelowych platform.
Pełny test wykonania Windows/CUDA wymaga komputera z Windows i GPU NVIDIA; kontener Linux na Macu
pozwala sprawdzić Linux, lecz nie sterownik Windows ani CUDA. Wyniki są w `reports/final/T001-validation.md`.

1. Zainstaluj `uv`:
   - Windows (PowerShell): `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"` albo `winget install --id=astral-sh.uv -e`
   - macOS / Linux: `curl -LsSf https://astral.sh/uv/install.sh | sh` albo `brew install uv`
2. Python zarządzany przez uv: `uv python install 3.12`.
3. Dla extra `lgbm` lub `all` zainstaluj systemowy runtime OpenMP:
   - macOS (Homebrew): `brew install libomp`.
   - Debian/Ubuntu: `sudo apt-get update` i `sudo apt-get install libgomp1`.
   - Inne dystrybucje Linux: odpowiedni pakiet runtime OpenMP z menedżera pakietów.
   - Windows: aktualny [Microsoft Visual C++ Redistributable x64](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).
   To zależność natywnego LightGBM, której `uv` nie instaluje jako pakietu systemowego
   ([instrukcja LightGBM](https://lightgbm.readthedocs.io/en/stable/Installation-Guide.html)).
4. Zależności (w katalogu repo):
   - Mac, CPU, CI: `uv sync --extra cpu --extra all`
   - laptopy RTX: `uv sync --extra cuda --extra all`
   Extras `cpu` i `cuda` wykluczają się (konfiguracja indeksów PyTorch w `pyproject.toml`, T001).
   Extra `all` = `api` + `xai` + `onnx` + `lgbm` + `tracking` (MLflow); obraz API instaluje się bez `tracking` (`docs/decisions.md` D-033).
5. Sprawdzenie T001: `uv run pytest -q` — testuje pakiety, stałe i logowanie, sprawdza wheels oraz
   ładowanie zainstalowanych bibliotek, w tym OpenMP dla LightGBM. Pełne środowisko `cpu`/`cuda` + `all`
   powinno przejść bez pominiętych testów zależności. `scripts/env_check.py` powstaje w T003.
6. Hooki: `uv run pre-commit install`.
7. Frontend (tylko C i do demo, T606): Node.js LTS, `cd web && npm ci`.
8. Docker Desktop (Windows: backend WSL2) — do `docker compose up` (T701).

Drugą wspieraną wersję Pythona wybierzesz przez
`uv sync --python 3.11 --extra cpu --extra all` (na Windows z GPU: `--extra cuda` zamiast `--extra cpu`).
Polecenie zmienia interpreter środowiska projektu; lokalizację oddzielnego środowiska można wskazać
zmienną `UV_PROJECT_ENVIRONMENT` przed uruchomieniem `uv sync` i `uv run`.
Do wiernego odtworzenia istniejącego lockfile dodaj `--locked`.

## 3. Specyfika urządzeń

**CUDA (RTX 2060, Turing, sm_75):**
- AMP fp16 + `GradScaler` (`training.amp: true`); bf16 nie jest natywnie wspierane.
- Startowo ResNet1D przy 100 Hz: `batch_size: 128` z AMP; przy OOM zmniejsz batch i zwiększ `grad_accum_steps`.
- Długie treningi: zasilacz podłączony, tryb wysokiej wydajności, wyłączone usypianie systemu.
- `nvidia-smi` musi pokazywać sterownik zgodny z wybranym wariantem CUDA wheels (T001).
- W T001 wybrano indeks **CUDA 12.6 (`cu126`)**. Przyjmujemy sterownik Windows **≥ 560.76**
  (Linux **≥ 560.28.03**), zgodnie z tabelą CUDA 12.6 GA w
  [dokumentacji NVIDIA](https://docs.nvidia.com/cuda/archive/12.6.0/cuda-toolkit-release-notes/index.html#cuda-driver).
  To wymaganie projektu oparte na wersji sterownika dla pełnego toolkitu; tabela zgodności minor CUDA 12.x
  podaje niższe minimum, z dodatkowymi ograniczeniami. Lokalny CUDA Toolkit nie jest potrzebny do instalacji wheels.
- Indeks zawiera wheels `cp311-win_amd64` i `cp312-win_amd64` (D-005). Potwierdzenie działania na RTX 2060
  wymaga uruchomienia na laptopie: `nvidia-smi` oraz
  `uv run python -c "import torch; print(torch.__version__, torch.version.cuda, torch.cuda.is_available())"`.
  Wynik z laptopa dołączamy do PR; sprawdzenie dostępności wheels nie zastępuje testu GPU.

**MPS (M4 Pro):**
- Tylko float32; AMP wyłączone.
- `PYTORCH_ENABLE_MPS_FALLBACK=1` — brakujące operacje wykonają się na CPU (wolniej, ale poprawnie).
- Wyniki nie są bitowo identyczne z CUDA — wyniki finalne liczymy na laptopie A (`docs/decisions.md` D-019).

**CPU:**
- Testy jednostkowe i CI. `torch.set_num_threads` zostawiamy domyślne, chyba że benchmark (T704) mówi inaczej.

## 4. Zmienne środowiskowe

Plik `.env` w katalogu repo (poza gitem; wzór w `.env.example`). Skrypty wczytują go przez `cardioai.utils.env.load_env()`.

| Zmienna | Domyślnie | Opis |
|---|---|---|
| `CARDIOAI_DATA_ROOT` | `data/raw/ptb-xl-1.0.3` | katalog z PTB-XL 1.0.3; loader configu mapuje go na `data.root` (nadpisuje YAML, ale `--set` ma pierwszeństwo — `docs/config.md` §1 pkt 4) |
| `CARDIOAI_DEVICE` | `auto` | `auto` / `cpu` / `cuda` / `mps`; loader configu mapuje go na `training.device` (nadpisuje YAML, ale `--set` ma pierwszeństwo — `docs/config.md` §1 pkt 4) |
| `CARDIOAI_LOG_LEVEL` | `INFO` | poziom logowania |
| `MLFLOW_TRACKING_URI` | brak → lokalny store | adres serwera MLflow (`docs/mlops.md` §1) |
| `MLFLOW_TRACKING_USERNAME`, `MLFLOW_TRACKING_PASSWORD` | brak | gdy serwer wymaga logowania |
| `PYTORCH_ENABLE_MPS_FALLBACK` | — | `1` na Macu |
| `CUBLAS_WORKSPACE_CONFIG` | — | `:4096:8` przy `training.deterministic: true` na CUDA |
| `CARDIOAI_ALLOW_TEST` | — | `1` **wyłącznie** w procedurze finalnej T801 |
| `CARDIOAI_PREDICTOR` | `auto` | `auto` (brak bundla → mock z ostrzeżeniem) / `real` (brak bundla → 503 `MODEL_NOT_LOADED`) / `mock` (zawsze mock); `docs/inference_api.md` §9 |
| `CARDIOAI_BUNDLE_PATH` | `models/bundles/current` | katalog bundla dla API |
| `CARDIOAI_MAX_UPLOAD_MB` | `10` | limit rozmiaru wejścia API |
| `CARDIOAI_TIMEOUT_S` | `30` | limit czasu analizy |
| `CARDIOAI_DEMO_DIR` | `api/demo` | rekordy demo |
| `CARDIOAI_CORS_ORIGINS` | `["http://localhost:5173"]` | dozwolone pochodzenia w trybie dev; wartość w formacie JSON (lista) |

## 5. Dane na każdej maszynie

- Każda maszyna pobiera i weryfikuje dane sama: `download_ptbxl.py` → `verify_checksums.py` → `build_index.py`
  → `build_cache.py --sampling-rate 100` → `compute_norm_stats.py`.
- Kopiowanie danych między maszynami (dysk, sieć) jest dozwolone — po skopiowaniu zawsze `verify_checksums.py`.
- Miejsce na dysku: ZIP 1,7 GB (można usunąć po rozpakowaniu) + dane 3 GB + cache 100 Hz ok. 1 GB + cache 500 Hz ok. 5,2 GB + `outputs/`.
- Identyczność danych potwierdza `sha256sums_sha256` w `MANIFEST.json` i `index_sha256` w meta indeksu — porównaj `sha256sums_sha256` między maszynami w tygodniu 1,
  a `index_sha256` w tygodniu 2 (indeks powstaje w T103).

## 6. Windows — pułapki

1. **Workery DataLoadera** startują przez `spawn`: skrypty muszą mieć `if __name__ == "__main__":`, transformy i dataset muszą być
   picklowalne (bez lambd), a memmap otwierany leniwie w workerze (`docs/data_contract.md` §10).
2. **Ścieżki:** zawsze `pathlib.Path`; ścieżki z CSV (`records100/00000/00001_lr`) łącz przez `root / Path(filename)`.
3. **Końce linii:** `.gitattributes` z `* text=auto eol=lf` oraz `binary` dla `*.dat`, `*.npy`, `*.pt`, `*.png`, `*.pdf`.
4. **Zmienne środowiskowe w PowerShell:** `$env:CARDIOAI_DEVICE = "cuda"`; w bash: `export CARDIOAI_DEVICE=cuda`. Prościej: `.env`.
5. **Antywirus** spowalnia odczyt tysięcy małych plików WFDB — używaj cache NPY; ewentualnie wyklucz katalog `data/` ze skanowania w czasie rzeczywistym (decyzja właściciela komputera).
6. **WSL2** jest dopuszczalną alternatywą do treningu (parytet z Linuksem w CI); dane trzymaj wtedy w systemie plików WSL, nie w `/mnt/c`.
7. **Długie ścieżki:** w razie błędów `git config --global core.longpaths true`.

Weryfikacja T001 na laptopie RTX 2060 (PowerShell; po instalacji runtime z §2):

```powershell
nvidia-smi
uv sync --locked --python 3.12 --extra cuda --extra all
uv run pytest -q
uv run python -c "import torch; print(torch.__version__, torch.version.cuda, torch.cuda.is_available()); assert torch.cuda.is_available(); assert 'sm_75' in torch.cuda.get_arch_list()"
```

Powtórz dla `--python 3.11`. Dla wariantu CPU wybierz `--extra cpu` i uruchom `uv run pytest -q`.
Zapisz wersję sterownika i wynik poleceń. Kontrola wheels na Macu potwierdza możliwość doboru pakietów,
ale zaliczenie kryterium Windows/CUDA wymaga tego wykonania na Windows.

## 7. Rozwiązywanie problemów

| Objaw | Przyczyna | Rozwiązanie |
|---|---|---|
| `torch.cuda.is_available()` zwraca `False` | zainstalowany wariant CPU lub stary sterownik | `uv sync --extra cuda --extra all`; sprawdź `nvidia-smi` |
| `NotImplementedError` na MPS | brak operacji w MPS | `PYTORCH_ENABLE_MPS_FALLBACK=1` |
| DataLoader „wisi” na Windows | problem z pickle lub `spawn` | diagnoza z `data.num_workers=0`, potem popraw picklowalność |
| `CUDA out of memory` | za duży batch | zmniejsz `batch_size`, zwiększ `grad_accum_steps`, włącz `amp` |
| Różne wyniki między maszynami | inne dane lub urządzenie | porównaj hashe z §5; wyniki finalne tylko z laptopa A |
| Brak połączenia z MLflow | VPN, adres, logowanie | sprawdź `MLFLOW_TRACKING_URI`; tymczasowo loguj lokalnie i zsynchronizuj później |
| `uv sync` zgłasza konflikt extras | wybrano jednocześnie `cpu` i `cuda` | wybierz jeden wariant |
| Import `lightgbm` zgłasza brak `libomp.dylib` lub `libgomp.so.1` | brak systemowego runtime OpenMP | zainstaluj runtime z §2; ponownie uruchom testy zależności |
