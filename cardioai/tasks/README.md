# Zadania CardioAI — jak z nich korzystać

Projekt jest podzielony na karty zadań `T###-*.md`, z których każda da się zrealizować w jednej sesji z narzędziem
wspomagającym kodowanie (Codex, Claude Code, Cursor, Copilot, Gemini). Zasady wspólne dla wszystkich zadań są
w `AGENTS.md`; karta zawiera tylko to, co specyficzne dla zadania, i odsyła do kontraktów w `docs/`.

## 1. Czym jest karta zadania

| Sekcja | Rola |
|---|---|
| front matter (YAML) | metadane czytane przez `scripts/tasks.py` (§2) |
| Kontekst | dokumenty i sekcje `§`, które agent musi przeczytać |
| Cel | jedno–dwa zdania: po co jest to zadanie |
| Zakres / Poza zakresem | granice — „Poza zakresem” jest wiążące |
| Pliki | co powstaje lub się zmienia |
| Interfejs | sygnatury i kształty; oznaczone jako **wiążące** implementujemy dokładnie |
| Kryteria akceptacji | lista kontrolna do odhaczenia w PR |
| Testy | testy, które muszą powstać |
| Weryfikacja | komendy do uruchomienia przed PR |
| Wskazówki i pułapki | znane problemy i decyzje do podjęcia |

Szablon nowej karty: `tasks/TEMPLATE.md`.

## 2. Front matter — pola

```yaml
---
id: T103                     # unikalne, zgodne z nazwą pliku
title: Indeks etykiet i splitów
epic: data                   # foundation | data | training | quality | extended | reliability | product | deploy | final
owner: A                     # A | B | C (role z AGENTS.md)
reviewer: B
week: 2                      # planowany tydzień (1–14)
size: M                      # S | M | L
level: MVP                   # MVP | Core | Extended
gate: G1                     # G1–G6 lub none
experiment: E00              # E00–E11 lub none
depends_on: [T101, T102]
status: todo                 # todo | in_progress | review | done | blocked | dropped
---
```

## 3. Statusy, rozmiary, poziomy

- **Statusy:** `todo` → `in_progress` → `review` → `done`; `blocked` (z opisem przyczyny w karcie), `dropped` (świadomie porzucone, z uzasadnieniem).
- **Rozmiary:** S — do pół dnia, M — 1–2 dni, L — 3+ dni (agent zaczyna od planu do akceptacji; rozważ podział).
- **Poziomy:** MVP i Core są obowiązkowe; Extended realizujemy dopiero po ustabilizowaniu Core (specyfikacja §3.2).
- Status zmieniamy w front matter karty (`python scripts/tasks.py set-status T103 in_progress`) w tym samym PR co kod.

## 4. Proces pracy

1. **Wybór:** `python scripts/tasks.py next --owner A` pokazuje zadania, których zależności są `done`.
2. **Start:** gałąź `t103-label-index`, status `in_progress`.
3. **Agent:** przekaż mu prompt z §6 (lub w Claude Code: `/task T103`). Dla rozmiaru L najpierw zatwierdź plan.
4. **Kontrola człowieka:** przejrzyj diff względem karty; uruchom komendy z sekcji „Weryfikacja”.
5. **PR:** szablon `.github/pull_request_template.md`, status `review`; recenzent (pole `reviewer`) sprawdza kartę i `AGENTS.md` §2 (może użyć promptu recenzji z §6).
6. **Merge:** po akceptacji i zielonym CI — status `done`, `python scripts/tasks.py backlog` odświeża `tasks/BACKLOG.md`.

## 5. Bramki jakościowe G1–G6

Bramka jest zaliczona, gdy wszystkie zadania z danym `gate` mają status `done` **i** spełniony jest warunek poniżej.
Przegląd bramki robi cały zespół (15 minut, notatka w PR zamykającym bramkę).

| Bramka | Warunek przejścia (specyfikacja §12.1) | Tydzień |
|---|---|---|
| G1 — Data | split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany | 3 |
| G2 — Baseline | model uczy się sensownego sygnału; metryki > losowe; pipeline MLflow działa (doprecyzowanie: macro AUROC val ≥ 0,80, E02) | 3–4 |
| G3 — Core model | ResNet1D stabilny na ≥ 3 runach; brak regresji pipeline'u danych | 5 |
| G4 — Reliability | kalibracja i abstention ocenione; quality gate nie degraduje wyników bez kontroli | 11 |
| G5 — Product | API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa | 13 |
| G6 — Final | konfiguracja zamrożona przed foldem 10; karta modelu i wyniki reprodukowalne | 14 |

## 6. Prompty dla agentów

**Implementacja** (dowolne narzędzie; w Claude Code zamiast tego `/task T###`):

```text
Realizujesz zadanie {ID} w repozytorium CardioAI.
1. Przeczytaj AGENTS.md w całości, potem tasks/{ID}-*.md i sekcje dokumentów z „Kontekst”.
2. Sprawdź zależności: python scripts/tasks.py show {ID}. Jeśli któraś nie jest done — przerwij i napisz, czego brakuje.
3. Przedstaw plan: pliki, publiczne interfejsy, testy. (Rozmiar L: zaczekaj na moją akceptację.)
4. Zaimplementuj wyłącznie „Zakres”. Interfejsy oznaczone jako wiążące odwzoruj dokładnie.
5. Dodaj testy z sekcji „Testy”, uruchom komendy z „Weryfikacja” i bramkę z AGENTS.md §7.
6. Ustaw status review: python scripts/tasks.py set-status {ID} review.
7. Raport po polsku: zmienione pliki, wyniki testów, odhaczone kryteria akceptacji, odstępstwa, pytania.
```

**Recenzja** (w Claude Code: `/review-task T###`):

```text
Zrecenzuj zmiany z git diff main...HEAD względem karty tasks/{ID}-*.md i AGENTS.md. Niczego nie poprawiaj.
Dla każdego kryterium akceptacji i każdej reguły z AGENTS.md §2 podaj OK / UWAGA / BŁĄD z plikiem i linią.
Uruchom lint-imports i testy szybkie. Zakończ werdyktem: gotowe do merge / wymaga poprawek (lista).
```

**Tylko plan** (dla zadań L albo przy niepewności):

```text
Przeczytaj AGENTS.md i tasks/{ID}-*.md. Nie zmieniaj plików. Przygotuj plan implementacji: kolejność kroków,
pliki, sygnatury, testy, ryzyka i pytania do zespołu. Wskaż miejsca, gdzie karta lub docs/ są niejednoznaczne.
```

## 7. Narzędzie `scripts/tasks.py`

Działa na samej bibliotece standardowej (`python scripts/tasks.py …` albo `uv run python scripts/tasks.py …`).

| Komenda | Działanie |
|---|---|
| `check` | waliduje front matter, unikalność ID, zależności (istnienie, brak cykli), odwołania `docs/… §N` |
| `backlog` | generuje `tasks/BACKLOG.md` (tabela, plan tygodniowy, ścieżka krytyczna, graf) |
| `next [--owner A]` | zadania `todo`, których wszystkie zależności są `done` |
| `show T103` | ścieżka karty, status i statusy zależności |
| `set-status T103 review` | zmienia `status` w front matter |
| `graph` | graf zależności w Mermaid |
| `issues [--repo org/repo]` | wypisuje polecenia `gh issue create` dla kart (nic nie wykonuje) |

## 8. Eksport do GitHub Issues (opcjonalnie)

`python scripts/tasks.py issues --repo <org>/<repo> > create_issues.sh`, przejrzyj plik, uruchom go przy zalogowanym `gh`.
Karty w repo pozostają źródłem prawdy; issue służy do dyskusji i przypisań.

## 9. Plan i zależności

Pełna lista zadań, plan tygodniowy dla A/B/C, ścieżka krytyczna i graf zależności: `tasks/BACKLOG.md`.
