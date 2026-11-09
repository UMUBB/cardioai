---
id: T607
title: Przeglądarka 12 odprowadzeń (EcgViewer)
epic: product
owner: C
reviewer: A
week: 5
size: M
level: Core
gate: G5
experiment: none
depends_on: [T606]
status: todo
---

# T607 — Przeglądarka 12 odprowadzeń (`EcgViewer`)

## Kontekst

- `docs/frontend.md` §5 (wymagania `EcgViewer`), §8
- `docs/inference_api.md` §7 (pole `signal`)
- `docs/data_contract.md` §7 (kolejność `LEADS`, jednostki)

## Cel

Czytelny, szybki podgląd 12 odprowadzeń z synchronizowanym powiększaniem — podstawa widoku wyniku i nakładki XAI.

## Zakres

- Komponent `EcgViewer` (Plotly przez `react-plotly.js` + `plotly.js-dist-min`): układy `grid12` (3×4 + opcjonalnie pasek rytmu II) i `stack`,
  wspólna oś czasu w sekundach z synchronizowanym zoom/pan, oś Y w mV, opcjonalna siatka papieru EKG (0,2 s / 0,5 mV), `scattergl` przy 500 Hz.
- Obsługa prop `overlay` (dane atrybucji) jako punkt zaczepienia dla T609 (bez rysowania).
- Podłączenie do strony wyniku (Analiza i Demo).

## Poza zakresem

- Rysowanie atrybucji (T609), panele wyników (T608).

## Pliki

- `web/src/components/EcgViewer.tsx` — nowy
- `web/src/components/plotly.ts` — nowy (fabryka komponentu Plotly)
- `web/tests/EcgViewer.test.tsx` — nowy

## Interfejs (wiążący)

```typescript
type SignalPayload = components["schemas"]["SignalPayload"];   // z wygenerowanego schema.d.ts
interface EcgViewerProps {
  signal: SignalPayload;
  layout?: "grid12" | "stack";
  showGrid?: boolean;
  overlay?: { fs: number; values: number[][] } | null;          // [12][T'], skala [-1, 1]
  height?: number;
}
export function EcgViewer(props: EcgViewerProps): JSX.Element;
```

## Kryteria akceptacji

- [ ] Odprowadzenia renderowane i podpisane w kolejności `I, II, III, aVR, aVL, aVF, V1–V6` niezależnie od kolejności w danych (mapowanie po `leads`).
- [ ] Zoom/pan na jednym wykresie przenosi się na pozostałe (wspólna oś X).
- [ ] Render 12×1000 punktów < 500 ms na laptopie zespołu (pomiar w PR); 12×5000 działa płynnie z `scattergl`.
- [ ] Oś Y opisana w mV, oś X w s.

## Testy

- `EcgViewer.test.tsx` (Plotly mockowany): liczba śladów, kolejność i podpisy, przeliczenie osi czasu z `fs`.

## Weryfikacja

```bash
cd web && npm run lint && npm run typecheck && npm test
```

## Wskazówki i pułapki

- Pełny pakiet Plotly ma kilka MB — importuj `plotly.js-dist-min` przez `createPlotlyComponent`.
- Synchronizację osi uzyskasz jednym wykresem z `subplots` i `matches: "x"` — prościej niż 12 osobnych wykresów.
