# Dokumentacja CardioAI — mapa

Dokumenty w tym katalogu są **kontraktami**: opisują, jak system ma działać, zanim powstanie kod.
Karty zadań (`tasks/`) odwołują się do nich z numerami sekcji (np. `docs/data_contract.md` §6).
Zasady pracy i reguły nienaruszalne są w `AGENTS.md` w katalogu głównym.

## Dokumenty

| Dokument | Co zawiera | Właściciel |
|---|---|---|
| `architecture.md` | warstwy, pakiety, granice modułów, przepływy treningu i inferencji, statusy | C |
| `data_contract.md` | PTB-XL 1.0.3, etykiety, split, schemat indeksu, sygnał, transformacje, cache, metadane | A |
| `config.md` | schemat configu YAML, `extends`, `--set`, hash configu, nazwy runów | B |
| `modeling.md` | interfejs `ECGModel`, architektury, głowy, straty, checkpoint, protokół treningu | B |
| `evaluation.md` | definicje metryk, progi, pliki predykcji i metryk, blokada testu, bootstrap | B |
| `reliability.md` | jakość sygnału, quality gate, kalibracja, abstention, XAI, robustness | C (jakość: A) |
| `inference_api.md` | bundle, `Predictor`, formaty wejścia, walidacja, endpointy, JSON odpowiedzi, błędy | C |
| `frontend.md` | wymagania UI, komponenty, komunikacja z API, teksty | C |
| `mlops.md` | MLflow, konwencje runów, rejestr modeli, CI/CD, Docker, wydania | C |
| `environment.md` | sprzęt zespołu, instalacja, CUDA/MPS/CPU, zmienne środowiskowe, Windows | C |
| `experiments.md` | hipotezy H1–H6, eksperymenty E00–E11, reguły decyzyjne, tabele wyników | B |
| `decisions.md` | rejestr decyzji projektowych (D-001…) | wszyscy |
| `model_card.md` | szablon karty modelu (wypełniany w T802) | C |
| `spec/` | oryginalna specyfikacja projektu (PDF) | — |

## Kolejność czytania według roli

- **A — Data & Signal ML:** `AGENTS.md` → `data_contract.md` → `architecture.md` → `reliability.md` §2–§4 → `config.md`.
- **B — Model & Experiments:** `AGENTS.md` → `modeling.md` → `evaluation.md` → `config.md` → `experiments.md` → `data_contract.md` §8.
- **C — Reliability & Product:** `AGENTS.md` → `architecture.md` → `inference_api.md` → `reliability.md` → `frontend.md` → `mlops.md`.
- **Agent kodujący:** `AGENTS.md` → karta zadania → sekcje wskazane w „Kontekst”.

## Źródła prawdy

| Kwestia | Jedyne źródło |
|---|---|
| Kolejność klas, odprowadzeń, etykiet jakości, foldy | `src/cardioai/constants.py` (treść w `data_contract.md` §4, §5, §7, §11) |
| Schemat indeksu i próbki | `data_contract.md` §6, §8 |
| Kolejność transformacji sygnału | `data_contract.md` §8 |
| Klucze configu | `config.md` §4 (kod: `src/cardioai/config/schema.py`) |
| Format checkpointu | `modeling.md` §6 |
| Format bundla | `inference_api.md` §2 |
| JSON API | `inference_api.md` §7 (kod: `api/openapi.json`, generowany) |
| Nazwy metryk i tagów MLflow | `mlops.md` §2–§3 |
| Status zadań | front matter kart `tasks/T###-*.md` (`tasks/BACKLOG.md` jest generowany) |

## Zasady utrzymania dokumentacji

1. Dokument zmieniamy w tym samym PR co kod, którego dotyczy.
2. Zmiana kontraktu (oznaczonego jako „wiążący”) wymaga wpisu w `decisions.md`.
3. Sekcje są numerowane — nie przenumerowuj ich bez aktualizacji odwołań w kartach. `python scripts/tasks.py check` wykrywa zerwane odwołania `§N` tylko wtedy,
   gdy ścieżka pliku (np. `docs/config.md`) stoi w tej samej linii przed `§`; nie sprawdza też aktualności `tasks/BACKLOG.md` (po zmianie front matter uruchom `python scripts/tasks.py backlog`).
4. Liczby z eksperymentów trafiają do `experiments.md` przez `scripts/summarize_runs.py`, nie ręcznie.
