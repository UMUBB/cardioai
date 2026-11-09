# Frontend

Status: wymagania funkcjonalne **wiążące** (§4, §5, §7), wybór bibliotek — rekomendacja. Kod: `web/`. Właściciel: C.

## 1. Cel i zasady

Frontend jest demonstratorem systemu: pokazuje 12 odprowadzeń, wyniki wieloetykietowe z progami, jakość sygnału,
abstention i atrybucję XAI. Zasady:

1. Frontend niczego nie liczy — wszystkie liczby pochodzą z API (`docs/inference_api.md` §7).
2. Nie mockujemy API w przeglądarce. W trakcie prac backend działa w trybie mock (`CARDIOAI_PREDICTOR=mock`).
3. Żaden tekst w UI nie sugeruje diagnozy (§7).
4. Interfejs po polsku; teksty w jednym pliku (`web/src/i18n/pl.ts`).

## 2. Stack

| Warstwa | Wybór | Uwagi |
|---|---|---|
| Build | Vite | dev server z proxy `/api` → `http://localhost:8000` |
| UI | React + TypeScript (`strict: true`) | komponenty funkcyjne, hooki |
| Wykresy | Plotly przez `react-plotly.js` + `plotly.js-dist-min` (fabryka `createPlotlyComponent`) | mniejszy bundle niż pełne Plotly |
| Stan serwera | TanStack Query | cache i stany ładowania/błędu |
| Typy API | `openapi-typescript` → `web/src/api/schema.d.ts` (generowany) | klient: `openapi-fetch` |
| Routing | React Router | 4 strony (§4) |
| Testy | Vitest + React Testing Library | Plotly mockowany w testach |
| Jakość | ESLint + Prettier, `tsc --noEmit` | w CI (T702) |

## 3. Struktura katalogu `web/`

```text
web/
├── package.json            # skrypty: dev, build, test, lint, typecheck, gen:api
├── vite.config.ts
├── src/
│   ├── api/                # client.ts, schema.d.ts (generowany), hooks.ts
│   ├── components/         # EcgViewer, PredictionTable, QualityPanel, StatusBanner, ...
│   ├── pages/              # AnalyzePage, DemoPage, ResultView, AboutPage
│   ├── i18n/pl.ts
│   ├── fixtures/           # przykładowe odpowiedzi API do testów (kopie z docs/inference_api.md)
│   └── main.tsx
└── tests/
```

## 4. Strony

| Strona | Ścieżka | Zawartość |
|---|---|---|
| Analiza | `/` | upload WFDB (`.hea` + `.dat`), NPZ lub CSV; pole `sampling_rate` dla CSV; opcjonalne metadane; przycisk „Analizuj” |
| Demo | `/demo` | lista rekordów demo (`ecg_id`, etykiety referencyjne, flagi jakości); wybór uruchamia analizę |
| Wynik | widok w obrębie strony Analiza/Demo | wynik ostatniej analizy (bez trwałego zapisu) |
| O systemie | `/about` | `ModelInfo`, wersje, opis ograniczeń, przypisanie PTB-XL (CC BY 4.0), zastrzeżenie |

Wyniki nie są przechowywane między odświeżeniami strony (prywatność, brak backendu do historii).

## 5. Komponenty

| Komponent | Wymagania |
|---|---|
| `EcgViewer` | 12 odprowadzeń w kolejności `LEADS`; wspólna oś czasu (s) z synchronizowanym zoom/pan; oś Y w mV; układ siatki 3×4 lub kolumna; opcjonalna siatka „papieru EKG” (0,2 s / 0,5 mV); `scattergl` przy 500 Hz; render ≤ 500 ms dla 12×1000 punktów |
| `XaiOverlay` | atrybucja per odprowadzenie jako tło (heatmapa pod linią) z przełącznikiem; skala kolorów z legendą; podpis z §7 |
| `LeadImportanceChart` | ranking 12 odprowadzeń (wykres słupkowy, malejąco) |
| `ClassSelector` | wybór klasy do atrybucji → ponowne żądanie z `explain_class` |
| `PredictionTable` | klasa, prawdopodobieństwo (pasek), znacznik progu, decyzja ponad/poniżej progu, informacja o kalibracji |
| `StatusBanner` | `OK` / `ABSTAIN` („Wymaga ręcznej oceny”) / `REJECTED` („Zbyt niska jakość sygnału”) z ikoną i tekstem |
| `QualityPanel` | status `ACCEPT`/`WARN`/`REJECT`, wynik jakości, prawdopodobieństwa artefaktów, powody i ostrzeżenia |
| `ModelInfoPanel` | `model_version`, `preprocessing_version`, `fs`, `timing_ms`, tryb predyktora (baner przy `mock`) |
| `Disclaimer` | stały, widoczny na każdej stronie (§7) |
| `ErrorAlert` | kod i komunikat z koperty błędu (`docs/inference_api.md` §8) |

Dostępność: status nigdy nie jest przekazywany wyłącznie kolorem (zawsze tekst i ikona), kontrast WCAG AA, obsługa klawiatury dla uploadu i listy demo.

## 6. Komunikacja z API

- Bazowy URL: `/api` (proxy Vite w dev; Caddy w compose usuwa prefiks i przekazuje do `api:8000`).
- Typy: `npm run gen:api` generuje `src/api/schema.d.ts` z `../api/openapi.json`; pliku nie edytujemy ręcznie.
- Upload: `multipart/form-data`; para WFDB wysyłana jako dwa pliki w polu `files`.
- Błędy: zawsze przez kopertę `error.code` → komunikat z `pl.ts` (fallback: `error.message` z API).
- Stany: ładowanie (szkielet + spinner), błąd (`ErrorAlert`), pusty wynik.

## 7. Teksty i zastrzeżenia

- Stałe zastrzeżenie: „CardioAI to prototyp badawczy. Nie jest wyrobem medycznym i nie służy do diagnozowania ani podejmowania decyzji klinicznych.”
- Nazewnictwo: „wynik modelu”, „prawdopodobieństwo według modelu”, „klasa powyżej progu” — **nigdy** „diagnoza”, „pacjent ma…”.
- `ABSTAIN`: „Model nie jest wystarczająco pewny — wynik wymaga ręcznej oceny.” Prawdopodobieństwa wyszarzone, z adnotacją.
- `REJECTED`: „Jakość sygnału jest zbyt niska, aby przeprowadzić analizę.” + powody z `signal_quality.reasons`.
- XAI: „Mapa atrybucji pokazuje wrażliwość modelu na fragmenty sygnału, a nie przyczynę kliniczną.”
- Tryb mock: „TRYB DEMONSTRACYJNY (MOCK) — wyniki są sztuczne.”
- Strona „O systemie”: cytowanie PTB-XL (`docs/data_contract.md` §1) i licencja CC BY 4.0.

## 8. Testy i jakość

- `npm run lint`, `npm run typecheck`, `npm test`, `npm run build` — wszystkie zielone w CI.
- Testy komponentów na fixture'ach odpowiedzi (`src/fixtures/`) dla statusów `OK`, `ABSTAIN`, `REJECTED` i błędu 422.
- Test kolejności odprowadzeń w `EcgViewer` i obecności zastrzeżenia na każdej stronie.
- Ręczny test end-to-end przed wydaniem: `docker compose up` → upload pliku WFDB → wynik z XAI (T701).
