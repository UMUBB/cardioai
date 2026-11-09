---
id: T608
title: Panele wyniku — predykcje, jakość, status, informacje o modelu
epic: product
owner: C
reviewer: B
week: 6
size: M
level: Core
gate: G5
experiment: none
depends_on: [T607]
status: todo
---

# T608 — Panele wyniku: predykcje, jakość, status, informacje o modelu

## Kontekst

- `docs/frontend.md` §5 (komponenty), §7 (teksty i zastrzeżenia — wiążące)
- `docs/architecture.md` §7 (semantyka statusów)
- `docs/inference_api.md` §7 (pola odpowiedzi)

## Cel

Użytkownik rozumie wynik: które klasy są powyżej progów, jak pewny jest model, czy sygnał jest dobrej jakości i kiedy system odmawia odpowiedzi.

## Zakres

- `StatusBanner` (`OK` / `ABSTAIN` / `REJECTED`, tekst + ikona), `PredictionTable` (pasek prawdopodobieństwa, znacznik progu, decyzja, informacja o kalibracji),
  `QualityPanel` (status, wynik, prawdopodobieństwa artefaktów, powody, ostrzeżenia), `ModelInfoPanel` (wersje, `fs`, `timing_ms`, tryb).
- Prezentacja `ABSTAIN`: prawdopodobieństwa wyszarzone z adnotacją; `REJECTED`: brak tabeli predykcji, powody z `signal_quality.reasons`.
- Słownictwo z §7 (żadnego „diagnoza”, „pacjent ma”).
- Dostępność: status nie tylko kolorem, kontrast WCAG AA.

## Poza zakresem

- XAI (T609).

## Pliki

- `web/src/components/StatusBanner.tsx`, `PredictionTable.tsx`, `QualityPanel.tsx`, `ModelInfoPanel.tsx` — nowe
- `web/src/pages/ResultView.tsx` — nowy lub zmiana
- `web/tests/ResultView.test.tsx` — nowy

## Kryteria akceptacji

- [ ] Fixture'y odpowiedzi dla `OK`, `ABSTAIN`, `REJECTED` renderują się zgodnie z `docs/frontend.md` §7 (testy snapshot lub asercje tekstów).
- [ ] W tekstach UI brak słów „diagnoza”/„diagnozuje” (test przeszukujący `pl.ts`).
- [ ] Znacznik progu w `PredictionTable` odpowiada wartości z `thresholds`.
- [ ] Ostrzeżenia z `warnings[]` widoczne z czytelnym komunikatem.

## Testy

- `ResultView.test.tsx`: trzy statusy, ostrzeżenia, brak predykcji przy `REJECTED`, tryb mock.

## Weryfikacja

```bash
cd web && npm run lint && npm run typecheck && npm test
```

## Wskazówki i pułapki

- Typy pól bierz z `schema.d.ts`; nie twórz ręcznych duplikatów interfejsów odpowiedzi.
