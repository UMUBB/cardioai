---
id: T000
title: Krótki tytuł w trybie rozkazującym
epic: data
owner: A
reviewer: B
week: 1
size: M
level: MVP
gate: none
experiment: none
depends_on: []
status: todo
---

# T000 — Krótki tytuł

## Kontekst

- `AGENTS.md` §2 (reguły nienaruszalne)
- `docs/<dokument>.md` §N (czego dotyczy)

## Cel

Jedno–dwa zdania: jaki problem rozwiązuje zadanie i co będzie możliwe po jego wykonaniu.

## Zakres

- Konkretne elementy do zrobienia.

## Poza zakresem

- Co świadomie zostaje na później (z numerem zadania, jeśli istnieje).

## Pliki

- `src/cardioai/<pakiet>/<moduł>.py` — nowy / zmiana
- `tests/unit/<pakiet>/test_<moduł>.py` — nowy

## Interfejs (wiążący)

```python
def function_name(arg: Type) -> ReturnType: ...
```

## Kryteria akceptacji

- [ ] Mierzalny warunek 1.
- [ ] Mierzalny warunek 2.

## Testy

- `tests/unit/...`: co sprawdza każdy test.

## Weryfikacja

```bash
uv run pytest tests/unit/<pakiet> -q
```

## Wskazówki i pułapki

- Znane problemy, decyzje do podjęcia, linki do dokumentacji bibliotek.
