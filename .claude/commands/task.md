---
description: Zrealizuj kartę zadania CardioAI, np. /task T103
argument-hint: T###
---

Zrealizuj zadanie **$ARGUMENTS** zgodnie z procesem z `AGENTS.md` §6.

1. Uruchom `python scripts/tasks.py show $ARGUMENTS` i przeczytaj wskazaną kartę w całości.
   Jeśli któraś zależność nie ma statusu `done`, zatrzymaj się i napisz, czego brakuje.
2. Przeczytaj dokumenty z sekcji **Kontekst** karty (konkretne sekcje `§`).
3. Przedstaw plan: pliki do utworzenia i zmiany, publiczne interfejsy, testy, ryzyka.
   Dla rozmiaru L poczekaj na moją akceptację; dla S i M kontynuuj.
4. Zaimplementuj wyłącznie „Zakres”. Interfejsy oznaczone jako wiążące odwzoruj dokładnie.
5. Dodaj testy z sekcji „Testy” i uruchom komendy z sekcji „Weryfikacja” oraz bramkę z `AGENTS.md` §7.
6. Zaktualizuj dokumentację, jeśli zmieniło się zachowanie, i ustaw status:
   `python scripts/tasks.py set-status $ARGUMENTS review`.
7. Zakończ raportem po polsku: zmienione pliki, wyniki testów, odhaczone kryteria akceptacji,
   odstępstwa od karty, otwarte pytania. Zaproponuj treść commita w formacie
   `feat(<moduł>): <opis> [$ARGUMENTS]`.
