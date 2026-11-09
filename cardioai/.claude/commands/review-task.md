---
description: Zrecenzuj zmiany względem karty zadania CardioAI, np. /review-task T103
argument-hint: T###
---

Zrecenzuj bieżące zmiany (`git diff main...HEAD`) względem karty **$ARGUMENTS**. Niczego nie poprawiaj — tylko oceń.

Sprawdź po kolei i dla każdego punktu podaj: OK / UWAGA / BŁĄD + plik:linia.

1. Kryteria akceptacji z karty — które są spełnione, których brakuje.
2. Zakres: czy zmiany wychodzą poza „Zakres” lub naruszają „Poza zakresem”.
3. Interfejsy wiążące z karty: nazwy, sygnatury, kształty i typy.
4. Reguły nienaruszalne z `AGENTS.md` §2: split i fold 10, statystyki tylko z train, augmentacje tylko w treningu,
   `get_device()` zamiast `.cuda()`, brak float64, stałe z `cardioai.constants`, jedna implementacja preprocessingu.
5. Granice modułów (`AGENTS.md` §3) — uruchom `uv run lint-imports`.
6. Testy: czy pokrywają przypadki brzegowe z karty; uruchom
   `uv run pytest -m "not requires_data and not slow and not gpu"`.
7. Kontrakty z `docs/`: czy zmiana ich dotyczy i czy jest wpis w `docs/decisions.md`.
8. Jakość: typy, docstringi, obsługa błędów, brak cichych fallbacków, brak danych w diffie.

Zakończ werdyktem: **gotowe do merge** / **wymaga poprawek** (lista konkretnych poprawek).
