---
id: T801
title: Zamrożenie konfiguracji i jednorazowa ewaluacja na foldzie 10 (G6)
epic: final
owner: B
reviewer: C
week: 14
size: M
level: Core
gate: G6
experiment: none
depends_on: [T209, T306, T504, T610, T701]
status: todo
---

# T801 — Zamrożenie konfiguracji i jednorazowa ewaluacja na foldzie 10 (G6)

## Kontekst

- `docs/evaluation.md` §7 (blokada testu, checklista), §8 (bootstrap pacjentów)
- `docs/reliability.md` §8 (robustness na teście — tylko tutaj)
- `AGENTS.md` §2 pkt 2
- Specyfikacja, Załącznik B (checklista przed finalnym testem)

## Cel

Wiarygodny wynik końcowy: test użyty dokładnie raz, po formalnym zamrożeniu modeli, progów i kalibracji, z przedziałami ufności i pełnym śladem audytowym.

## Zakres

- `scripts/final_checklist.py`: automatyczne sprawdzenie punktów z `docs/evaluation.md` §7 (niezmienniki indeksu, źródło statystyk, `fitted_on: "val"`,
  kompletne `provenance` bundli, czyste drzewo git, ≥ 3 seedy rodziny finalnej, brak wpisów w `release/final_test_log.jsonl`), lista modeli do oceny,
  akceptacja A/B/C (pola w pliku) → `release/final_freeze.json` (commitowany).
- Przedziały ufności z `cardioai.evaluation.bootstrap` (bootstrap pacjentów, B = 1000, seed 0, wariant sparowany) — moduł powstaje w T209, tu tylko z niego korzystamy.
- `scripts/final_test.py`: wymaga `CARDIOAI_ALLOW_TEST=1` i pliku zamrożenia; dla każdego zamrożonego bundla jednorazowo: predykcje i metryki testu,
  przedziały ufności, robustness suite na teście, tag `stage=final`, wpis w `release/final_test_log.jsonl`; kolejne uruchomienie dla tego samego bundla → odmowa.
- Tabela wyników testu w `docs/experiments.md` §5 i w `docs/model_card.md` (T802 korzysta).

## Poza zakresem

- Jakiekolwiek zmiany modeli po zamrożeniu — wymagają nowego wydania i opisu w raporcie jako ograniczenie.

## Pliki

- `scripts/final_checklist.py`, `scripts/final_test.py` — nowe
- `src/cardioai/data/test_lock.py` — zmiana (walidacja treści `final_freeze.json`)
- `release/final_freeze.json`, `release/final_test_log.jsonl` — nowe (commitowane)
- `tests/unit/data/test_test_lock_final.py` — nowy

## Interfejs (wiążący)

Funkcje `patient_bootstrap` i `paired_patient_bootstrap` (`cardioai.evaluation.bootstrap`) są zdefiniowane w T209; T801 ich używa bez zmian sygnatur.

## Kryteria akceptacji

- [ ] `final_checklist.py` przechodzi bez wyjątków; każdy punkt checklisty ma wynik OK/FAIL w raporcie.
- [ ] `final_freeze.json` zawiera wersje bundli, `config_hash`, git SHA, datę i akceptacje A, B, C.
- [ ] Test oceniony dokładnie raz na bundel (log + tag MLflow `stage=final`); drugie uruchomienie → odmowa.
- [ ] Tabela: macro/micro AUROC, macro F1, AP, per klasa, 95% CI z bootstrapu pacjentów (moduł z T209), ECE i coverage przy `τ`.

## Testy

- `test_test_lock_final.py`: odmowa bez pliku, bez zmiennej, przy niepoprawnej treści pliku, przy powtórnej ocenie tego samego bundla.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_test_lock_final.py -q
uv run python scripts/final_checklist.py
CARDIOAI_ALLOW_TEST=1 uv run python scripts/final_test.py --freeze release/final_freeze.json
```

## Wskazówki i pułapki

- Uruchom na urządzeniu kanonicznym (laptop A, D-019) z czystym drzewem git.
- Zanim ustawisz `CARDIOAI_ALLOW_TEST=1`, zrób przegląd zamrożenia z całym zespołem — to jednorazowa operacja.
