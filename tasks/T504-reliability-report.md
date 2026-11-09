---
id: T504
title: Raport niezawodności i przegląd bramki G4
epic: reliability
owner: C
reviewer: B
week: 11
size: S
level: Core
gate: G4
experiment: E09
depends_on: [T304, T305, T501, T502]
status: todo
---

# T504 — Raport niezawodności i przegląd bramki G4

## Kontekst

- `docs/reliability.md` §1 (przegląd komponentów), §4–§6
- `docs/experiments.md` §4 (E05, E09)
- `tasks/README.md` §5 (G4)

## Cel

Jeden wygenerowany raport, który pokazuje kompletny obraz niezawodności kandydata na model finalny i jest dowodem zaliczenia bramki G4.

## Zakres

- `scripts/reliability_report.py --run-id ID`: zbiera z runu MLflow (lub lokalnych plików) kalibrację, progi, quality gate, abstention
  i wynik robustness; tworzy `reports/reliability/<run>/report.md` z tabelami i wykresami; loguje do MLflow (`reliability_report/`).
- Sekcje raportu: podsumowanie, kalibracja (przed/po, out-of-fold), progi, quality gate (trade-off), abstention (krzywe, tabela), odporność (skrót), ograniczenia.
- Przegląd G4 przez zespół; notatka w PR.

## Poza zakresem

- Raport końcowy przedmiotu (T803).

## Pliki

- `scripts/reliability_report.py` — nowy
- `src/cardioai/reliability/report.py` — nowy (składanie sekcji Markdown z gotowych danych)
- `tests/unit/reliability/test_report.py` — nowy

## Interfejs (wiążący)

```python
def build_reliability_report(*, calibration: Mapping[str, Any], thresholds: Mapping[str, Any],
                             quality_gate: Mapping[str, Any] | None, abstention: Mapping[str, Any],
                             tables: Mapping[str, pd.DataFrame], figures: Mapping[str, Path]) -> str: ...
```

## Kryteria akceptacji

- [ ] Raport generuje się bez ręcznych kroków dla wskazanego runu; brakujący komponent → sekcja „brak danych” zamiast wyjątku.
- [ ] Wszystkie liczby pochodzą z plików JSON/CSV runu (żadnych wartości wpisanych w kod).
- [ ] Bramka G4 przejrzana przez zespół; decyzje (metoda kalibracji, `τ`, progi gate) zapisane w `docs/experiments.md` (E09) i w `docs/decisions.md`, jeśli zmieniają domyślne ustawienia.

## Testy

- `test_report.py`: składanie raportu z danych syntetycznych, obsługa brakującego komponentu.

## Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_report.py -q
uv run python scripts/reliability_report.py --run-id <run_id>
```

## Wskazówki i pułapki

- Raport ma być czytelny dla prowadzącego: każda tabela z jednym zdaniem interpretacji (generowanym z szablonu, nie „z głowy”).
- Metryki z runu czytaj pod nazwami z `docs/mlops.md` §3 (np. `val/aurc`, `val/selective_risk_cov095`, `val/selective_risk_cov090`, `val/selective_risk_cov080`; D-029).
