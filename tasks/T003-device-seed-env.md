---
id: T003
title: Device, seed, AMP, git i informacje o środowisku
epic: foundation
owner: B
reviewer: A
week: 1
size: S
level: MVP
gate: G1
experiment: none
depends_on: [T001]
status: todo
---

# T003 — Device, seed, AMP, git i informacje o środowisku

## Kontekst

- `AGENTS.md` §2 pkt 5 i 9 (device, losowość)
- `docs/modeling.md` §8 (AMP, urządzenia, determinizm)
- `docs/environment.md` §3, §4

## Cel

Jedno miejsce wyboru urządzenia, AMP i seedów, dzięki któremu ten sam kod działa na CPU, CUDA i MPS bez warunków rozsianych po projekcie.

## Zakres

- `get_device` z kolejnością CUDA → MPS → CPU i obsługą `CARDIOAI_DEVICE`.
- `autocast_context` i `make_grad_scaler` (AMP tylko na CUDA, fp16).
- `seed_everything`, `make_rng`; opcjonalny tryb deterministyczny.
- `git_sha`, `git_dirty` (bez zależności od biblioteki GitPython — `subprocess`).
- `collect_env_info`, `load_env` (`.env` przez `python-dotenv`).
- `scripts/env_check.py` — wypisuje JSON z informacjami i wykonuje test mnożenia macierzy na wybranym urządzeniu.

## Poza zakresem

- Tagi MLflow (T004) — korzystają z funkcji z tego zadania.

## Pliki

- `src/cardioai/utils/device.py`, `seed.py`, `git.py`, `env.py` — nowe
- `scripts/env_check.py` — nowy
- `tests/unit/utils/test_device.py`, `test_seed.py`, `test_git_env.py` — nowe

## Interfejs (wiążący)

```python
def get_device(preference: str | None = None) -> torch.device: ...
    # preference to wartość już rozstrzygnięta przez loader configu (T002; D-025) i nie jest łączona ze zmienną środowiskową;
    # None (wywołania bez configu, np. env_check.py) -> CARDIOAI_DEVICE -> "auto"
    # "cuda"/"mps" niedostępne -> DeviceUnavailableError (bez cichego fallbacku)
def autocast_context(device: torch.device, enabled: bool) -> AbstractContextManager[None]: ...
def make_grad_scaler(device: torch.device, enabled: bool) -> torch.amp.GradScaler | None: ...
def seed_everything(seed: int, *, deterministic: bool = False) -> None: ...
def make_rng(*keys: int) -> np.random.Generator: ...        # np.random.default_rng(list(keys))
def git_sha(short: bool = True) -> str: ...                 # "unknown" poza repo
def git_dirty() -> bool | None: ...
def collect_env_info() -> dict[str, str]: ...               # python, torch, cuda, cudnn, device_name, mps, os, host, git
def load_env(path: Path | None = None) -> bool: ...         # True, gdy plik .env wczytany
class DeviceUnavailableError(RuntimeError): ...
```

## Kryteria akceptacji

- [ ] `get_device("auto")` na maszynie bez GPU zwraca `cpu`; `get_device(None)` z `CARDIOAI_DEVICE=cpu` wymusza CPU nawet przy dostępnej CUDA.
- [ ] Żądanie `cuda` lub `mps` bez dostępności → `DeviceUnavailableError` z czytelnym komunikatem.
- [ ] `autocast_context` dla CPU i MPS zwraca kontekst pusty; dla CUDA z `enabled=True` — `torch.autocast("cuda", dtype=torch.float16)`.
- [ ] `seed_everything(0)` daje powtarzalne `random`, `numpy` i `torch`; `deterministic=True` ustawia `torch.use_deterministic_algorithms(True, warn_only=True)` i ostrzega o `CUBLAS_WORKSPACE_CONFIG`.
- [ ] `scripts/env_check.py` działa na każdej maszynie zespołu (wynik z każdej w PR lub w komentarzu).

## Testy

- `test_device.py`: monkeypatch `torch.cuda.is_available` / `torch.backends.mps.is_available`; zmienna środowiskowa (tylko przy `preference=None`); błędne wartości.
- `test_seed.py`: powtarzalność `make_rng(1, 2, 3)`; różne klucze → różne strumienie.
- `test_git_env.py`: `git_sha` poza repo (tmp) → `"unknown"`; `load_env` na pliku tymczasowym.

## Weryfikacja

```bash
uv run pytest tests/unit/utils -q
uv run python scripts/env_check.py
```

## Wskazówki i pułapki

- `torch.amp.GradScaler("cuda")` zastąpił starsze `torch.cuda.amp.GradScaler` — użyj nowego API.
- Nie używaj `torch.set_default_dtype(torch.float64)` nigdzie w projekcie.
