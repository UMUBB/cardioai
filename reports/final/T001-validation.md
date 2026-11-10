# T001 — wynik weryfikacji i opis PR

## Zadanie

Karta: `tasks/T001-repo-scaffold.md`. Status: `review`.

## Co zmieniono

- Instalowalny pakiet `cardioai` 0.1.0 i `cardioai_api`, budowane przez hatchling dla Pythona 3.11–3.12.
- Zależności bazowe, extras `cpu`, `cuda`, `api`, `xai`, `onnx`, `lgbm`, `tracking`, `all` oraz grupa `dev`.
  `cpu` i `cuda` wykluczają się; CUDA korzysta z `cu126`, macOS z PyPI/MPS. Lockfile wygenerował uv.
- Szkielety modułów, stałe domenowe i funkcje `n_samples`, `split_of_fold`, `get_logger`, `setup_logging`.
- Ruff, strict mypy, pytest, 11 kontraktów import-linter i pre-commit z limitem plików 1000 KiB.
- Ustawienia końców linii, edytora, ignorowania artefaktów i komplet 15 zmiennych w `.env.example`.
- README, instrukcje CUDA i decyzja D-005; 22 testy importów, stałych, foldów i logowania.

Istniejące `scripts/tasks.py` i `scripts/make_issues.py` wymagały dostosowania do włączonego lintu:
formatowanie, nowy zapis adnotacji, usunięcie nieużywanych nazw i równoważny zapis formatowania tekstu.
Porównano wyniki przed i po zmianie na tych samych kartach i dokumentach: backlog oraz wygenerowany
skrypt wszystkich 55 issues są identyczne bajt w bajt. Osadzone szablony shell zachowują oryginalne linie
(lokalne `noqa: E501`). Ruff sprawdza i formatuje pliki Pythona; nie przepisuje przykładów w Markdown.

## Jak przetestowano

Środowisko: macOS ARM64, Python 3.12.16, uv 0.13.6, PyTorch 2.15.0.
Cache narzędzi i dodatkowe środowiska weryfikacyjne umieszczono w katalogu tymczasowym.

```text
uv sync --extra cpu --extra all
  OK: zainstalowano pakiet i wszystkie extras funkcjonalne.
uv sync --locked --extra cpu
  OK: nowe, puste środowisko, bez zmiany lockfile (użyto istniejącego cache).
uv run pytest -q
  22 passed.
uv run pytest -m "not requires_data and not slow and not gpu"
  22 passed.
uv run ruff check .
  All checks passed!
uv run ruff format --check .
  17 files already formatted.
uv run lint-imports
  Contracts: 11 kept, 0 broken.
uv run mypy src
  Success: no issues found in 12 source files.
uv run pre-commit run --all-files
  Wszystkie hooki przechodzą.
python3 scripts/tasks.py check
  55 task cards, 0 errors, 0 warnings.
git diff --check
  Bez błędów.
```

Dodatkowe sprawdzenia:

- `uv build`: sdist i wheel zbudowane poprawnie. Wheel zainstalowany w oddzielnym venv;
  oba pakiety oraz funkcje stałych importują się z `site-packages` poza katalogiem repozytorium.
- Osobna instalacja bazowa `uv sync --locked --no-dev` działa bez `torch` i bez `mlflow`.
  Wybór `cpu` wraz z `cuda` kończy się oczekiwanym błędem konfliktu extras.
- Siedem prób w kopii pakietów potwierdza, że import-linter odrzuca bezpośrednie importy API → data,
  inference → MLflow, training → reliability, models → data (także podmoduł) i tracking → inference
  poza adapterem. Przepuszcza API → inference → data oraz wyjątek tracking.pyfunc → inference → data.
- Hook rozmiaru przetestowany na nowych, dodanych do indeksu plikach w tymczasowym repozytorium:
  1000 KiB przechodzi, 1000 KiB + 1 bajt jest odrzucany z komunikatem `exceeds 1000 KB`.
- `.env.example` odpowiada wszystkim 15 zmiennym z dokumentacji. Sprawdzono 27 ścieżek ignorowanych
  i wyjątków, LF dla tekstu oraz osiem rozszerzeń binarnych.
- Mnożenie macierzy float32 na CPU działa. Poza sandboxem:
  `torch.backends.mps.is_built() == True`, `torch.backends.mps.is_available() == True`.
  W sandboxie dostępność MPS wynosi `False` z powodu ograniczonego dostępu do urządzenia.

## Kryteria akceptacji

| Kryterium | Wynik |
|---|---|
| Instalacja macOS/CPU + all i MPS | OK, MPS `True` poza sandboxem |
| Instalacja Linux/CPU + all | Dobór wheels OK w dry-run; wykonanie na Linuksie pozostaje do potwierdzenia |
| Instalacja Windows/RTX 2060 + CUDA + all | Dobór wheels OK w dry-run; sterownik i wykonanie GPU pozostają do potwierdzenia |
| Lockfile i czysta instalacja `--locked --extra cpu` | OK na macOS |
| pytest, ruff, format, import-linter | OK |
| Hook rozmiaru > 1000 KiB | OK, potwierdzony testem odrzucenia |
| gitignore i wyjątki raportów | OK |
| gitattributes LF / binary | OK |
| Komplet zmiennych `.env.example` | OK |
| D-005: CUDA i wymaganie sterownika | OK, CUDA 12.6; Windows ≥ 560.76 / Linux ≥ 560.28.03 |

Sprawdzono `uv sync --locked --extra cpu --extra all --python-platform x86_64-unknown-linux-gnu --dry-run`
oraz `uv sync --locked --extra cuda --extra all --python-platform x86_64-pc-windows-msvc --dry-run`.
Są to kontrole doboru zależności z lockfile; nie potwierdzają uruchomienia bibliotek na tych systemach.
Indeks CUDA zawiera wheels Windows dla `cp311` i `cp312`.

## Kontrakty

- [x] Brak zmian wiążących kontraktów danych, konfiguracji, checkpointu, bundla i API.
- [x] Wybór wariantu CUDA przewidziany przez T001 zapisano w D-005 i `docs/environment.md`.

## Definition of Done (`AGENTS.md` §7)

- [ ] Wszystkie kryteria akceptacji: pozostają testy wykonania Linux i Windows/RTX.
- [x] Ruff, format, import-linter, mypy i szybkie testy przechodzą.
- [x] Kod działa na CPU; brak `.cuda()` i float64 w tensorach implementacji.
- [x] Typy i angielskie docstringi w publicznych interfejsach.
- [x] Brak danych, checkpointów i sekretów w zmianach.
- [x] Dokumentacja zaktualizowana.
- [x] Status karty: `review`.
- [ ] Akceptacja drugiej osoby z zespołu.

## Odstępstwa od karty i otwarte pytania

- Rzeczywiste wykonanie na Linux i Windows/RTX 2060 wymaga tych maszyn; nie deklarujemy
  nieprzeprowadzonych testów. Właściciel laptopa dołącza wynik `nvidia-smi`, instalacji oraz
  `torch.cuda.is_available()`. Pozostała część kryterium macOS została sprawdzona.
- Marker platformy dodano także do źródła CUDA zgodnie z przewodnikiem uv: macOS pobiera PyTorch z PyPI.
- Dostosowanie dwóch istniejących skryptów było konieczne do spełnienia repozytoryjnej bramki lintu;
  ich generowane wyniki pozostały identyczne.
- CI powstaje w T005, poza zakresem T001. Nie dodano workflow i nie deklarujemy zielonego CI.
- Nie pobierano danych PTB-XL ani nie odblokowywano foldu 10.

Źródła wyboru indeksów i sterownika: [uv / PyTorch](https://docs.astral.sh/uv/guides/integration/pytorch/),
[wheels cu126](https://download.pytorch.org/whl/cu126/torch/),
[NVIDIA CUDA 12.6](https://docs.nvidia.com/cuda/archive/12.6.0/cuda-toolkit-release-notes/index.html#cuda-driver).
