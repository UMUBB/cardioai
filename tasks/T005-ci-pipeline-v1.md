---
id: T005
title: CI v1 — lint, granice modułów i testy na każdym PR
epic: foundation
owner: B
reviewer: C
week: 1
size: S
level: MVP
gate: G1
experiment: none
depends_on: [T001]
status: todo
---

# T005 — CI v1: lint, granice modułów i testy na każdym PR

## Kontekst

- `docs/mlops.md` §6 (CI/CD)
- `AGENTS.md` §7 (Definition of Done), §8 (testy)

## Cel

Każdy PR jest automatycznie sprawdzany tą samą bramką, którą agent uruchamia lokalnie, więc błąd zasad lub granic modułów nie trafi do `main`.

## Zakres

- `.github/workflows/ci.yml`: wyzwalacze `pull_request` i `push` do `main`; `ubuntu-latest`; `astral-sh/setup-uv` z cache.
- Kroki: `uv sync --locked --extra cpu --extra all` → `ruff check` → `ruff format --check` → `lint-imports` → `mypy src` (na start `continue-on-error: true`)
  → `pytest -m "not requires_data and not slow and not gpu" --cov=cardioai`.
- `concurrency` z anulowaniem poprzednich przebiegów dla tej samej gałęzi; `timeout-minutes: 15`.
- Krótka instrukcja ochrony gałęzi `main` (wymagany status CI, 1 akceptacja) w opisie PR — ustawia administrator repo.

## Poza zakresem

- Job frontendu, budowa obrazów Docker, sprawdzanie `api/openapi.json`, wydania (T702).

## Pliki

- `.github/workflows/ci.yml` — nowy

## Kryteria akceptacji

- [ ] CI uruchamia się na PR i na `main`, jest zielone na `main`.
- [ ] CI instaluje PyTorch w wariancie CPU (brak pobierania pakietów `nvidia-*` w logu).
- [ ] Pełny przebieg ≤ 10 minut przy ciepłym cache.
- [ ] Naruszenie granic modułów (celowy PR testowy) kończy się czerwonym CI na kroku `lint-imports`.
- [ ] Gałąź `main` chroniona: wymagany zielony CI i 1 akceptacja.

## Testy

- Brak nowych testów; weryfikacja przez przebieg CI na PR testowym.

## Weryfikacja

```bash
# lokalnie te same komendy co w CI
uv sync --locked --extra cpu --extra all
uv run ruff check . && uv run ruff format --check . && uv run lint-imports
uv run pytest -m "not requires_data and not slow and not gpu"
```

## Wskazówki i pułapki

- Zmiana `mypy` na blokujący (`continue-on-error: false`) następuje w T702, gdy kod jest stabilny.
- Nie dodawaj sekretów do workflow w tym zadaniu — nie są potrzebne.
