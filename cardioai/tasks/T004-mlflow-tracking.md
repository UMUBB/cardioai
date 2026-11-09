---
id: T004
title: MLflow — serwer zespołowy i warstwa trackingu
epic: foundation
owner: C
reviewer: B
week: 1
size: M
level: MVP
gate: G1
experiment: none
depends_on: [T002, T003]
status: todo
---

# T004 — MLflow: serwer zespołowy i warstwa trackingu

## Kontekst

- `docs/mlops.md` §1 (hosting), §2 (konwencje i tagi), §3 (parametry, metryki, artefakty)
- `docs/config.md` §6 (nazwa runu, `config_hash`)
- `docs/decisions.md`: D-007

## Cel

Trzy maszyny logują do jednego trackera z jednolitymi tagami, parametrami i układem artefaktów, a kod nie zna adresu serwera.

## Zakres

- Funkcje trackingu (niżej); gdy `tracking.enabled = false` lub brak aktywnego runu — wszystkie są no-op.
- Tagi obowiązkowe z `docs/mlops.md` §2, parametry ze spłaszczonego configu, artefakt `config/resolved.yaml` i `env/env_info.json`.
- `docker/mlflow.compose.yaml` — serwer MLflow (SQLite + serwowane artefakty) do uruchomienia na maszynie zespołu.
- Decyzja o hostingu (wariant A lub B z `docs/mlops.md` §1): uzupełnienie D-007 i §1 oraz instrukcja podłączenia w `docs/environment.md` §4.

## Poza zakresem

- Podsumowania i tabele runów (T209), rejestr modeli (T702).

## Pliki

- `src/cardioai/tracking/__init__.py`, `mlflow_utils.py` — nowe
- `docker/mlflow.compose.yaml` — nowy
- `docs/mlops.md`, `docs/decisions.md`, `docs/environment.md` — aktualizacja
- `tests/unit/tracking/test_mlflow_utils.py` — nowy

## Interfejs (wiążący)

```python
@contextmanager
def start_run(cfg: RunConfig, *, run_name: str | None = None, extra_tags: Mapping[str, str] | None = None,
              nested: bool = False) -> Iterator[mlflow.ActiveRun | None]: ...
@contextmanager
def resume_run(run_id: str) -> Iterator[mlflow.ActiveRun]: ...
def log_config(cfg: RunConfig) -> None: ...
def log_metrics(metrics: Mapping[str, float], step: int | None = None) -> None: ...   # pomija NaN z ostrzeżeniem
def log_artifact_file(path: Path, artifact_path: str | None = None) -> None: ...
def log_artifact_dir(path: Path, artifact_path: str) -> None: ...
def flatten_config(cfg: RunConfig) -> dict[str, str]: ...
def required_tags(cfg: RunConfig) -> dict[str, str]: ...
```

## Kryteria akceptacji

- [ ] `start_run` ustawia wszystkie tagi z `docs/mlops.md` §2 (wartości z configu, `git_sha`, `git_dirty`, `device`, `host`), `stage=dev` domyślnie.
- [ ] Nazwa eksperymentu = `tracking.experiment_name` lub `experiment.name`; nazwa runu z `default_run_name`.
- [ ] Parametry spłaszczone (`training.optimizer.lr`); zbyt długie wartości przycięte z ostrzeżeniem.
- [ ] Bez `MLFLOW_TRACKING_URI` logowanie lokalne w katalogu ignorowanym przez git + ostrzeżenie w logu.
- [ ] Serwer z `docker/mlflow.compose.yaml` działa, a każda z trzech maszyn zalogowała run testowy (zrzut listy runów w PR).
- [ ] D-007 ma status „przyjęta” z opisem wariantu, adresu (bez sekretów) i kopii zapasowej.

## Testy

- `test_mlflow_utils.py` z tymczasowym URI (`tmp_path`): komplet tagów, spłaszczanie, artefakt configu, no-op przy `tracking.enabled=false`,
  pomijanie NaN, `resume_run` dopisuje do istniejącego runu.

## Weryfikacja

```bash
uv run pytest tests/unit/tracking -q
docker compose -f docker/mlflow.compose.yaml up -d
```

## Wskazówki i pułapki

- API MLflow różni się między 2.x i 3.x (np. argumenty `log_model`) — sprawdź wersję z `uv.lock`.
- Ścieżki Windows w URI artefaktów: używaj `Path.as_uri()` albo serwera z `--serve-artifacts`, żeby klient wysyłał artefakty przez HTTP.
- Sekrety (hasła) tylko w `.env`; nigdy w configu ani w tagach.
