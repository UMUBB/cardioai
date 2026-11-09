---
id: T609
title: Nakładka XAI na sygnał i ranking odprowadzeń
epic: product
owner: C
reviewer: A
week: 11
size: S
level: Core
gate: G5
experiment: E11
depends_on: [T608]
status: todo
---

# T609 — Nakładka XAI na sygnał i ranking odprowadzeń

## Kontekst

- `docs/frontend.md` §5 (`XaiOverlay`, `LeadImportanceChart`, `ClassSelector`), §7 (podpis XAI)
- `docs/inference_api.md` §6 (`explain`, `explain_class`), §7 (pole `explanation`)
- `docs/reliability.md` §7

## Cel

Atrybucja jest widoczna w aplikacji dla wybranego rekordu (wymóg Definition of Done), z jasnym zastrzeżeniem, że to wrażliwość modelu, nie przyczyna kliniczna.

## Zakres

- `XaiOverlay`: atrybucja per odprowadzenie jako tło pod przebiegiem (heatmapa lub kolorowe segmenty) z przełącznikiem i legendą skali `[-1, 1]`.
- `LeadImportanceChart`: ranking 12 odprowadzeń malejąco.
- `ClassSelector`: zmiana klasy → ponowne żądanie z `explain_class` (dla uploadu i demo); stan ładowania.
- Podpis z `docs/frontend.md` §7 zawsze przy nakładce.
- Działa w trybie mock (dane z `MockPredictor`); weryfikacja na prawdziwym modelu po T610.

## Poza zakresem

- Obliczanie atrybucji (T503, T610).

## Pliki

- `web/src/components/XaiOverlay.tsx`, `LeadImportanceChart.tsx`, `ClassSelector.tsx` — nowe
- `web/src/components/EcgViewer.tsx` — zmiana (rysowanie `overlay`)
- `web/tests/Xai.test.tsx` — nowy

## Kryteria akceptacji

- [ ] Nakładka i ranking wyświetlane, gdy `explanation` nie jest `null`; przy `null` — informacja „atrybucja niedostępna dla tego wyniku”.
- [ ] Zmiana klasy wysyła żądanie z `explain_class` i aktualizuje nakładkę.
- [ ] Podpis XAI widoczny zawsze, gdy nakładka jest włączona (test).

## Testy

- `Xai.test.tsx`: renderowanie z fixture'ą, brak `explanation`, przełącznik, wybór klasy.

## Weryfikacja

```bash
cd web && npm run lint && npm run typecheck && npm test
```

## Wskazówki i pułapki

- Atrybucja ma `attribution_fs ≤ 100`, a sygnał może mieć 500 Hz — mapuj indeksy przez czas w sekundach, nie przez indeks próbki.
