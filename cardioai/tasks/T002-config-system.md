---
id: T002
title: System konfiguracji (YAML + Pydantic, extends, --set, config_hash)
epic: foundation
owner: B
reviewer: C
week: 1
size: M
level: MVP
gate: G1
experiment: none
depends_on: [T001]
status: todo
---

# T002 — System konfiguracji

## Kontekst

- `docs/config.md` §1–§7 (cały dokument jest kontraktem tego zadania)
- `AGENTS.md` §5 (konwencje)
- `docs/decisions.md`: D-006, D-025

## Cel

Każdy run jest opisany jednym walidowanym obiektem `RunConfig`, zbudowanym z plików YAML (`extends`) i nadpisań `--set`,
z deterministycznym `config_hash` do grupowania runów różniących się tylko seedem.

## Zakres

- Modele Pydantic v2 (`extra="forbid"`) dla wszystkich sekcji z `docs/config.md` §4, z wartościami domyślnymi z tej sekcji.
- Ładowanie YAML z listą `extends` (ścieżki względne do pliku), scalanie według §3, wykrywanie cykli.
- Nakładanie zmiennych środowiskowych po scaleniu YAML i przed `--set`: `CARDIOAI_DATA_ROOT → data.root`, `CARDIOAI_DEVICE → training.device`
  (pierwszeństwo: `--set` > zmienna środowiskowa > plik YAML > wartość domyślna; `docs/config.md` §1 pkt 4).
- Parsowanie `--set klucz.podklucz=wartość` (wartość przez `yaml.safe_load`), `add_config_args` dla argparse.
- `config_hash` według §6, `dump_resolved` (YAML), `default_run_name`.
- Configi: `configs/base.yaml`, `configs/data/ptbxl_100.yaml`, `configs/data/ptbxl_500.yaml`, `configs/experiment/e00_smoke.yaml`.

## Poza zakresem

- Walidacja `model.params` i parametrów augmentacji (rejestry w T202 i T109 — tu tylko `dict[str, Any]`).
- Integracja z MLflow (T004).

## Pliki

- `src/cardioai/config/__init__.py`, `schema.py`, `loader.py` — nowe
- `configs/base.yaml`, `configs/data/ptbxl_100.yaml`, `configs/data/ptbxl_500.yaml`, `configs/experiment/e00_smoke.yaml` — nowe
- `tests/unit/config/test_schema.py`, `tests/unit/config/test_loader.py` — nowe

## Interfejs (wiążący)

```python
class RunConfig(BaseModel):            # sekcje: experiment, seed, data, preprocessing, augmentations,
    ...                                 # quality, model, training, evaluation, tracking, output_dir
class AugmentationSpec(BaseModel):     # name: str, p: float, + dowolne parametry (model_config extra="allow")
    ...

def load_config(path: str | Path, overrides: Sequence[str] = ()) -> RunConfig: ...
def deep_merge(base: dict[str, Any], update: dict[str, Any]) -> dict[str, Any]: ...
def parse_override(item: str) -> tuple[list[str], Any]: ...        # "a.b=1e-3" -> (["a","b"], ...)
def config_hash(cfg: RunConfig) -> str: ...                       # 12 znaków hex
def dump_resolved(cfg: RunConfig, path: Path) -> None: ...
def default_run_name(cfg: RunConfig) -> str: ...                   # docs/config.md §6
def add_config_args(parser: argparse.ArgumentParser) -> None: ...  # --config (wymagany), --set (wielokrotny)
class ConfigError(ValueError): ...
```

## Kryteria akceptacji

- [ ] Wszystkie klucze z `docs/config.md` §4 istnieją z tymi samymi wartościami domyślnymi; `configs/base.yaml` je odzwierciedla.
- [ ] Nieznany klucz → `ConfigError` z pełną ścieżką klucza (np. `training.optimzer`).
- [ ] Scalanie: słowniki rekurencyjnie, listy w całości, `null` nadpisuje; kolejność warstw: `extends` → plik → zmienne środowiskowe → `--set`.
- [ ] `CARDIOAI_DATA_ROOT` i `CARDIOAI_DEVICE` nadpisują `data.root` i `training.device` z YAML, a `--set` nadpisuje zmienną środowiskową.
- [ ] Cykl w `extends` → `ConfigError`; klucz `extends` nie trafia do wyniku.
- [ ] `config_hash` nie zależy od kolejności kluczy ani od pól wyłączonych w §6 (seed, tracking, output_dir, data.root, data.num_workers, data.cache_dir,
      data.batch_size_eval, training.log_every_n_steps, training.device); zmiana `training.amp` zmienia hash.
- [ ] `dump_resolved` → `load_config` daje równy obiekt.
- [ ] `e00_smoke.yaml`: 1 epoka, `batch_size: 8`, `data.cache_dir: null`, `data.num_workers: 0`, `tracking.enabled: false`, model `debug_linear` (implementacja w T202).
- [ ] Walidacja zakresów: `data.sampling_rate ∈ {100, 500}`, `0 ≤ p ≤ 1` w augmentacjach, `training.epochs ≥ 1`, `preprocessing.notch_hz < sampling_rate/2` (gdy ustawione).

## Testy

- `test_loader.py`: scalanie (słownik, lista, null), kolejność warstw (w tym zmienne środowiskowe: YAML < env < `--set`, przez `monkeypatch.setenv`), `--set` dla int/float/bool/list/null/str, cykl `extends`,
  ścieżki względne `extends` z podkatalogów, stabilność `config_hash` (permutacja kluczy, zmiana seeda → ten sam hash, zmiana `lr` → inny).
- `test_schema.py`: wartości domyślne, `extra="forbid"`, walidacje zakresów, round-trip YAML.

## Weryfikacja

```bash
uv run pytest tests/unit/config -q
uv run python -c "from cardioai.config import load_config; print(load_config('configs/experiment/e00_smoke.yaml'))"
```

## Wskazówki i pułapki

- PyYAML (YAML 1.1) czyta `1e-3` jako **tekst** — w plikach YAML pisz `1.0e-3`; pola typowane Pydantic i tak skonwertują tekst w trybie lax,
  ale `model.params` (słownik) nie — walidacja nastąpi dopiero w `Params` modelu (T202).
- Hash licz z `model_dump(mode="json")` z posortowanymi kluczami, nie z tekstu YAML.
