## Zadanie

Karta: `tasks/T___-....md` · Gałąź: `t___-...`

## Co zmieniono

-

## Jak przetestowano

```text
uv run ruff check . && uv run ruff format --check .
uv run lint-imports
uv run mypy src   # zalecane, nieblokujące do T702
uv run pytest -m "not requires_data and not slow and not gpu"
(wklej skrócony wynik)
```

Dodatkowo (jeśli dotyczy): testy `requires_data`, run MLflow (link / run_id), zrzut ekranu UI.

## Kontrakty

- [ ] Brak zmian kontraktów (sekcje wiążące: `docs/data_contract.md`, `docs/config.md`, `docs/modeling.md` §1, §2, §6, `docs/inference_api.md` §2, §3, §5–§8,
  `docs/evaluation.md` §2–§5, §7, `docs/reliability.md` §2, §4–§7, `docs/mlops.md` §2–§3, `docs/frontend.md` §4, §5, §7)
- [ ] Zmiana kontraktu — opisana w `docs/...` i w `docs/decisions.md` (D-___)

## Definition of Done (`AGENTS.md` §7)

- [ ] Kryteria akceptacji z karty spełnione (odhaczone w karcie)
- [ ] ruff / lint-imports / pytest zielone (mypy zalecane, nieblokujące do T702)
- [ ] Kod działa na CPU; brak `.cuda()` i float64 w tensorach
- [ ] Typy i docstringi w publicznym API
- [ ] Brak danych, checkpointów i sekretów w diffie
- [ ] Dokumentacja zaktualizowana
- [ ] Status karty: `review`

## Odstępstwa od karty i otwarte pytania

-
