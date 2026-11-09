# AGENTS.md — CardioAI

Instrukcje dla agentów kodujących (Codex, Claude Code, Cursor, Copilot, Gemini) i dla ludzi w zespole.
Ten plik jest **jedynym źródłem zasad pracy** w repozytorium. Kontrakty techniczne są w `docs/`, zadania w `tasks/`.
Czytaj go w całości przed każdym zadaniem.

## 1. Projekt w skrócie

- **CardioAI** — system ML do analizy 12-odprowadzeniowego EKG (10 s) na zbiorze **PTB-XL 1.0.3** (PhysioNet, licencja CC BY 4.0).
- **Zadanie główne:** klasyfikacja wieloetykietowa 5 superklas `NORM, MI, STTC, CD, HYP` (5 logitów + sigmoid, `BCEWithLogitsLoss`).
- **Elementy systemu:** dane → modele 1D (CNN, ResNet1D, Transformer) → kalibracja, quality gate, abstention, XAI, robustness → bundle inferencyjny → FastAPI → React.
- **Kontekst:** projekt akademicki (Uniwersytet Bielsko-Bialski, przedmiot Uczenie maszynowe), 3 osoby, 14 tygodni. Domyślnie 100 Hz.
- **To nie jest wyrób medyczny.** System nie służy do diagnozowania pacjentów.
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`. Mapa dokumentacji: `docs/README.md`.

## 2. Zasady nienaruszalne

Złamanie którejkolwiek reguły oznacza PR do poprawy, niezależnie od jakości reszty kodu.

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany.** Sygnał i predykcje dla foldu 10 są dostępne wyłącznie przez `cardioai.data.test_lock` (odblokowanie tylko w T801). Liczności etykiet z indeksu są dozwolone. Nie „sprawdzaj szybko” na teście. Wybór modelu, progi, kalibracja, robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train:** normalizacja, `pos_weight`, standaryzacja metadanych. Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W trybie ewaluacji i w inferencji pipeline jest deterministyczny.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, przenoszenie przez `.to(device)`. Zakaz `.cuda()`. Zakaz `torch.float64` w tensorach (MPS go nie obsługuje). AMP to flaga w configu, nie wymóg.
6. **Stałe tylko z `cardioai.constants`:** kolejność klas (`SUPERCLASSES`), odprowadzeń (`LEADS`), etykiet jakości (`QUALITY_LABELS`), foldów (`SPLIT_FOLDS`). Nigdy literałów typu `["NORM", "MI", ...]` ani indeksów kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji. API nie ma własnej kopii.
8. **Dane i artefakty poza gitem:** `data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`. Jedyny wyjątek: małe rekordy demo w `api/demo/` (T605).
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym przekazuj `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie.** Zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja dokumentu w `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli zadanie tego wymaga, a karta tego nie przewiduje — **zatrzymaj się i zapytaj**.
11. **Brak twierdzeń klinicznych.** XAI opisujemy jako atrybucję (wrażliwość modelu), nie jako wyjaśnienie przyczynowe. UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 3. Mapa repozytorium

| Ścieżka | Zawartość |
|---|---|
| `src/cardioai/constants.py` | stałe domenowe: klasy, odprowadzenia, foldy, wersja zbioru |
| `src/cardioai/config/` | schemat configu (Pydantic), ładowanie YAML (`extends`, `--set`) |
| `src/cardioai/utils/` | device, seed, logging, git, informacje o środowisku |
| `src/cardioai/tracking/` | MLflow: start runu, tagi, parametry, podsumowania runów |
| `src/cardioai/data/` | pobieranie, indeks etykiet, WFDB, Dataset/DataLoader, cache, normalizacja, preprocessing, augmentacje, korupcje, metadane, blokada testu |
| `src/cardioai/models/` | interfejs `ECGModel`, rejestr, CNN, ResNet1D, Transformer, głowy, fuzja metadanych |
| `src/cardioai/training/` | `Trainer`, straty, optymalizatory i schedulery, checkpointy |
| `src/cardioai/evaluation/` | metryki, progi, predykcje, raporty, bootstrap |
| `src/cardioai/reliability/` | kalibracja, quality gate, abstention, XAI, robustness |
| `src/cardioai/inference/` | typy wyników, bundle, parsowanie i walidacja wejścia, `Predictor`, mock |
| `api/cardioai_api/` | FastAPI (`/v1/...`), schematy odpowiedzi, `api/openapi.json`, `api/demo/` |
| `web/` | React + TypeScript + Plotly |
| `scripts/` | cienkie CLI (argparse) wywołujące `src/`; bez logiki biznesowej |
| `configs/` | YAML: `base.yaml`, `data/`, `model/`, `experiment/`, `robustness/` |
| `tests/` | `unit/`, `data/` (wymaga PTB-XL), `integration/`, `api/`, `fixtures/` |
| `docs/` | kontrakty i dokumentacja — zacznij od `docs/README.md` |
| `tasks/` | karty zadań `T###-*.md`, `BACKLOG.md` (generowany), `README.md` |

### Dozwolone zależności między modułami (pilnuje `lint-imports`)

| Moduł | Może importować | Nie może importować |
|---|---|---|
| `constants`, `utils` | bibliotek zewnętrznych; `utils` → `constants` | reszty projektu |
| `config` | `constants`, `utils` | reszty projektu |
| `tracking` | `config`, `utils`, `constants`; `inference` tylko w `tracking/pyfunc.py` (T702) | `data`, `models`, `training` |
| `data` | `constants`, `utils`, `config` | `models`, `training`, `inference` |
| `models` | `constants`, `utils`, `config` | `data`, `training`, `inference` |
| `evaluation` | `constants`, `utils` | `models`, `training`, `inference` |
| `training` | `data`, `models`, `evaluation`, `tracking`, `config`, `utils`, `constants` | `inference`, `reliability` |
| `reliability` | `data`, `models`, `evaluation`, `utils`, `constants` | `training`, `inference`, `tracking` |
| `inference` | `constants`, `utils`, `config`, `data`, `models`, `evaluation`, `reliability` | `training`, `tracking`, `mlflow` |
| `api/cardioai_api` | `cardioai.inference`, `cardioai.constants` | wszystkiego innego z `cardioai` |

Zakazy z tabeli dotyczą importów **bezpośrednich**; importy pośrednie (np. `cardioai_api` → `cardioai.inference` → `cardioai.data`) są dozwolone (`docs/decisions.md` D-024).

## 4. Komendy

Uruchamiaj z katalogu głównego repo. Komendy działają na Windows, macOS i Linux (szczegóły: `docs/environment.md`).

| Cel | Komenda |
|---|---|
| Instalacja — Mac (MPS), CPU, CI | `uv sync --extra cpu --extra all` |
| Instalacja — laptop z RTX 2060 | `uv sync --extra cuda --extra all` |
| Sprawdzenie środowiska | `uv run python scripts/env_check.py` |
| Lint i format | `uv run ruff check .` oraz `uv run ruff format --check .` |
| Granice modułów | `uv run lint-imports` |
| Typy | `uv run mypy src` |
| Testy szybkie (jak w CI) | `uv run pytest -m "not requires_data and not slow and not gpu"` |
| Testy na prawdziwym PTB-XL | `uv run pytest -m requires_data` |
| Dane | `uv run python scripts/download_ptbxl.py` → `verify_checksums.py` → `build_index.py` |
| Trening | `uv run python scripts/train.py --config configs/experiment/e03_resnet1d.yaml --set seed=1` |
| Ewaluacja (val) | `uv run python scripts/evaluate.py --checkpoint <ścieżka> --split val` |
| API (dev) | `uv run uvicorn cardioai_api.main:app --reload` |
| Frontend (dev) | `cd web && npm ci && npm run dev` |
| Demo całości | `docker compose up --build` |
| Zadania gotowe do wzięcia | `python scripts/tasks.py next` |

## 5. Konwencje kodu

- Python 3.11–3.12, pełne typowanie w `src/`, `from __future__ import annotations`.
- `ruff` (lint + format), długość linii 100. Docstringi w stylu Google.
- **Język:** identyfikatory, docstringi, komentarze, komunikaty logów i commity — po angielsku. `docs/`, `tasks/`, teksty UI — po polsku.
- Kształty tensorów zapisuj w docstringach: `x: [B, 12, T] float32 (mV lub znormalizowane)`.
- Logowanie przez `cardioai.utils.logging.get_logger(__name__)`; żadnych `print` w `src/`.
- Ścieżki przez `pathlib.Path`; żadnych ścieżek na sztywno — config lub zmienne środowiskowe (`docs/environment.md` §4).
- Konfiguracja przekazywana jawnie (obiekty Pydantic); brak stanu globalnego i singletonów.
- Błędy: własne wyjątki z czytelnym komunikatem; zakaz `except Exception: pass` i cichych fallbacków (np. zamiany NaN na 0 bez ostrzeżenia).
- Transformacje sygnału jako funkcje czyste (`np.ndarray` → `np.ndarray`, float32); efekty uboczne tylko w skryptach.
- Windows: skrypty z DataLoaderem mają `if __name__ == "__main__":`; datasety i transformy muszą być picklowalne (bez lambd), memmap otwierany leniwie w workerze.
- Checkpointy zapisujemy tak, by `torch.load(path, weights_only=True)` działało (tylko tensory i typy proste).
- Nowe zależności przez `uv add` (nie edytuj ręcznie `uv.lock`). Zależność > 50 MB lub nowy framework → wpis w `docs/decisions.md`.

## 6. Jak realizować zadanie z `tasks/`

1. Przeczytaj kartę `tasks/T###-*.md` w całości, potem dokumenty z sekcji **Kontekst** (z numerami sekcji `§`).
2. Sprawdź zależności: `python scripts/tasks.py show T###`. Wszystkie z `depends_on` muszą mieć `status: done`. Jeśli nie — zgłoś to, nie implementuj „na zapas”.
3. Przed pisaniem kodu wypisz krótki plan: pliki do utworzenia i zmiany, publiczne interfejsy, testy. Przy rozmiarze **L** poczekaj na akceptację planu.
4. Implementuj **tylko zakres karty**. Sekcja „Poza zakresem” jest wiążąca. Interfejsy oznaczone jako wiążące implementuj dokładnie (nazwy, sygnatury, kształty).
5. Dodaj testy z sekcji **Testy**. Testy jednostkowe działają na syntetycznych danych (fixture mini-PTB-XL), bez sieci i bez GPU.
6. Uruchom bramkę jakości (§7) i wklej wynik do opisu PR.
7. Zaktualizuj dokumentację, jeśli zmieniło się zachowanie, i ustaw w karcie `status: review` (`python scripts/tasks.py set-status T### review`).
8. Raport końcowy: zmienione pliki, wynik testów i lintera, odstępstwa od karty, otwarte pytania.

## 7. Definition of Done (każde zadanie)

- [ ] Wszystkie kryteria akceptacji z karty spełnione.
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702 (od T702 CI traktuje mypy jako blokujący).
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i float64 w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi.
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md`.
- [ ] Status karty zaktualizowany; PR zatwierdzony przez drugą osobę z zespołu.

## 8. Testy

- Markery pytest: `requires_data` (prawdziwy PTB-XL w `CARDIOAI_DATA_ROOT`), `slow` (> 10 s), `gpu` (CUDA lub MPS). CI uruchamia testy bez tych markerów.
- Fixture `mini_ptbxl_root` (T102) generuje w katalogu tymczasowym zbiór o strukturze PTB-XL: ok. 40 rekordów, 10 foldów, pliki WFDB 100 i 500 Hz. Używaj go zamiast prawdziwych danych.
- Testy nie korzystają z internetu (sieć mockujemy), mają ustalone seedy i tolerancje dla porównań float.
- Każdy błąd naprawiony w kodzie dostaje test regresyjny.

## 9. Git i Pull Requesty

- Gałąź: `t103-label-index` (ID zadania + krótki opis). Jeden PR = jedno zadanie.
- Commity: Conventional Commits po angielsku z ID zadania, np. `feat(data): build label index [T103]`.
- PR według `.github/pull_request_template.md`; min. jedna akceptacja innej osoby; CI musi być zielone.
- Recenzent sprawdza zgodność z kartą i z tym plikiem (komenda `/review-task` dla Claude Code).

## 10. Czego nie robić

- Wyników do raportu nie liczymy w notebookach. Notebooki służą tylko do eksploracji, wyniki pochodzą ze `scripts/` i MLflow.
- Nie liczymy statystyk na całym zbiorze i nie robimy `fit` na val/test, poza wyjątkami z §2 pkt 3.
- Nie zmieniamy kolejności klas ani odprowadzeń.
- Nie filtrujemy sygnału domyślnie — filtracja jest wariantem ablacyjnym (`docs/decisions.md` D-011).
- Nie edytujemy ręcznie plików generowanych: `uv.lock`, `api/openapi.json`, `web/src/api/schema.d.ts`, `tasks/BACKLOG.md`.
- Nie refaktoryzujemy poza zakresem zadania i nie dodajemy zależności „na zapas”.
- Nie wpisujemy liczb do `docs/experiments.md` ręcznie — tabele generuje `scripts/summarize_runs.py`.

## 11. Słownik

- **rekord** — jeden 10-sekundowy zapis EKG (`ecg_id`); **pacjent** — `patient_id` (może mieć wiele rekordów).
- **odprowadzenie (lead)** — jeden z 12 kanałów w kolejności `LEADS`.
- **fold** — wartość `strat_fold` (1–10); **split** — `train` / `val` / `test`.
- **superklasa** — jedna z 5 klas diagnostycznych; **SCP statement** — kod z `scp_statements.csv`.
- **bundle** — artefakt inferencyjny: wagi + preprocessing + kalibracja + progi + quality gate + abstention + wersje (`docs/inference_api.md` §2).
- **quality gate** — decyzja `ACCEPT` / `WARN` / `REJECT` o jakości sygnału.
- **abstention** — jawne „nie wiem” przy wysokiej niepewności; status odpowiedzi `ABSTAIN`.
- **coverage** — odsetek przypadków, dla których system wydaje wynik; **selective risk** — błąd na tych przypadkach.
- **G1–G6** — bramki jakościowe projektu; **E00–E11** — eksperymenty; **H1–H6** — hipotezy (`docs/experiments.md`).
