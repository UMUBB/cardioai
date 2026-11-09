---
id: T606
title: Frontend — szkielet, klient API z OpenAPI, strony i tryb demo
epic: product
owner: C
reviewer: A
week: 4
size: M
level: Core
gate: G5
experiment: none
depends_on: [T604]
status: todo
---

# T606 — Frontend: szkielet, klient API z OpenAPI, strony i tryb demo

## Kontekst

- `docs/frontend.md` §1–§4 (zasady, stack, struktura, strony), §6 (komunikacja z API), §7 (teksty), §8 (testy)
- `docs/inference_api.md` §6, §10
- `docs/decisions.md`: D-018

## Cel

Działająca aplikacja webowa rozmawiająca z API w trybie mock: upload pliku, lista rekordów demo, strona „O systemie” i stałe zastrzeżenie — szkielet pod komponenty z T607–T609.

## Zakres

- Vite + React + TypeScript (`strict`), ESLint, Prettier, Vitest + Testing Library, React Router, TanStack Query.
- `npm run gen:api` (`openapi-typescript` z `../api/openapi.json` → `src/api/schema.d.ts`) i klient `openapi-fetch` z bazą `/api`.
- Proxy Vite `/api` → `http://localhost:8000` (z usunięciem prefiksu `/api`).
- Strony: Analiza (formularz uploadu z walidacją po stronie klienta: para `.hea`+`.dat`, `.npz`, `.csv` + `sampling_rate`), Demo (lista rekordów),
  O systemie (`ModelInfo`, wersje, przypisanie PTB-XL, zastrzeżenie); `Disclaimer` i baner trybu mock na każdej stronie.
- Teksty w `src/i18n/pl.ts`; mapowanie kodów błędów API na komunikaty.
- Wynik analizy wyświetlany na razie jako sformatowany JSON (komponenty w T607–T609).

## Poza zakresem

- Wizualizacja sygnału (T607), panele wyników (T608), XAI (T609), obraz Docker (T701).

## Pliki

- `web/` — nowy projekt (`package.json`, `vite.config.ts`, `tsconfig.json`, `src/main.tsx`, `src/pages/*`, `src/api/*`, `src/i18n/pl.ts`, `src/components/Disclaimer.tsx`, `src/components/ErrorAlert.tsx`)
- `web/src/fixtures/` — przykładowe odpowiedzi API (kopie przykładów z `docs/inference_api.md` §7)
- `web/tests/` — testy stron

## Kryteria akceptacji

- [ ] `npm run lint`, `npm run typecheck`, `npm test`, `npm run build` przechodzą.
- [ ] Z backendem w trybie mock: upload pliku NPZ zwraca wynik; lista demo ładuje rekordy; strona „O systemie” pokazuje `model_version` i `predictor_mode`.
- [ ] Zastrzeżenie z `docs/frontend.md` §7 widoczne na każdej stronie (test); baner mock przy `predictor_mode: "mock"`.
- [ ] Błędy API wyświetlane przez `ErrorAlert` z komunikatem z `pl.ts` (test dla 413 i 422).
- [ ] `src/api/schema.d.ts` wygenerowany, nie edytowany ręcznie (nagłówek „generated”).

## Testy

- Testy Vitest: renderowanie stron, zastrzeżenie, obsługa błędów (fetch mockowany w teście jednostkowym — to nie jest mock API w aplikacji).

## Weryfikacja

```bash
cd web && npm ci && npm run gen:api && npm run lint && npm run typecheck && npm test && npm run build
CARDIOAI_PREDICTOR=mock uv run uvicorn cardioai_api.main:app --reload   # w drugim terminalu: cd web && npm run dev
```

## Wskazówki i pułapki

- Node.js w wersji LTS; zablokuj wersje przez `package-lock.json` (commitowany).
- Upload pary WFDB: oba pliki w jednym polu `files` (multiple) — sprawdź, czy `.hea` i `.dat` mają tę samą nazwę bazową przed wysłaniem.
