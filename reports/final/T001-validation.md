# T001 — wynik weryfikacji

## Zadanie

Karta: `tasks/T001-repo-scaffold.md`. Status: `review`.

Tryb przekazania: niezacommitowane zmiany na lokalnej gałęzi `T001`.

## Co zmieniono

- Instalowalny pakiet `cardioai` 0.1.0 i `cardioai_api`, budowane przez hatchling dla Pythona 3.11–3.12.
- Zależności bazowe, extras `cpu`, `cuda`, `api`, `xai`, `onnx`, `lgbm`, `tracking`, `all` oraz grupa `dev`.
  `cpu` i `cuda` wykluczają się; CUDA korzysta z `cu126`, macOS z PyPI/MPS. Lockfile wygenerował uv.
- Szkielety modułów, stałe domenowe i funkcje `n_samples`, `split_of_fold`, `get_logger`, `setup_logging`.
- Ruff, strict mypy, pytest, 11 kontraktów import-linter i pre-commit z limitem plików 1000 KiB.
- Ustawienia końców linii, edytora, ignorowania artefaktów i komplet 15 zmiennych w `.env.example`.
- README, instrukcje CUDA i decyzja D-005; 22 testy importów, stałych, foldów i logowania.
- Audyt przenośności: 20 testów ładowania zależności natywnych i sześć testów wheels;
  łącznie 48 testów. Dodano `required-environments` i wygenerowano ponownie `uv.lock`.
- Naprawiono brak w instrukcji instalacji: LightGBM wymaga systemowego OpenMP. Na Macu
  zainstalowano `libomp` 23.1.4; w testowanych kontenerach Linux zainstalowano `libgomp1`.

Istniejące `scripts/tasks.py` i `scripts/make_issues.py` wymagały dostosowania do włączonego lintu:
formatowanie, nowy zapis adnotacji, usunięcie nieużywanych nazw i równoważny zapis formatowania tekstu.
Porównano wyniki przed i po zmianie na tych samych kartach i dokumentach: backlog oraz wygenerowany
skrypt wszystkich 55 issues są identyczne bajt w bajt. Osadzone szablony shell zachowują oryginalne linie
(lokalne `noqa: E501`). Ruff sprawdza i formatuje pliki Pythona; nie przepisuje przykładów w Markdown.

## Jak przetestowano

Środowiska: macOS ARM64 oraz Debian 12 w Dockerze (ARM64 i emulowane x86_64),
Python 3.11.18 i 3.12.16, uv 0.13.6. PyTorch: macOS 2.15.0, Linux 2.15.0+cpu.
Cache narzędzi i dodatkowe środowiska weryfikacyjne umieszczono w katalogu tymczasowym.

```text
uv sync --extra cpu --extra all
  OK: zainstalowano pakiet i wszystkie extras funkcjonalne.
uv sync --locked --extra cpu
  OK: nowe, puste środowisko, bez zmiany lockfile (użyto istniejącego cache).
uv run pytest -q
  48 passed, bez pominięć.
uv run pytest -m "not requires_data and not slow and not gpu"
  28 passed, 20 deselected (importy zależności oznaczone slow).
uv run ruff check .
  All checks passed!
uv run ruff format --check .
  18 files already formatted.
uv run lint-imports
  Contracts: 11 kept, 0 broken.
uv run mypy src
  Success: no issues found in 12 source files.
uv run pre-commit run --all-files
  Wszystkie hooki przechodzą.
uv run pre-commit run --files <wszystkie pliki śledzone i nowe>
  Wszystkie hooki przechodzą również dla plików niezacommitowanych; indeks Git bez zmian.
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

## Audyt platform (2026-11-10)

| Platforma wykonania | Python | Instalacja `cpu` + `all` | `pytest -q` | Lint / format / importy / mypy | Budowa / import wheel |
|---|---|---|---|---|---|
| macOS ARM64, natywnie | 3.11.18 | OK | 48 passed | OK | OK |
| macOS ARM64, natywnie | 3.12.16 | OK | 48 passed | OK | OK |
| Linux ARM64, Docker | 3.11.18 | OK | 48 passed | OK | OK |
| Linux ARM64, Docker | 3.12.16 | OK | 48 passed | OK | OK |
| Linux x86_64, Docker z emulacją na Macu | 3.11.18 | OK | 48 passed | OK | OK |
| Linux x86_64, Docker z emulacją na Macu | 3.12.16 | OK | 48 passed | OK | OK |

MPS jest dostępne (`True`) na Macu w obu wersjach Pythona. Linuxowe wheels PyTorch mają wariant
CPU; sprawdzono również obliczenie macierzowe float32. Kontenery uruchomiono bez GPU,
na kopii źródeł; środowisko i cache były wewnątrz kontenera. Nie dodano produkcyjnych Dockerfile
ani workflow CI. Obrazy audytu: `python:3.11-slim-bookworm` i `python:3.12-slim-bookworm`.

Dodatkowo sprawdzono **12 kombinacji wheels**: obie wersje Pythona × macOS ARM64/CPU,
Linux ARM64/CPU, Linux x86_64/CPU i CUDA, Windows x86_64/CPU i CUDA. Wszystkie przeszły
`uv sync --locked --offline --dry-run --no-build --no-install-project --python <wersja>
--python-platform <platforma> --extra <cpu|cuda> --extra all`. W kontroli macOS użyto
`MACOSX_DEPLOYMENT_TARGET=14.0`. Windows wybrał `torch 2.15.0+cpu` lub `2.14.1+cu126`.

Test importu LightGBM najpierw ujawnił brak `libomp.dylib`, pomimo pomyślnego `uv sync`.
Po instalacji OpenMP wszystkie 20 importów zależności przechodzi. Jest to test regresyjny
braku wykrytego podczas audytu. Wymagania systemowe są opisane w `docs/environment.md` §2.
Zewnętrzna biblioteka WFDB zgłasza dwa ostrzeżenia o przestarzałym użyciu pandas; nie powodują
one błędów. Starsze logi audytu 3.12 zawierają też ostrzeżenie aliasu `multipart`, który w teście
zastąpiono bieżącym importem `python_multipart`.

## Kryteria akceptacji

| Kryterium | Wynik |
|---|---|
| Instalacja macOS/CPU + all i MPS | OK dla Pythona 3.11 i 3.12, MPS `True` poza sandboxem |
| Instalacja Linux/CPU + all | OK w czterech rzeczywistych uruchomieniach: ARM64/x86_64 × Python 3.11/3.12 |
| Instalacja Windows/RTX 2060 + CUDA + all | Dobór wheels OK w dry-run; sterownik i wykonanie GPU pozostają do potwierdzenia |
| Lockfile i czysta instalacja `--locked --extra cpu` | OK na macOS |
| pytest, ruff, format, import-linter | OK |
| Hook rozmiaru > 1000 KiB | OK, potwierdzony testem odrzucenia |
| gitignore i wyjątki raportów | OK |
| gitattributes LF / binary | OK |
| Komplet zmiennych `.env.example` | OK |
| D-005: CUDA i wymaganie sterownika | OK, CUDA 12.6; Windows ≥ 560.76 / Linux ≥ 560.28.03 |

Indeks CUDA zawiera wheels Windows dla `cp311` i `cp312`. Kontrola wheels Windows potwierdza
dobór pakietów; nie potwierdza ładowania DLL, wersji sterownika ani dostępności rzeczywistego GPU.

## Kontrakty

- [x] Brak zmian wiążących kontraktów danych, konfiguracji, checkpointu, bundla i API.
- [x] Wybór wariantu CUDA przewidziany przez T001 zapisano w D-005 i `docs/environment.md`.

## Definition of Done (`AGENTS.md` §7)

- [ ] Wszystkie kryteria akceptacji: pozostaje test wykonania Windows/RTX 2060.
- [x] Ruff, format, import-linter, mypy i szybkie testy przechodzą.
- [x] Kod działa na CPU; brak `.cuda()` i float64 w tensorach implementacji.
- [x] Typy i angielskie docstringi w publicznych interfejsach.
- [x] Brak danych, checkpointów i sekretów w zmianach.
- [x] Dokumentacja zaktualizowana.
- [x] Status karty: `review`.
- [ ] Akceptacja drugiej osoby z zespołu.

## Odstępstwa od karty i otwarte pytania

- **Nie można potwierdzić e2e Windows/CUDA na samym Macu.** Właściciel laptopa z Windows/RTX
  dołącza wynik `nvidia-smi`, instalacji, `uv run pytest -q` oraz `torch.cuda.is_available()`.
  Gotowa procedura dla obu wersji Pythona i wariantu CPU jest w `docs/environment.md` §6.
  Do tego czasu kryterium Windows pozostaje nieodhaczone, a karta ma status `review`.
- Uzgodniony zakres architektur: macOS ARM64, Windows x86_64, Linux x86_64/ARM64.
  Wynik dotyczy szkieletu T001; modele i pipeline treningowy powstają w kolejnych kartach.
- Marker platformy dodano także do źródła CUDA zgodnie z przewodnikiem uv: macOS pobiera PyTorch z PyPI.
- Dostosowanie dwóch istniejących skryptów było konieczne do spełnienia repozytoryjnej bramki lintu;
  ich generowane wyniki pozostały identyczne.
- CI powstaje w T005, poza zakresem T001. Nie dodano workflow i nie deklarujemy zielonego CI.
- Nie pobierano danych PTB-XL ani nie odblokowywano foldu 10.

Źródła wyboru indeksów i sterownika: [uv / PyTorch](https://docs.astral.sh/uv/guides/integration/pytorch/),
[wheels cu126](https://download.pytorch.org/whl/cu126/torch/),
[NVIDIA CUDA 12.6](https://docs.nvidia.com/cuda/archive/12.6.0/cuda-toolkit-release-notes/index.html#cuda-driver),
[wymagania instalacji LightGBM](https://lightgbm.readthedocs.io/en/stable/Installation-Guide.html),
[wymagane środowiska uv](https://docs.astral.sh/uv/concepts/resolution/#required-environments).
