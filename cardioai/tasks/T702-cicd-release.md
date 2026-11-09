---
id: T702
title: CI/CD pełne — frontend, obrazy, wydania i promocja modelu
epic: deploy
owner: C
reviewer: A
week: 13
size: M
level: Core
gate: G5
experiment: none
depends_on: [T005, T606, T701]
status: todo
---

# T702 — CI/CD pełne: frontend, obrazy, wydania i promocja modelu

## Kontekst

- `docs/mlops.md` §4 (rejestr, aliasy, promocja), §6 (pipeline'y), §8 (wydania)
- `docs/inference_api.md` §10 (aktualność `api/openapi.json`)
- `docs/decisions.md`: D-022

## Cel

Każdy PR sprawdza cały system (Python i frontend), `main` buduje obrazy, a tag `v*` publikuje wersjonowane obrazy i wydanie z bundlem i kartą modelu.

## Zakres

- `ci.yml`: job `web` (`npm ci`, `gen:api` + kontrola różnic, lint, typecheck, test, build); kontrola `api/openapi.json` (`export_openapi.py` + `git diff --exit-code`);
  `mypy` blokujący; na `main` — budowa obrazów bez publikacji i `smoke_e2e.py` w trybie mock.
- `release.yml` (tag `v*`): budowa i publikacja obrazów `api` i `web` w GHCR z tagiem wersji, wydanie GitHub z bundlem (`.zip`), `model_card.md` i skrótem metryk.
- `scripts/promote_model.py --model-version X --alias champion`: rejestracja bundla jako modelu pyfunc `cardioai-diagnosis` w MLflow (wrapper ładujący `Predictor`) i ustawienie aliasu po ręcznej akceptacji.
- Opis procesu promocji w `docs/mlops.md` §4 (aktualizacja, jeśli różni się od planu).

## Poza zakresem

- Wdrożenie na serwer publiczny.

## Pliki

- `.github/workflows/ci.yml` — zmiana; `.github/workflows/release.yml` — nowy
- `scripts/promote_model.py` — nowy
- `src/cardioai/tracking/pyfunc.py` — nowy (wrapper MLflow ładujący `Predictor`; `tracking` może importować `inference`, odwrotnie nie — `AGENTS.md` §3)
- `docs/mlops.md`, `docs/decisions.md` — aktualizacja

## Kryteria akceptacji

- [ ] PR ze zmianą frontendu lub API bez regeneracji `openapi.json`/`schema.d.ts` → czerwone CI.
- [ ] Na `main` obrazy budują się, a `smoke_e2e.py` (mock) przechodzi w CI.
- [ ] Tag testowy (np. `v0.9.0-rc1`) publikuje obrazy w GHCR i tworzy wydanie z bundlem i kartą modelu.
- [ ] `promote_model.py` rejestruje wersję w MLflow i ustawia alias `champion` (zrzut z UI MLflow w PR).
- [ ] Czas PR-CI ≤ 15 min.

## Testy

- Przebiegi workflow na PR testowym i tagu testowym; test jednostkowy wrappera pyfunc (ładowanie bundla testowego, `predict` na ramce z sygnałem).

## Weryfikacja

```bash
uv run python scripts/export_openapi.py && git diff --exit-code api/openapi.json
uv run python scripts/promote_model.py --model-version resnet1d-1.0.0 --alias candidate
```

## Wskazówki i pułapki

- Publikacja w GHCR wymaga `permissions: packages: write` w workflow.
- Wrapper pyfunc mieszka w `cardioai.tracking`, więc `cardioai.inference` i API nadal nie zależą od `mlflow`.
