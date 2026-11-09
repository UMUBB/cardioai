---
id: T610
title: Integracja quality gate, kalibracji, abstention i XAI w Predictorze
epic: product
owner: C
reviewer: A
week: 12
size: M
level: Core
gate: G5
experiment: none
depends_on: [T304, T501, T502, T503, T603]
status: todo
---

# T610 — Integracja quality gate, kalibracji, abstention i XAI w `Predictor`

## Kontekst

- `docs/architecture.md` §6 (kroki 4–8), §7 (statusy)
- `docs/reliability.md` §4–§7
- `docs/inference_api.md` §2 (sekcje bundla), §7 (pola odpowiedzi)

## Cel

Pełny pipeline inferencji z bundla: odrzucanie złej jakości, skalibrowane prawdopodobieństwa, jawne „nie wiem” i atrybucja — dokładnie te komponenty, które dopasowano offline.

## Zakres

- Odtworzenie z `BundleSpec`: `QualityGate.from_dict`, `calibrator_from_dict`, progi, `AbstentionPolicy.from_dict`, ustawienia XAI.
- `Predictor.predict`: reguły twarde + głowa jakości → status gate; `REJECT` → `REJECTED` (bez predykcji); kalibracja → progi → niepewność → `ABSTAIN`;
  XAI dla `OK` (lub `explain="always"`), ostrzeżenie `EXPLANATION_SKIPPED` w pozostałych przypadkach; ostrzeżenia `QUALITY_WARN`, `FLAT_LEAD`, `SATURATION`.
- Eksport bundla kandydata z kompletem komponentów (`scripts/export_model.py`) i sprawdzenie w UI (zrzut ekranu XAI do PR).

## Poza zakresem

- Zmiany kontraktu API (jeśli konieczne — zatrzymaj się i zapytaj).

## Pliki

- `src/cardioai/inference/predictor.py` — zmiana
- `tests/unit/inference/test_predictor_reliability.py` — nowy
- `tests/integration/test_predictor_parity.py` — zmiana (parzystość z kalibracją)

## Kryteria akceptacji

- [ ] Sygnał z 3 płaskimi odprowadzeniami → `REJECTED`, `predictions = None`, powód `FLAT_LEAD`.
- [ ] Wymuszona wysoka niepewność (model-atrapa zwracający logity ≈ 0) → `ABSTAIN` z `abstain_reasons`.
- [ ] Prawdopodobieństwa skalibrowane zgodne z `scripts/calibrate.py` dla tych samych logitów (tolerancja 1e-6).
- [ ] `explanation` obecne dla `OK`, nieobecne dla `ABSTAIN` przy `explain="auto"`, obecne przy `explain="always"`.
- [ ] Bundle z wyłączonymi komponentami nadal działa (zachowanie z T603).
- [ ] Zrzut ekranu UI z nakładką XAI dla rekordu demo dołączony do PR.

## Testy

- `test_predictor_reliability.py`: trzy statusy, ostrzeżenia, kalibracja, XAI zależne od statusu, komponenty wyłączone.

## Weryfikacja

```bash
uv run pytest tests/unit/inference tests/integration/test_predictor_parity.py -q
uv run python scripts/export_model.py --checkpoint <best.pt> --version 1.0.0 --calibration <...> --thresholds <...> --quality-gate <...> --abstention <...>
```

## Wskazówki i pułapki

- Kolejność jest wiążąca: gate → kalibracja → progi → abstention → XAI. Zmiana kolejności zmienia semantykę statusów.
- XAI liczy gradienty — wykonuj je poza `inference_mode()` i tylko dla jednego rekordu.
