---
id: T701
title: Obrazy Docker, docker compose i reverse proxy
epic: deploy
owner: C
reviewer: B
week: 13
size: M
level: Core
gate: G5
experiment: none
depends_on: [T605, T608]
status: todo
---

# T701 — Obrazy Docker, `docker compose` i reverse proxy

## Kontekst

- `docs/mlops.md` §7 (usługi, bundle, tryb mock), §8 (wydania, `fetch_bundle.py`)
- `docs/inference_api.md` §9, §11
- `docs/decisions.md`: D-022, D-026, D-033, D-034
- Specyfikacja §9.3 i Definition of Done („API i UI przez jedno `docker compose up`”)

## Cel

Demo uruchamiane jedną komendą z czystego checkoutu: frontend i API za reverse proxy, z prawdziwym modelem, gdy bundle jest dostępny, i z wyraźnym trybem mock, gdy go nie ma.

## Zakres

- `docker/api.Dockerfile`: Python slim, `uv sync --locked --extra cpu --extra api --extra xai --no-dev` (bez extra `tracking` — obraz API nie zawiera MLflow; D-033), użytkownik bez root, `HEALTHCHECK` na `/v1/health`, bez kodu treningowego w warstwie wykonawczej (tylko pakiety potrzebne do inferencji — sprawdź `lint-imports` i rozmiar).
- `docker/web.Dockerfile`: build Node (`npm ci`, `npm run build`) → Caddy z plikami statycznymi; `docker/Caddyfile`: `/api/*` → `api:8000` z usunięciem prefiksu, reszta → SPA.
- `compose.yaml` w katalogu głównym: usługi `api` i `web` (port 8080), bundle `./models/bundles/current:/bundle:ro`; profil `tracking` z MLflow.
- `scripts/fetch_bundle.py --version TAG` (pobiera asset wydania przez `gh release download` lub HTTPS, rozpakowuje do `models/bundles/<model_version>/` i kopiuje do `models/bundles/current/` — zwykły katalog, nie dowiązanie symboliczne; D-034).
- `scripts/smoke_e2e.py`: sprawdza `http://localhost:8080/api/v1/health`, listę demo i analizę jednego rekordu demo.
- `.dockerignore` (bez `data/`, `outputs/`, `mlruns/`, `node_modules/`).

## Poza zakresem

- Publikacja obrazów w GHCR i workflow wydania (T702).

## Pliki

- `docker/api.Dockerfile`, `docker/web.Dockerfile`, `docker/Caddyfile`, `compose.yaml`, `.dockerignore` — nowe
- `scripts/fetch_bundle.py`, `scripts/smoke_e2e.py` — nowe
- `README.md` — zmiana (sekcja „Demo”)

## Kryteria akceptacji

- [ ] Z czystego checkoutu bez bundla (domyślne `CARDIOAI_PREDICTOR=auto`): `docker compose up --build` → UI na `http://localhost:8080` w trybie mock z banerem; `smoke_e2e.py` przechodzi.
- [ ] Z bundlem w `models/bundles/current`: `predictor_mode: "real"`, analiza rekordu demo zwraca wynik z XAI; `smoke_e2e.py` przechodzi.
- [ ] Obraz API działa jako użytkownik bez root; rozmiary obrazów podane w PR.
- [ ] Healthcheck API zielony; `web` startuje po zdrowym `api` (`depends_on: condition: service_healthy`).
- [ ] Działa na Windows (Docker Desktop + WSL2) i macOS (potwierdzenie z dwóch maszyn).

## Testy

- `scripts/smoke_e2e.py` jako test ręczny/CI (T702 uruchamia go po zbudowaniu obrazów).

## Weryfikacja

```bash
docker compose up --build -d
uv run python scripts/smoke_e2e.py --base-url http://localhost:8080
docker compose down
```

## Wskazówki i pułapki

- Na macOS z Apple Silicon obrazy budują się dla `linux/arm64` — PyTorch CPU ma wheels dla obu architektur; nie wymuszaj `platform`.
- Nie kopiuj `models/bundles/` do obrazu w trybie dev — tylko montowanie; zapieczenie bundla w obrazie wydania to decyzja T702.
