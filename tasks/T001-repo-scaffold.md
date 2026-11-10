---
id: T001
title: Szkielet repozytorium, pyproject i narzędzia jakości
epic: foundation
owner: C
reviewer: B
week: 1
size: M
level: MVP
gate: G1
experiment: none
depends_on: []
status: review
---

# T001 — Szkielet repozytorium, pyproject i narzędzia jakości

## Kontekst

- `AGENTS.md` §3 (mapa i granice modułów), §4 (komendy), §5 (konwencje), §8 (testy)
- `docs/architecture.md` §3, §4
- `docs/environment.md` §2 (instalacja), §6 (Windows)
- `docs/decisions.md`: D-005 (uv i warianty PyTorch), D-008 (pakiety), D-024 (importy bezpośrednie), D-033 (extra `tracking`)

## Cel

Instalowalny pakiet `cardioai` ze wspólnymi narzędziami (ruff, pytest, mypy, import-linter, pre-commit), który instaluje się
jedną komendą na Windows z CUDA, macOS z MPS i Linuksie bez GPU. Od tego zadania zależą wszystkie pozostałe.

## Zakres

- `pyproject.toml` (backend `hatchling`), pakiety `src/cardioai` i `api/cardioai_api`, `requires-python = ">=3.11,<3.13"`.
- Zależności bazowe: `numpy`, `pandas`, `pyarrow`, `scipy`, `scikit-learn`, `wfdb`, `pyyaml`, `pydantic>=2`, `matplotlib`, `python-dotenv` (bez `mlflow` — patrz extra `tracking`, D-033).
- Extras: `cpu` i `cuda` (PyTorch ≥ 2.6, wzajemnie wykluczające się), `api` (`fastapi`, `uvicorn[standard]`, `python-multipart`, `pydantic-settings`),
  `xai` (`captum`), `onnx` (`onnx`, `onnxruntime`), `lgbm` (`lightgbm`), `tracking` (`mlflow`), `all` = `api` + `xai` + `onnx` + `lgbm` + `tracking`.
- Grupa `dev` (PEP 735): `pytest`, `pytest-cov`, `ruff`, `mypy`, `import-linter`, `pre-commit`, `types-PyYAML`, `pandas-stubs`.
- Szkielet pakietów z `__init__.py`: `config`, `utils`, `tracking`, `data`, `models`, `training`, `evaluation`, `reliability`, `inference` oraz `api/cardioai_api`.
- `src/cardioai/__init__.py` (`__version__ = "0.1.0"`), `src/cardioai/constants.py` (treść niżej), `src/cardioai/utils/logging.py`.
- Konfiguracja: ruff (`line-length = 100`, reguły `E,F,I,B,UP,SIM,N`), mypy (na start `strict` z wyjątkami dla bibliotek bez typów),
  pytest (markery `requires_data`, `slow`, `gpu`; `testpaths = ["tests"]`), kontrakty `import-linter` odwzorowujące tabelę z `AGENTS.md` §3.
- `.gitignore`, `.gitattributes`, `.editorconfig`, `.env.example`, `.pre-commit-config.yaml`, szkielet `README.md`, katalogi `configs/`, `scripts/`, `tests/unit/`, `tests/data/`.
- Test dymny `tests/unit/test_smoke.py`.

## Poza zakresem

- System configu (T002), device i seed (T003), MLflow (T004), workflow CI (T005), frontend (T606).

## Pliki

- `pyproject.toml`, `uv.lock` — nowe
- `src/cardioai/__init__.py`, `src/cardioai/constants.py`, `src/cardioai/utils/logging.py` — nowe
- `api/cardioai_api/__init__.py` — nowy
- `.gitignore`, `.gitattributes`, `.editorconfig`, `.env.example`, `.pre-commit-config.yaml`, `README.md` — nowe
- `tests/unit/test_smoke.py` — nowy

## Interfejs (wiążący)

```python
# src/cardioai/constants.py
DATASET_NAME: Final = "ptb-xl"
DATASET_VERSION: Final = "1.0.3"
LEADS: Final[tuple[str, ...]] = ("I", "II", "III", "aVR", "aVL", "aVF", "V1", "V2", "V3", "V4", "V5", "V6")
N_LEADS: Final = 12
SUPERCLASSES: Final[tuple[str, ...]] = ("NORM", "MI", "STTC", "CD", "HYP")
QUALITY_LABELS: Final[tuple[str, ...]] = ("static_noise", "burst_noise", "baseline_drift", "electrode_problem")
SAMPLING_RATES: Final[tuple[int, ...]] = (100, 500)
RECORD_SECONDS: Final = 10
SPLIT_FOLDS: Final[Mapping[str, tuple[int, ...]]] = MappingProxyType(
    {"train": (1, 2, 3, 4, 5, 6, 7, 8), "val": (9,), "test": (10,)})
QUALITY_STATUSES: Final = ("ACCEPT", "WARN", "REJECT")
RESPONSE_STATUSES: Final = ("OK", "ABSTAIN", "REJECTED")

def n_samples(sampling_rate: int) -> int: ...       # sampling_rate * RECORD_SECONDS
def split_of_fold(fold: int) -> str: ...            # ValueError dla fold spoza 1–10

# src/cardioai/utils/logging.py
def get_logger(name: str) -> logging.Logger: ...
def setup_logging(level: str | None = None) -> None: ...   # domyślnie CARDIOAI_LOG_LEVEL lub INFO
```

Wzorzec konfiguracji PyTorch w `pyproject.toml` (zweryfikuj z przewodnikiem uv „Using uv with PyTorch”):

```toml
[tool.uv]
conflicts = [[{ extra = "cpu" }, { extra = "cuda" }]]

[tool.uv.sources]
torch = [
  { index = "pytorch-cpu", extra = "cpu", marker = "sys_platform != 'darwin'" },
  { index = "pytorch-cuda", extra = "cuda" },
]

[[tool.uv.index]]
name = "pytorch-cpu"
url = "https://download.pytorch.org/whl/cpu"
explicit = true

[[tool.uv.index]]
name = "pytorch-cuda"
url = "https://download.pytorch.org/whl/cu126"   # wariant do potwierdzenia (D-005)
explicit = true
```

## Kryteria akceptacji

- [x] `uv sync --extra cpu --extra all` działa na Linuksie i macOS; na Macu `torch.backends.mps.is_available()` zwraca `True`.
- [ ] `uv sync --extra cuda --extra all` działa na laptopie z RTX 2060 (Windows); `torch.cuda.is_available()` zwraca `True` (wynik wklejony do PR).
- [x] `uv.lock` jest w repo, a `uv sync --locked --extra cpu` przechodzi w czystym środowisku.
- [x] `uv run pytest`, `uv run ruff check .`, `uv run ruff format --check .` i `uv run lint-imports` przechodzą.
- [x] `pre-commit` blokuje plik większy niż 1 MB (`check-added-large-files --maxkb=1000`).
- [x] `.gitignore` obejmuje: `data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `mlflow.db`, `models/bundles/`, `reports/*` (z wyjątkami `!reports/final/` i `!reports/docs-audit/`),
      `*.pt`, `*.onnx`, `*.npy`, `.env`, `CLAUDE.local.md`, `.venv/`, `node_modules/`, `web/dist/` oraz katalogi cache narzędzi.
- [x] `.gitattributes`: `* text=auto eol=lf` oraz `binary` dla `*.dat *.npy *.npz *.pt *.onnx *.png *.pdf *.parquet`.
- [x] `.env.example` zawiera wszystkie zmienne z `docs/environment.md` §4 (z wartościami domyślnymi lub pustymi).
- [x] Wpis D-005 w `docs/decisions.md` uzupełniony o wybrany wariant CUDA i uzasadnienie (sterownik, dostępność wheels).

Weryfikacja T001 (2026-11-10): instalacja macOS ARM64 i MPS (`True`) potwierdzone na Pythonie 3.11 i 3.12.
Linux/CPU: rzeczywista instalacja, 48 testów, bramka jakości i budowa pakietu potwierdzone w kontenerach
ARM64 i x86_64 dla obu wersji Pythona. Uzupełniono wymagany runtime OpenMP dla LightGBM.
Windows x86_64 CPU/CUDA: potwierdzono dostępność wheels dla obu wersji Pythona; wykonanie
na Windows z RTX 2060 pozostaje wymagane. Tylko kryterium Windows pozostaje nieodhaczone.
Pełny wynik kontroli:
`reports/final/T001-validation.md`.

## Testy

- `tests/unit/test_smoke.py`: import `cardioai` i `__version__`; `LEADS` ma 12 unikalnych nazw; kolejność `SUPERCLASSES`;
  foldy w `SPLIT_FOLDS` są rozłączne i pokrywają 1–10; `n_samples(100) == 1000`; `split_of_fold(10) == "test"`; `split_of_fold(11)` zgłasza `ValueError`.
- `tests/integration/test_installation.py`: importy zainstalowanych zależności, w tym ładowanie bibliotek
  natywnych (testy `slow`), oraz dostępność wheels z lockfile dla macOS ARM64, Windows x86_64
  i Linux x86_64/ARM64. Kontrola platform działa offline bez pobierania i budowania zależności.

## Weryfikacja

```bash
uv sync --extra cpu --extra all
uv run pytest -q
uv run ruff check . && uv run ruff format --check .
uv run lint-imports
uv run pre-commit run --all-files
```

## Wskazówki i pułapki

- `torch` jest tylko w extras — `uv sync` bez extras nie zainstaluje PyTorch; CI i dokumentacja zawsze podają extra.
- `import-linter` potrzebuje `root_packages = ["cardioai", "cardioai_api"]`; kontrakt `forbidden` dla `cardioai_api` (wszystko poza `cardioai.inference`, `cardioai.constants`).
  Zakazy dotyczą importów bezpośrednich (D-024): kontrakty `cardioai_api` i `cardioai.tracking` mają `allow_indirect_imports = true`,
  a wyjątek pyfunc zapisz jako `ignore_imports = ["cardioai.tracking.pyfunc -> cardioai.inference"]`.
- Nie dodawaj `-m` do `addopts` pytest — testy `requires_data` same się pomijają, gdy brak danych (T103/T104).
- Na Windows sprawdź, czy indeks CUDA ma wheel dla Twojej wersji Pythona (`cp312-win_amd64`).
