#!/usr/bin/env bash
# =============================================================================
# CardioAI — tworzenie GitHub Issues z kart zadań (tasks/T###-*.md)
#
# PLIK GENEROWANY przez scripts/make_issues.py — nie edytuj go ręcznie.
# Zmień kartę (tasks/T###-*.md) i wygeneruj ponownie:  python3 scripts/make_issues.py
#
# Domyślnie skrypt działa na sucho (nic nie jest wysyłane do GitHuba).
#
# Użycie:
#   bash scripts/create_issues.sh --dump ./issues-preview      # podgląd treści issues jako pliki .md (dry run)
#   bash scripts/create_issues.sh --apply --repo ORG/REPO      # utworzenie etykiet i issues
#
# Opcje:
#   --apply        faktycznie wykonaj polecenia `gh` (wymaga `gh auth login`)
#   --repo ORG/R   repozytorium docelowe (domyślnie bieżące repo wykryte przez `gh repo view`)
#   --only T103,T104  ogranicz do wskazanych zadań
#   --dump DIR     zapisz wyrenderowane treści issues do DIR/T###.md
#   --refresh      nadpisz treść już istniejących issues (domyślnie istniejące są pomijane)
#   --yes          nie pytaj o potwierdzenie przy --apply
#   -h, --help     ta pomoc
#
# Zmienne środowiskowe (opcjonalne): ASSIGNEE_A, ASSIGNEE_B, ASSIGNEE_C — loginy GitHub osób A/B/C,
# SLEEP_S — przerwa między tworzonymi issues (domyślnie 2 s, omija limity GitHuba).
#
# Zachowanie:
#  * issues tworzone są w kolejności zależności, więc „Blokowane przez” zawiera od razu linki #N;
#  * po utworzeniu wszystkich issues treść nowych issues jest odświeżana, żeby „Odblokowuje” też miało linki #N;
#  * skrypt jest idempotentny: issue z tytułem zaczynającym się od „[T###]” już istnieje → pomijane.
# =============================================================================
set -euo pipefail

REPO="${REPO:-}"
APPLY=0
DUMP_DIR=""
ONLY=""
REFRESH=0
ASSUME_YES=0
SLEEP_S="${SLEEP_S:-2}"
ASSIGNEE_A="${ASSIGNEE_A:-}"
ASSIGNEE_B="${ASSIGNEE_B:-}"
ASSIGNEE_C="${ASSIGNEE_C:-}"

usage() { awk '/^# ====/ { n++; next } n == 1 { sub(/^# ?/, ""); print } n == 2 { exit }' "$0"; }
die() { echo "BŁĄD: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --repo) [ $# -ge 2 ] || die "--repo wymaga wartości ORG/REPO"; REPO="$2"; shift ;;
    --only) [ $# -ge 2 ] || die "--only wymaga listy zadań"; ONLY="$2"; shift ;;
    --dump) [ $# -ge 2 ] || die "--dump wymaga katalogu"; DUMP_DIR="$2"; shift ;;
    --refresh) REFRESH=1 ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "nieznany argument: $1 (zobacz --help)" ;;
  esac
  shift
done

if [ "$APPLY" = 1 ]; then
  command -v gh >/dev/null 2>&1 || die "brak GitHub CLI (gh) — https://cli.github.com"
  gh auth status >/dev/null 2>&1 || die "zaloguj się: gh auth login"
  if [ -z "$REPO" ]; then
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" || die "nie wykryto repozytorium — podaj --repo ORG/REPO"
  fi
fi
[ -n "$REPO" ] || REPO="ORG/REPO"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MAP="$WORK/map.txt"        # linie: "T103 17" (zadanie, numer issue)
CREATED="$WORK/created.txt"
SED="$WORK/map.sed"
TABLE="$WORK/table.txt"
: > "$MAP"; : > "$CREATED"

build_sed() {
  local tid num
  {
    echo "s|__REPO__|$REPO|g"
    while read -r tid num; do
      [ -n "${tid:-}" ] && echo "s|{{$tid}}|$tid (#$num)|g"
    done < "$MAP"
    echo 's|{{\(T[0-9][0-9][0-9]\)}}|\1|g'
  } > "$SED"
}

render() { build_sed; "body_$1" | sed -f "$SED"; }
issue_no() { awk -v id="$1" '$1 == id { print $2 }' "$MAP" | tail -n 1; }
selected() { [ -z "$ONLY" ] && return 0; case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
assignee_for() {
  case "$1" in A) echo "$ASSIGNEE_A" ;; B) echo "$ASSIGNEE_B" ;; C) echo "$ASSIGNEE_C" ;; *) echo "" ;; esac
}

write_labels() { cat > "$WORK/labels.txt" <<'__LABELS_EOF__'
epic:data|5319e7|Epik: Dane
epic:deploy|5319e7|Epik: Wdrożenie
epic:extended|5319e7|Epik: Rozszerzenia
epic:final|5319e7|Epik: Finalizacja
epic:foundation|5319e7|Epik: Fundamenty
epic:product|5319e7|Epik: Produkt (API/UI)
epic:quality|5319e7|Epik: Jakość i odporność
epic:reliability|5319e7|Epik: Wiarygodność
epic:training|5319e7|Epik: Modele i trening
exp:E00|bfd4f2|Eksperyment E00 — EDA i sanity checks
exp:E01|bfd4f2|Eksperyment E01 — Baseline klasyczny
exp:E02|bfd4f2|Eksperyment E02 — Mały CNN 1D
exp:E03|bfd4f2|Eksperyment E03 — ResNet1D
exp:E04|bfd4f2|Eksperyment E04 — Nierównowaga klas
exp:E05|bfd4f2|Eksperyment E05 — Multitask z jakością sygnału
exp:E06|bfd4f2|Eksperyment E06 — Lead dropout i robustness
exp:E07|bfd4f2|Eksperyment E07 — Transformer
exp:E08|bfd4f2|Eksperyment E08 — Fuzja metadanych
exp:E09|bfd4f2|Eksperyment E09 — Kalibracja i abstention
exp:E10|bfd4f2|Eksperyment E10 — 100 vs 500 Hz
exp:E11|bfd4f2|Eksperyment E11 — XAI i benchmark wdrożeniowy
gate:G1|006b75|Bramka G1 — Data
gate:G2|006b75|Bramka G2 — Baseline
gate:G3|006b75|Bramka G3 — Core model
gate:G4|006b75|Bramka G4 — Reliability
gate:G5|006b75|Bramka G5 — Product
gate:G6|006b75|Bramka G6 — Final
level:Core|d93f0b|Poziom: Core (obowiązkowe)
level:Extended|fbca04|Poziom: Extended (po ustabilizowaniu Core)
level:MVP|b60205|Poziom: MVP (obowiązkowe)
owner:A|0e8a16|Właściciel A — Data & Signal ML
owner:B|0e8a16|Właściciel B — Model & Experiments
owner:C|0e8a16|Właściciel C — Reliability & Product
size:L|c5def5|Rozmiar L (3+ osobodni)
size:M|c5def5|Rozmiar M (1–2 osobodni)
size:S|c5def5|Rozmiar S (do pół dnia, ok. 0,5 osobodnia)
week:1|ededed|Planowany tydzień 1
week:10|ededed|Planowany tydzień 10
week:11|ededed|Planowany tydzień 11
week:12|ededed|Planowany tydzień 12
week:13|ededed|Planowany tydzień 13
week:14|ededed|Planowany tydzień 14
week:2|ededed|Planowany tydzień 2
week:3|ededed|Planowany tydzień 3
week:4|ededed|Planowany tydzień 4
week:5|ededed|Planowany tydzień 5
week:6|ededed|Planowany tydzień 6
week:7|ededed|Planowany tydzień 7
week:8|ededed|Planowany tydzień 8
week:9|ededed|Planowany tydzień 9
__LABELS_EOF__
}

write_table() { cat > "$TABLE" <<'__TABLE_EOF__'
T001|Szkielet repozytorium, pyproject i narzędzia jakości|epic:foundation,level:MVP,size:M,owner:C,week:1,gate:G1|C
T002|System konfiguracji (YAML + Pydantic, extends, --set, config_hash)|epic:foundation,level:MVP,size:M,owner:B,week:1,gate:G1|B
T003|Device, seed, AMP, git i informacje o środowisku|epic:foundation,level:MVP,size:S,owner:B,week:1,gate:G1|B
T004|MLflow — serwer zespołowy i warstwa trackingu|epic:foundation,level:MVP,size:M,owner:C,week:1,gate:G1|C
T005|CI v1 — lint, granice modułów i testy na każdym PR|epic:foundation,level:MVP,size:S,owner:B,week:1,gate:G1|B
T101|Pobieranie PTB-XL 1.0.3, weryfikacja SHA-256 i manifest|epic:data,level:MVP,size:M,owner:A,week:1,gate:G1|A
T102|Syntetyczny mini-PTB-XL jako fixture testów|epic:data,level:MVP,size:M,owner:A,week:1,gate:G1|A
T103|Indeks etykiet i splitów (parquet + meta)|epic:data,level:MVP,size:M,owner:A,week:2,gate:G1,exp:E00|A
T104|Testy kontraktu danych i ochrona przed przeciekiem|epic:data,level:MVP,size:S,owner:A,week:2,gate:G1,exp:E00|A
T105|Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu|epic:data,level:MVP,size:M,owner:A,week:2,gate:G1|A
T106|Cache sygnałów NPY z dostępem memmap|epic:data,level:MVP,size:S,owner:A,week:3,gate:G1|A
T107|Statystyki normalizacji z train i transformacja Normalize|epic:data,level:MVP,size:S,owner:A,week:3,gate:G1|A
T108|Pipeline preprocessingu, filtry zerofazowe i resampling|epic:data,level:MVP,size:M,owner:A,week:4,gate:G3|A
T109|Augmentacje treningowe z rejestrem i walidacją parametrów|epic:data,level:MVP,size:M,owner:A,week:4,gate:G3,exp:E06|A
T110|EDA i raport danych (E00)|epic:data,level:MVP,size:M,owner:A,week:3,gate:G1,exp:E00|A
T201|Moduł metryk i doboru progów|epic:training,level:MVP,size:M,owner:C,week:2,gate:G2|C
T202|Interfejs modeli, rejestr enkoderów, głowy i narzędzia|epic:training,level:MVP,size:S,owner:B,week:2,gate:G2|B
T203|Baseline klasyczny na cechach sygnałowych (E01)|epic:training,level:MVP,size:M,owner:C,week:3,gate:G2,exp:E01|C
T204|Pętla treningowa, straty, checkpointy i scripts/train.py|epic:training,level:MVP,size:L,owner:B,week:3,gate:G2|B
T205|Płytki CNN 1D i pierwszy run end-to-end (E02)|epic:training,level:MVP,size:S,owner:B,week:3,gate:G2,exp:E02|B
T206|Ewaluacja checkpointu, pliki predykcji i metryk|epic:training,level:MVP,size:M,owner:B,week:4,gate:G2|B
T207|ResNet1D — model główny (E03)|epic:training,level:MVP,size:M,owner:B,week:4,gate:G3,exp:E03|B
T208|Nierównowaga klas — pos_weight, focal loss, progi (E04)|epic:training,level:MVP,size:M,owner:B,week:5,gate:G3,exp:E04|B
T209|Uruchamianie wielu seedów i tabele wyników z MLflow (bramka G3)|epic:training,level:MVP,size:S,owner:B,week:5,gate:G3,exp:E03|B
T301|Słabe etykiety jakości w Dataset i analiza ich wiarygodności|epic:quality,level:Core,size:S,owner:A,week:5,gate:G4,exp:E05|A
T302|Biblioteka korupcji syntetycznych z etykietami jakości|epic:quality,level:Core,size:M,owner:A,week:5,gate:G4,exp:E05|A
T303|Model jakości — głowa multitask i osobny QualityNet (E05)|epic:quality,level:Core,size:M,owner:A,week:6,gate:G4,exp:E05|A
T304|Quality gate ACCEPT/WARN/REJECT z regułami twardymi i progami z val|epic:quality,level:Core,size:M,owner:A,week:6,gate:G4,exp:E05|A
T305|Robustness suite — testy odporności z raportem|epic:quality,level:Core,size:M,owner:B,week:7,gate:G4,exp:E06|B
T306|Eksperyment lead dropout i odporność kanałowa (E06, H3)|epic:quality,level:Core,size:S,owner:B,week:7,gate:G4,exp:E06|B
T401|Transformer czasowy jako model porównawczy (E07)|epic:extended,level:Extended,size:M,owner:B,week:8,exp:E07|B
T402|Fuzja metadanych i analiza podgrup (E08, H2)|epic:extended,level:Extended,size:M,owner:B,week:9,exp:E08|B
T403|Głowy pomocnicze rhythm/form (opcjonalne, E05)|epic:extended,level:Extended,size:M,owner:A,week:9,exp:E05|A
T404|Porównanie 100 Hz vs 500 Hz — jakość a koszt (E10, H5)|epic:extended,level:Extended,size:M,owner:B,week:11,exp:E10|B
T501|Kalibracja prawdopodobieństw i diagramy niezawodności (E09)|epic:reliability,level:Core,size:M,owner:C,week:10,gate:G4,exp:E09|C
T502|Abstention i krzywe risk–coverage (E09, H4)|epic:reliability,level:Core,size:M,owner:C,week:10,gate:G4,exp:E09|C
T503|XAI — Integrated Gradients, saliency i agregacje (E11)|epic:reliability,level:Core,size:M,owner:C,week:8,gate:G5,exp:E11|C
T504|Raport niezawodności i przegląd bramki G4|epic:reliability,level:Core,size:S,owner:C,week:11,gate:G4,exp:E09|C
T601|Format bundla inferencyjnego i eksport z checkpointu|epic:product,level:Core,size:M,owner:B,week:6,gate:G5|B
T604|FastAPI v1 z MockPredictorem i typami inferencji (kontrakt-first)|epic:product,level:Core,size:M,owner:C,week:3,gate:G5|C
T602|Parsowanie i walidacja wejścia (WFDB, NPZ, CSV)|epic:product,level:Core,size:M,owner:A,week:8,gate:G5|A
T603|Predictor — pipeline inferencji z bundla|epic:product,level:Core,size:M,owner:C,week:9,gate:G5|C
T605|Integracja API z prawdziwym Predictorem i rekordami demo|epic:product,level:Core,size:M,owner:C,week:12,gate:G5|C
T606|Frontend — szkielet, klient API z OpenAPI, strony i tryb demo|epic:product,level:Core,size:M,owner:C,week:4,gate:G5|C
T607|Przeglądarka 12 odprowadzeń (EcgViewer)|epic:product,level:Core,size:M,owner:C,week:5,gate:G5|C
T608|Panele wyniku — predykcje, jakość, status, informacje o modelu|epic:product,level:Core,size:M,owner:C,week:6,gate:G5|C
T609|Nakładka XAI na sygnał i ranking odprowadzeń|epic:product,level:Core,size:S,owner:C,week:11,gate:G5,exp:E11|C
T610|Integracja quality gate, kalibracji, abstention i XAI w Predictorze|epic:product,level:Core,size:M,owner:C,week:12,gate:G5|C
T701|Obrazy Docker, docker compose i reverse proxy|epic:deploy,level:Core,size:M,owner:C,week:13,gate:G5|C
T702|CI/CD pełne — frontend, obrazy, wydania i promocja modelu|epic:deploy,level:Core,size:M,owner:C,week:13,gate:G5|C
T703|Eksport ONNX i kwantyzacja INT8 (opcjonalne, E11)|epic:deploy,level:Extended,size:M,owner:B,week:13,exp:E11|B
T704|Benchmark wydajności inferencji (E11)|epic:deploy,level:Core,size:S,owner:A,week:13,gate:G5,exp:E11|A
T801|Zamrożenie konfiguracji i jednorazowa ewaluacja na foldzie 10 (G6)|epic:final,level:Core,size:M,owner:B,week:14,gate:G6|B
T802|Karta modelu, README i instrukcja reprodukcji|epic:final,level:Core,size:S,owner:C,week:14,gate:G6|C
T803|Artefakty raportu końcowego — tabele i wykresy|epic:final,level:Core,size:M,owner:A,week:14,gate:G6|A
__TABLE_EOF__
}

# --- treści issues -----------------------------------------------------------------------------------------------
body_T001() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T001-repo-scaffold.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Instalowalny pakiet `cardioai` ze wspólnymi narzędziami (ruff, pytest, mypy, import-linter, pre-commit), który instaluje się
jedną komendą na Windows z CUDA, macOS z MPS i Linuksie bez GPU. Od tego zadania zależą wszystkie pozostałe.

| Pole | Wartość |
|---|---|
| Zadanie | **T001** — Szkielet repozytorium, pyproject i narzędzia jakości |
| Epik | Fundamenty (`foundation`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 1 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G1 — Data |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§3](https://github.com/__REPO__/blob/main/AGENTS.md#3-mapa-repozytorium) (mapa i granice modułów), [§4](https://github.com/__REPO__/blob/main/AGENTS.md#4-komendy) (komendy), [§5](https://github.com/__REPO__/blob/main/AGENTS.md#5-konwencje-kodu) (konwencje), [§8](https://github.com/__REPO__/blob/main/AGENTS.md#8-testy) (testy)
- [`docs/architecture.md`](https://github.com/__REPO__/blob/main/docs/architecture.md) [§3](https://github.com/__REPO__/blob/main/docs/architecture.md#3-pakiety-i-odpowiedzialności), [§4](https://github.com/__REPO__/blob/main/docs/architecture.md#4-granice-modułów)
- [`docs/environment.md`](https://github.com/__REPO__/blob/main/docs/environment.md) [§2](https://github.com/__REPO__/blob/main/docs/environment.md#2-instalacja-wszystkie-systemy) (instalacja), [§6](https://github.com/__REPO__/blob/main/docs/environment.md#6-windows--pułapki) (Windows)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-005](https://github.com/__REPO__/blob/main/docs/decisions.md#d-005--menedżer-środowiska-uv-i-warianty-pytorch) (uv i warianty PyTorch), [D-008](https://github.com/__REPO__/blob/main/docs/decisions.md#d-008--dodatkowe-pakiety-względem-specyfikacji) (pakiety), [D-024](https://github.com/__REPO__/blob/main/docs/decisions.md#d-024--granice-modułów-zakazy-dotyczą-importów-bezpośrednich) (importy bezpośrednie), [D-033](https://github.com/__REPO__/blob/main/docs/decisions.md#d-033--mlflow-w-extra-tracking) (extra `tracking`)

## 🛠️ Szczegóły techniczne

### Zakres

- `pyproject.toml` (backend `hatchling`), pakiety `src/cardioai` i `api/cardioai_api`, `requires-python = ">=3.11,<3.13"`.
- Zależności bazowe: `numpy`, `pandas`, `pyarrow`, `scipy`, `scikit-learn`, `wfdb`, `pyyaml`, `pydantic>=2`, `matplotlib`, `python-dotenv` (bez `mlflow` — patrz extra `tracking`, D-033).
- Extras: `cpu` i `cuda` (PyTorch ≥ 2.6, wzajemnie wykluczające się), `api` (`fastapi`, `uvicorn[standard]`, `python-multipart`, `pydantic-settings`),
  `xai` (`captum`), `onnx` (`onnx`, `onnxruntime`), `lgbm` (`lightgbm`), `tracking` (`mlflow`), `all` = `api` + `xai` + `onnx` + `lgbm` + `tracking`.
- Grupa `dev` (PEP 735): `pytest`, `pytest-cov`, `ruff`, `mypy`, `import-linter`, `pre-commit`, `types-PyYAML`, `pandas-stubs`.
- Szkielet pakietów z `__init__.py`: `config`, `utils`, `tracking`, `data`, `models`, `training`, `evaluation`, `reliability`, `inference` oraz `api/cardioai_api`.
- `src/cardioai/__init__.py` (`__version__ = "0.1.0"`), `src/cardioai/constants.py` (treść niżej), `src/cardioai/utils/logging.py`.
- Konfiguracja: ruff (`line-length = 100`, reguły `E,F,I,B,UP,SIM,N`), mypy (na start `strict` z wyjątkami dla bibliotek bez typów),
  pytest (markery `requires_data`, `slow`, `gpu`; `testpaths = ["tests"]`), kontrakty `import-linter` odwzorowujące tabelę z `AGENTS.md` §3.
- `.gitignore`, `.gitattributes`, `.editorconfig`, `.env.example`, `.pre-commit-config.yaml`, szkielet `README.md`, katalogi `configs/`, `scripts/`, `tests/unit/`, `tests/data/`.
- Test dymny `tests/unit/test_smoke.py`.

### Poza zakresem (wiążące)

- System configu ({{T002}}), device i seed ({{T003}}), MLflow ({{T004}}), workflow CI ({{T005}}), frontend ({{T606}}).

### Pliki

- `pyproject.toml`, `uv.lock` — nowe
- `src/cardioai/__init__.py`, `src/cardioai/constants.py`, `src/cardioai/utils/logging.py` — nowe
- `api/cardioai_api/__init__.py` — nowy
- `.gitignore`, `.gitattributes`, `.editorconfig`, `.env.example`, `.pre-commit-config.yaml`, `README.md` — nowe
- `tests/unit/test_smoke.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
# src/cardioai/constants.py
DATASET_NAME: Final = "ptb-xl"
DATASET_VERSION: Final = "1.0.3"
LEADS: Final[tuple[str, ...]] = ("I", "II", "III", "aVR", "aVL", "aVF", "V1", "V2", "V3", "V4", "V5", "V6")
N_LEADS: Final = 12
SUPERCLASSES: Final[tuple[str, ...]] = ("NORM", "MI", "STTC", "CD", "HYP")
QUALITY_LABELS: Final[tuple[str, ...]] = ("static_noise", "burst_noise", "baseline_drift", "electrode_problem")
SAMPLING_RATES: Final[tuple[int, ...]] = (100, 500)
RECORD_SECONDS: Final = 10
SPLIT_FOLDS: Final[Mapping[str, tuple[int, ...]]] = MappingProxyType(
    {"train": (1, 2, 3, 4, 5, 6, 7, 8), "val": (9,), "test": (10,)})
QUALITY_STATUSES: Final = ("ACCEPT", "WARN", "REJECT")
RESPONSE_STATUSES: Final = ("OK", "ABSTAIN", "REJECTED")

def n_samples(sampling_rate: int) -> int: ...       # sampling_rate * RECORD_SECONDS
def split_of_fold(fold: int) -> str: ...            # ValueError dla fold spoza 1–10

# src/cardioai/utils/logging.py
def get_logger(name: str) -> logging.Logger: ...
def setup_logging(level: str | None = None) -> None: ...   # domyślnie CARDIOAI_LOG_LEVEL lub INFO
```

Wzorzec konfiguracji PyTorch w `pyproject.toml` (zweryfikuj z przewodnikiem uv „Using uv with PyTorch”):

```toml
[tool.uv]
conflicts = [[{ extra = "cpu" }, { extra = "cuda" }]]

[tool.uv.sources]
torch = [
  { index = "pytorch-cpu", extra = "cpu", marker = "sys_platform != 'darwin'" },
  { index = "pytorch-cuda", extra = "cuda" },
]

[[tool.uv.index]]
name = "pytorch-cpu"
url = "https://download.pytorch.org/whl/cpu"
explicit = true

[[tool.uv.index]]
name = "pytorch-cuda"
url = "https://download.pytorch.org/whl/cu126"   # wariant do potwierdzenia (D-005)
explicit = true
```

### Testy do napisania

- `tests/unit/test_smoke.py`: import `cardioai` i `__version__`; `LEADS` ma 12 unikalnych nazw; kolejność `SUPERCLASSES`;
  foldy w `SPLIT_FOLDS` są rozłączne i pokrywają 1–10; `n_samples(100) == 1000`; `split_of_fold(10) == "test"`; `split_of_fold(11)` zgłasza `ValueError`.

### Weryfikacja

```bash
uv sync --extra cpu --extra all
uv run pytest -q
uv run ruff check . && uv run ruff format --check .
uv run lint-imports
uv run pre-commit run --all-files
```

### Wskazówki i pułapki

- `torch` jest tylko w extras — `uv sync` bez extras nie zainstaluje PyTorch; CI i dokumentacja zawsze podają extra.
- `import-linter` potrzebuje `root_packages = ["cardioai", "cardioai_api"]`; kontrakt `forbidden` dla `cardioai_api` (wszystko poza `cardioai.inference`, `cardioai.constants`).
  Zakazy dotyczą importów bezpośrednich (D-024): kontrakty `cardioai_api` i `cardioai.tracking` mają `allow_indirect_imports = true`,
  a wyjątek pyfunc zapisz jako `ignore_imports = ["cardioai.tracking.pyfunc -> cardioai.inference"]`.
- Nie dodawaj `-m` do `addopts` pytest — testy `requires_data` same się pomijają, gdy brak danych ({{T103}}/{{T104}}).
- Na Windows sprawdź, czy indeks CUDA ma wheel dla Twojej wersji Pythona (`cp312-win_amd64`).

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T001-repo-scaffold.md`](https://github.com/__REPO__/blob/main/tasks/T001-repo-scaffold.md)
- Decyzja [D-005](https://github.com/__REPO__/blob/main/docs/decisions.md#d-005--menedżer-środowiska-uv-i-warianty-pytorch) — Menedżer środowiska uv i warianty PyTorch
- Decyzja [D-008](https://github.com/__REPO__/blob/main/docs/decisions.md#d-008--dodatkowe-pakiety-względem-specyfikacji) — Dodatkowe pakiety względem specyfikacji
- Decyzja [D-024](https://github.com/__REPO__/blob/main/docs/decisions.md#d-024--granice-modułów-zakazy-dotyczą-importów-bezpośrednich) — Granice modułów: zakazy dotyczą importów bezpośrednich
- Decyzja [D-033](https://github.com/__REPO__/blob/main/docs/decisions.md#d-033--mlflow-w-extra-tracking) — `mlflow` w extra `tracking`
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] `uv sync --extra cpu --extra all` działa na Linuksie i macOS; na Macu `torch.backends.mps.is_available()` zwraca `True`.
- [ ] `uv sync --extra cuda --extra all` działa na laptopie z RTX 2060 (Windows); `torch.cuda.is_available()` zwraca `True` (wynik wklejony do PR).
- [ ] `uv.lock` jest w repo, a `uv sync --locked --extra cpu` przechodzi w czystym środowisku.
- [ ] `uv run pytest`, `uv run ruff check .`, `uv run ruff format --check .` i `uv run lint-imports` przechodzą.
- [ ] `pre-commit` blokuje plik większy niż 1 MB (`check-added-large-files --maxkb=1000`).
- [ ] `.gitignore` obejmuje: `data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `mlflow.db`, `models/bundles/`, `reports/*` (z wyjątkami `!reports/final/` i `!reports/docs-audit/`),
      `*.pt`, `*.onnx`, `*.npy`, `.env`, `CLAUDE.local.md`, `.venv/`, `node_modules/`, `web/dist/` oraz katalogi cache narzędzi.
- [ ] `.gitattributes`: `* text=auto eol=lf` oraz `binary` dla `*.dat *.npy *.npz *.pt *.onnx *.png *.pdf *.parquet`.
- [ ] `.env.example` zawiera wszystkie zmienne z `docs/environment.md` §4 (z wartościami domyślnymi lub pustymi).
- [ ] Wpis D-005 w `docs/decisions.md` uzupełniony o wybrany wariant CUDA i uzasadnienie (sterownik, dostępność wheels).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T001 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez:** brak — zadanie można zacząć od razu.

**Odblokowuje:**

- {{T002}} — System konfiguracji (YAML + Pydantic, extends, --set, config_hash) (tydzień 1, właściciel B)
- {{T003}} — Device, seed, AMP, git i informacje o środowisku (tydzień 1, właściciel B)
- {{T005}} — CI v1 — lint, granice modułów i testy na każdym PR (tydzień 1, właściciel B)
- {{T101}} — Pobieranie PTB-XL 1.0.3, weryfikacja SHA-256 i manifest (tydzień 1, właściciel A)
- {{T102}} — Syntetyczny mini-PTB-XL jako fixture testów (tydzień 1, właściciel A)
- {{T201}} — Moduł metryk i doboru progów (tydzień 2, właściciel C)
- {{T604}} — FastAPI v1 z MockPredictorem i typami inferencji (kontrakt-first) (tydzień 3, właściciel C)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T001` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t001-repo-scaffold`; status karty `in_progress` (`python3 scripts/tasks.py set-status T001 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(utils): <description> [T001]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T001`.

W Claude Code zadanie realizuje komenda `/task T001`.
__ISSUE_BODY_EOF__
}

body_T002() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T002-config-system.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Każdy run jest opisany jednym walidowanym obiektem `RunConfig`, zbudowanym z plików YAML (`extends`) i nadpisań `--set`,
z deterministycznym `config_hash` do grupowania runów różniących się tylko seedem.

| Pole | Wartość |
|---|---|
| Zadanie | **T002** — System konfiguracji (YAML + Pydantic, extends, --set, config_hash) |
| Epik | Fundamenty (`foundation`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 1 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G1 — Data |
| Eksperyment | — |
| Właściciel | B (Model & Experiments) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/config.md`](https://github.com/__REPO__/blob/main/docs/config.md) [§1–§7](https://github.com/__REPO__/blob/main/docs/config.md#1-zasady) (cały dokument jest kontraktem tego zadania)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§5](https://github.com/__REPO__/blob/main/AGENTS.md#5-konwencje-kodu) (konwencje)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-006](https://github.com/__REPO__/blob/main/docs/decisions.md#d-006--config-yaml--pydantic-bez-hydry), [D-025](https://github.com/__REPO__/blob/main/docs/decisions.md#d-025--pierwszeństwo-źródeł-configu-i-skład-config_hash)

## 🛠️ Szczegóły techniczne

### Zakres

- Modele Pydantic v2 (`extra="forbid"`) dla wszystkich sekcji z `docs/config.md` §4, z wartościami domyślnymi z tej sekcji.
- Ładowanie YAML z listą `extends` (ścieżki względne do pliku), scalanie według §3, wykrywanie cykli.
- Nakładanie zmiennych środowiskowych po scaleniu YAML i przed `--set`: `CARDIOAI_DATA_ROOT → data.root`, `CARDIOAI_DEVICE → training.device`
  (pierwszeństwo: `--set` > zmienna środowiskowa > plik YAML > wartość domyślna; `docs/config.md` §1 pkt 4).
- Parsowanie `--set klucz.podklucz=wartość` (wartość przez `yaml.safe_load`), `add_config_args` dla argparse.
- `config_hash` według §6, `dump_resolved` (YAML), `default_run_name`.
- Configi: `configs/base.yaml`, `configs/data/ptbxl_100.yaml`, `configs/data/ptbxl_500.yaml`, `configs/experiment/e00_smoke.yaml`.

### Poza zakresem (wiążące)

- Walidacja `model.params` i parametrów augmentacji (rejestry w {{T202}} i {{T109}} — tu tylko `dict[str, Any]`).
- Integracja z MLflow ({{T004}}).

### Pliki

- `src/cardioai/config/__init__.py`, `schema.py`, `loader.py` — nowe
- `configs/base.yaml`, `configs/data/ptbxl_100.yaml`, `configs/data/ptbxl_500.yaml`, `configs/experiment/e00_smoke.yaml` — nowe
- `tests/unit/config/test_schema.py`, `tests/unit/config/test_loader.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
class RunConfig(BaseModel):            # sekcje: experiment, seed, data, preprocessing, augmentations,
    ...                                 # quality, model, training, evaluation, tracking, output_dir
class AugmentationSpec(BaseModel):     # name: str, p: float, + dowolne parametry (model_config extra="allow")
    ...

def load_config(path: str | Path, overrides: Sequence[str] = ()) -> RunConfig: ...
def deep_merge(base: dict[str, Any], update: dict[str, Any]) -> dict[str, Any]: ...
def parse_override(item: str) -> tuple[list[str], Any]: ...        # "a.b=1e-3" -> (["a","b"], ...)
def config_hash(cfg: RunConfig) -> str: ...                       # 12 znaków hex
def dump_resolved(cfg: RunConfig, path: Path) -> None: ...
def default_run_name(cfg: RunConfig) -> str: ...                   # docs/config.md §6
def add_config_args(parser: argparse.ArgumentParser) -> None: ...  # --config (wymagany), --set (wielokrotny)
class ConfigError(ValueError): ...
```

### Testy do napisania

- `test_loader.py`: scalanie (słownik, lista, null), kolejność warstw (w tym zmienne środowiskowe: YAML < env < `--set`, przez `monkeypatch.setenv`), `--set` dla int/float/bool/list/null/str, cykl `extends`,
  ścieżki względne `extends` z podkatalogów, stabilność `config_hash` (permutacja kluczy, zmiana seeda → ten sam hash, zmiana `lr` → inny).
- `test_schema.py`: wartości domyślne, `extra="forbid"`, walidacje zakresów, round-trip YAML.

### Weryfikacja

```bash
uv run pytest tests/unit/config -q
uv run python -c "from cardioai.config import load_config; print(load_config('configs/experiment/e00_smoke.yaml'))"
```

### Wskazówki i pułapki

- PyYAML (YAML 1.1) czyta `1e-3` jako **tekst** — w plikach YAML pisz `1.0e-3`; pola typowane Pydantic i tak skonwertują tekst w trybie lax,
  ale `model.params` (słownik) nie — walidacja nastąpi dopiero w `Params` modelu ({{T202}}).
- Hash licz z `model_dump(mode="json")` z posortowanymi kluczami, nie z tekstu YAML.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T002-config-system.md`](https://github.com/__REPO__/blob/main/tasks/T002-config-system.md)
- Decyzja [D-006](https://github.com/__REPO__/blob/main/docs/decisions.md#d-006--config-yaml--pydantic-bez-hydry) — Config: YAML + Pydantic, bez Hydry
- Decyzja [D-025](https://github.com/__REPO__/blob/main/docs/decisions.md#d-025--pierwszeństwo-źródeł-configu-i-skład-config_hash) — Pierwszeństwo źródeł configu i skład `config_hash`
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Wszystkie klucze z `docs/config.md` §4 istnieją z tymi samymi wartościami domyślnymi; `configs/base.yaml` je odzwierciedla.
- [ ] Nieznany klucz → `ConfigError` z pełną ścieżką klucza (np. `training.optimzer`).
- [ ] Scalanie: słowniki rekurencyjnie, listy w całości, `null` nadpisuje; kolejność warstw: `extends` → plik → zmienne środowiskowe → `--set`.
- [ ] `CARDIOAI_DATA_ROOT` i `CARDIOAI_DEVICE` nadpisują `data.root` i `training.device` z YAML, a `--set` nadpisuje zmienną środowiskową.
- [ ] Cykl w `extends` → `ConfigError`; klucz `extends` nie trafia do wyniku.
- [ ] `config_hash` nie zależy od kolejności kluczy ani od pól wyłączonych w §6 (seed, tracking, output_dir, data.root, data.num_workers, data.cache_dir,
      data.batch_size_eval, training.log_every_n_steps, training.device); zmiana `training.amp` zmienia hash.
- [ ] `dump_resolved` → `load_config` daje równy obiekt.
- [ ] `e00_smoke.yaml`: 1 epoka, `batch_size: 8`, `data.cache_dir: null`, `data.num_workers: 0`, `tracking.enabled: false`, model `debug_linear` (implementacja w {{T202}}).
- [ ] Walidacja zakresów: `data.sampling_rate ∈ {100, 500}`, `0 ≤ p ≤ 1` w augmentacjach, `training.epochs ≥ 1`, `preprocessing.notch_hz < sampling_rate/2` (gdy ustawione).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T002 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T001}} — Szkielet repozytorium, pyproject i narzędzia jakości (tydzień 1, właściciel C)

**Odblokowuje:**

- {{T004}} — MLflow — serwer zespołowy i warstwa trackingu (tydzień 1, właściciel C)
- {{T105}} — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu (tydzień 2, właściciel A)
- {{T202}} — Interfejs modeli, rejestr enkoderów, głowy i narzędzia (tydzień 2, właściciel B)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T002` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t002-config-system`; status karty `in_progress` (`python3 scripts/tasks.py set-status T002 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(config): <description> [T002]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T002`.

W Claude Code zadanie realizuje komenda `/task T002`.
__ISSUE_BODY_EOF__
}

body_T003() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T003-device-seed-env.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Jedno miejsce wyboru urządzenia, AMP i seedów, dzięki któremu ten sam kod działa na CPU, CUDA i MPS bez warunków rozsianych po projekcie.

| Pole | Wartość |
|---|---|
| Zadanie | **T003** — Device, seed, AMP, git i informacje o środowisku |
| Epik | Fundamenty (`foundation`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 1 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G1 — Data |
| Eksperyment | — |
| Właściciel | B (Model & Experiments) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§2](https://github.com/__REPO__/blob/main/AGENTS.md#2-zasady-nienaruszalne) pkt 5 i 9 (device, losowość)
- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§8](https://github.com/__REPO__/blob/main/docs/modeling.md#8-amp-urządzenia-determinizm) (AMP, urządzenia, determinizm)
- [`docs/environment.md`](https://github.com/__REPO__/blob/main/docs/environment.md) [§3](https://github.com/__REPO__/blob/main/docs/environment.md#3-specyfika-urządzeń), [§4](https://github.com/__REPO__/blob/main/docs/environment.md#4-zmienne-środowiskowe)

## 🛠️ Szczegóły techniczne

### Zakres

- `get_device` z kolejnością CUDA → MPS → CPU i obsługą `CARDIOAI_DEVICE`.
- `autocast_context` i `make_grad_scaler` (AMP tylko na CUDA, fp16).
- `seed_everything`, `make_rng`; opcjonalny tryb deterministyczny.
- `git_sha`, `git_dirty` (bez zależności od biblioteki GitPython — `subprocess`).
- `collect_env_info`, `load_env` (`.env` przez `python-dotenv`).
- `scripts/env_check.py` — wypisuje JSON z informacjami i wykonuje test mnożenia macierzy na wybranym urządzeniu.

### Poza zakresem (wiążące)

- Tagi MLflow ({{T004}}) — korzystają z funkcji z tego zadania.

### Pliki

- `src/cardioai/utils/device.py`, `seed.py`, `git.py`, `env.py` — nowe
- `scripts/env_check.py` — nowy
- `tests/unit/utils/test_device.py`, `test_seed.py`, `test_git_env.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def get_device(preference: str | None = None) -> torch.device: ...
    # preference to wartość już rozstrzygnięta przez loader configu (T002; D-025) i nie jest łączona ze zmienną środowiskową;
    # None (wywołania bez configu, np. env_check.py) -> CARDIOAI_DEVICE -> "auto"
    # "cuda"/"mps" niedostępne -> DeviceUnavailableError (bez cichego fallbacku)
def autocast_context(device: torch.device, enabled: bool) -> AbstractContextManager[None]: ...
def make_grad_scaler(device: torch.device, enabled: bool) -> torch.amp.GradScaler | None: ...
def seed_everything(seed: int, *, deterministic: bool = False) -> None: ...
def make_rng(*keys: int) -> np.random.Generator: ...        # np.random.default_rng(list(keys))
def git_sha(short: bool = True) -> str: ...                 # "unknown" poza repo
def git_dirty() -> bool | None: ...
def collect_env_info() -> dict[str, str]: ...               # python, torch, cuda, cudnn, device_name, mps, os, host, git
def load_env(path: Path | None = None) -> bool: ...         # True, gdy plik .env wczytany
class DeviceUnavailableError(RuntimeError): ...
```

### Testy do napisania

- `test_device.py`: monkeypatch `torch.cuda.is_available` / `torch.backends.mps.is_available`; zmienna środowiskowa (tylko przy `preference=None`); błędne wartości.
- `test_seed.py`: powtarzalność `make_rng(1, 2, 3)`; różne klucze → różne strumienie.
- `test_git_env.py`: `git_sha` poza repo (tmp) → `"unknown"`; `load_env` na pliku tymczasowym.

### Weryfikacja

```bash
uv run pytest tests/unit/utils -q
uv run python scripts/env_check.py
```

### Wskazówki i pułapki

- `torch.amp.GradScaler("cuda")` zastąpił starsze `torch.cuda.amp.GradScaler` — użyj nowego API.
- Nie używaj `torch.set_default_dtype(torch.float64)` nigdzie w projekcie.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T003-device-seed-env.md`](https://github.com/__REPO__/blob/main/tasks/T003-device-seed-env.md)
- Decyzja [D-025](https://github.com/__REPO__/blob/main/docs/decisions.md#d-025--pierwszeństwo-źródeł-configu-i-skład-config_hash) — Pierwszeństwo źródeł configu i skład `config_hash`
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] `get_device("auto")` na maszynie bez GPU zwraca `cpu`; `get_device(None)` z `CARDIOAI_DEVICE=cpu` wymusza CPU nawet przy dostępnej CUDA.
- [ ] Żądanie `cuda` lub `mps` bez dostępności → `DeviceUnavailableError` z czytelnym komunikatem.
- [ ] `autocast_context` dla CPU i MPS zwraca kontekst pusty; dla CUDA z `enabled=True` — `torch.autocast("cuda", dtype=torch.float16)`.
- [ ] `seed_everything(0)` daje powtarzalne `random`, `numpy` i `torch`; `deterministic=True` ustawia `torch.use_deterministic_algorithms(True, warn_only=True)` i ostrzega o `CUBLAS_WORKSPACE_CONFIG`.
- [ ] `scripts/env_check.py` działa na każdej maszynie zespołu (wynik z każdej w PR lub w komentarzu).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T003 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T001}} — Szkielet repozytorium, pyproject i narzędzia jakości (tydzień 1, właściciel C)

**Odblokowuje:**

- {{T004}} — MLflow — serwer zespołowy i warstwa trackingu (tydzień 1, właściciel C)
- {{T105}} — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu (tydzień 2, właściciel A)
- {{T202}} — Interfejs modeli, rejestr enkoderów, głowy i narzędzia (tydzień 2, właściciel B)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T003` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t003-device-seed-env`; status karty `in_progress` (`python3 scripts/tasks.py set-status T003 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(utils): <description> [T003]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T003`.

W Claude Code zadanie realizuje komenda `/task T003`.
__ISSUE_BODY_EOF__
}

body_T004() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T004-mlflow-tracking.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Trzy maszyny logują do jednego trackera z jednolitymi tagami, parametrami i układem artefaktów, a kod nie zna adresu serwera.

| Pole | Wartość |
|---|---|
| Zadanie | **T004** — MLflow — serwer zespołowy i warstwa trackingu |
| Epik | Fundamenty (`foundation`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 1 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G1 — Data |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§1](https://github.com/__REPO__/blob/main/docs/mlops.md#1-mlflow--serwer-zespołowy) (hosting), [§2](https://github.com/__REPO__/blob/main/docs/mlops.md#2-konwencje-eksperymenty-runy-tagi) (konwencje i tagi), [§3](https://github.com/__REPO__/blob/main/docs/mlops.md#3-parametry-metryki-artefakty) (parametry, metryki, artefakty)
- [`docs/config.md`](https://github.com/__REPO__/blob/main/docs/config.md) [§6](https://github.com/__REPO__/blob/main/docs/config.md#6-hash-configu-i-nazwy-runów) (nazwa runu, `config_hash`)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-007](https://github.com/__REPO__/blob/main/docs/decisions.md#d-007--hosting-serwera-mlflow)

## 🛠️ Szczegóły techniczne

### Zakres

- Funkcje trackingu (niżej); gdy `tracking.enabled = false` lub brak aktywnego runu — wszystkie są no-op.
- Tagi obowiązkowe z `docs/mlops.md` §2, parametry ze spłaszczonego configu, artefakt `config/resolved.yaml` i `env/env_info.json`.
- `docker/mlflow.compose.yaml` — serwer MLflow (SQLite + serwowane artefakty) do uruchomienia na maszynie zespołu.
- Decyzja o hostingu (wariant A lub B z `docs/mlops.md` §1): uzupełnienie D-007 i §1 oraz instrukcja podłączenia w `docs/environment.md` §4.

### Poza zakresem (wiążące)

- Podsumowania i tabele runów ({{T209}}), rejestr modeli ({{T702}}).

### Pliki

- `src/cardioai/tracking/__init__.py`, `mlflow_utils.py` — nowe
- `docker/mlflow.compose.yaml` — nowy
- `docs/mlops.md`, `docs/decisions.md`, `docs/environment.md` — aktualizacja
- `tests/unit/tracking/test_mlflow_utils.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
@contextmanager
def start_run(cfg: RunConfig, *, run_name: str | None = None, extra_tags: Mapping[str, str] | None = None,
              nested: bool = False) -> Iterator[mlflow.ActiveRun | None]: ...
@contextmanager
def resume_run(run_id: str) -> Iterator[mlflow.ActiveRun]: ...
def log_config(cfg: RunConfig) -> None: ...
def log_metrics(metrics: Mapping[str, float], step: int | None = None) -> None: ...   # pomija NaN z ostrzeżeniem
def log_artifact_file(path: Path, artifact_path: str | None = None) -> None: ...
def log_artifact_dir(path: Path, artifact_path: str) -> None: ...
def flatten_config(cfg: RunConfig) -> dict[str, str]: ...
def required_tags(cfg: RunConfig) -> dict[str, str]: ...
```

### Testy do napisania

- `test_mlflow_utils.py` z tymczasowym URI (`tmp_path`): komplet tagów, spłaszczanie, artefakt configu, no-op przy `tracking.enabled=false`,
  pomijanie NaN, `resume_run` dopisuje do istniejącego runu.

### Weryfikacja

```bash
uv run pytest tests/unit/tracking -q
docker compose -f docker/mlflow.compose.yaml up -d
```

### Wskazówki i pułapki

- API MLflow różni się między 2.x i 3.x (np. argumenty `log_model`) — sprawdź wersję z `uv.lock`.
- Ścieżki Windows w URI artefaktów: używaj `Path.as_uri()` albo serwera z `--serve-artifacts`, żeby klient wysyłał artefakty przez HTTP.
- Sekrety (hasła) tylko w `.env`; nigdy w configu ani w tagach.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T004-mlflow-tracking.md`](https://github.com/__REPO__/blob/main/tasks/T004-mlflow-tracking.md)
- Decyzja [D-007](https://github.com/__REPO__/blob/main/docs/decisions.md#d-007--hosting-serwera-mlflow) — Hosting serwera MLflow
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] `start_run` ustawia wszystkie tagi z `docs/mlops.md` §2 (wartości z configu, `git_sha`, `git_dirty`, `device`, `host`), `stage=dev` domyślnie.
- [ ] Nazwa eksperymentu = `tracking.experiment_name` lub `experiment.name`; nazwa runu z `default_run_name`.
- [ ] Parametry spłaszczone (`training.optimizer.lr`); zbyt długie wartości przycięte z ostrzeżeniem.
- [ ] Bez `MLFLOW_TRACKING_URI` logowanie lokalne w katalogu ignorowanym przez git + ostrzeżenie w logu.
- [ ] Serwer z `docker/mlflow.compose.yaml` działa, a każda z trzech maszyn zalogowała run testowy (zrzut listy runów w PR).
- [ ] D-007 ma status „przyjęta” z opisem wariantu, adresu (bez sekretów) i kopii zapasowej.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T004 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T002}} — System konfiguracji (YAML + Pydantic, extends, --set, config_hash) (tydzień 1, właściciel B)
- {{T003}} — Device, seed, AMP, git i informacje o środowisku (tydzień 1, właściciel B)

**Odblokowuje:**

- {{T203}} — Baseline klasyczny na cechach sygnałowych (E01) (tydzień 3, właściciel C)
- {{T204}} — Pętla treningowa, straty, checkpointy i scripts/train.py (tydzień 3, właściciel B)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T004` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t004-mlflow-tracking`; status karty `in_progress` (`python3 scripts/tasks.py set-status T004 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(tracking): <description> [T004]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T004`.

W Claude Code zadanie realizuje komenda `/task T004`.
__ISSUE_BODY_EOF__
}

body_T005() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T005-ci-pipeline-v1.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Każdy PR jest automatycznie sprawdzany tą samą bramką, którą agent uruchamia lokalnie, więc błąd zasad lub granic modułów nie trafi do `main`.

| Pole | Wartość |
|---|---|
| Zadanie | **T005** — CI v1 — lint, granice modułów i testy na każdym PR |
| Epik | Fundamenty (`foundation`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 1 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G1 — Data |
| Eksperyment | — |
| Właściciel | B (Model & Experiments) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§6](https://github.com/__REPO__/blob/main/docs/mlops.md#6-cicd) (CI/CD)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§7](https://github.com/__REPO__/blob/main/AGENTS.md#7-definition-of-done-każde-zadanie) (Definition of Done), [§8](https://github.com/__REPO__/blob/main/AGENTS.md#8-testy) (testy)

## 🛠️ Szczegóły techniczne

### Zakres

- `.github/workflows/ci.yml`: wyzwalacze `pull_request` i `push` do `main`; `ubuntu-latest`; `astral-sh/setup-uv` z cache.
- Kroki: `uv sync --locked --extra cpu --extra all` → `ruff check` → `ruff format --check` → `lint-imports` → `mypy src` (na start `continue-on-error: true`)
  → `pytest -m "not requires_data and not slow and not gpu" --cov=cardioai`.
- `concurrency` z anulowaniem poprzednich przebiegów dla tej samej gałęzi; `timeout-minutes: 15`.
- Krótka instrukcja ochrony gałęzi `main` (wymagany status CI, 1 akceptacja) w opisie PR — ustawia administrator repo.

### Poza zakresem (wiążące)

- Job frontendu, budowa obrazów Docker, sprawdzanie `api/openapi.json`, wydania ({{T702}}).

### Pliki

- `.github/workflows/ci.yml` — nowy

### Testy do napisania

- Brak nowych testów; weryfikacja przez przebieg CI na PR testowym.

### Weryfikacja

```bash
# lokalnie te same komendy co w CI
uv sync --locked --extra cpu --extra all
uv run ruff check . && uv run ruff format --check . && uv run lint-imports
uv run pytest -m "not requires_data and not slow and not gpu"
```

### Wskazówki i pułapki

- Zmiana `mypy` na blokujący (`continue-on-error: false`) następuje w {{T702}}, gdy kod jest stabilny.
- Nie dodawaj sekretów do workflow w tym zadaniu — nie są potrzebne.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T005-ci-pipeline-v1.md`](https://github.com/__REPO__/blob/main/tasks/T005-ci-pipeline-v1.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] CI uruchamia się na PR i na `main`, jest zielone na `main`.
- [ ] CI instaluje PyTorch w wariancie CPU (brak pobierania pakietów `nvidia-*` w logu).
- [ ] Pełny przebieg ≤ 10 minut przy ciepłym cache.
- [ ] Naruszenie granic modułów (celowy PR testowy) kończy się czerwonym CI na kroku `lint-imports`.
- [ ] Gałąź `main` chroniona: wymagany zielony CI i 1 akceptacja.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T005 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T001}} — Szkielet repozytorium, pyproject i narzędzia jakości (tydzień 1, właściciel C)

**Odblokowuje:**

- {{T702}} — CI/CD pełne — frontend, obrazy, wydania i promocja modelu (tydzień 13, właściciel C)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T005` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t005-ci-pipeline-v1`; status karty `in_progress` (`python3 scripts/tasks.py set-status T005 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(ci): <description> [T005]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T005`.

W Claude Code zadanie realizuje komenda `/task T005`.
__ISSUE_BODY_EOF__
}

body_T101() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T101-download-verify.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Każda osoba odtwarza identyczne dane jedną komendą, a skrypty budujące indeks odmawiają pracy na niezweryfikowanych danych.

| Pole | Wartość |
|---|---|
| Zadanie | **T101** — Pobieranie PTB-XL 1.0.3, weryfikacja SHA-256 i manifest |
| Epik | Dane (`data`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 1 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G1 — Data |
| Eksperyment | — |
| Właściciel | A (Data & Signal ML) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§1](https://github.com/__REPO__/blob/main/docs/data_contract.md#1-źródło-i-licencja) (źródło, licencja), [§2](https://github.com/__REPO__/blob/main/docs/data_contract.md#2-układ-na-dysku-i-pobieranie) (układ na dysku, `MANIFEST.json`)
- [`docs/environment.md`](https://github.com/__REPO__/blob/main/docs/environment.md) [§5](https://github.com/__REPO__/blob/main/docs/environment.md#5-dane-na-każdej-maszynie) (dane na każdej maszynie)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§2](https://github.com/__REPO__/blob/main/AGENTS.md#2-zasady-nienaruszalne) pkt 8 (dane poza gitem)

## 🛠️ Szczegóły techniczne

### Zakres

- Pobranie ZIP-a wersji 1.0.3 (wznawianie przez nagłówek `Range`, gdy serwer go obsługuje), rozpakowanie i przeniesienie do `data/raw/ptb-xl-1.0.3/`.
- Tryb `--from-zip` (ZIP pobrany ręcznie) i `--force`; idempotencja (ponowne uruchomienie przy poprawnym manifeście nic nie robi).
- Weryfikacja wszystkich plików względem `SHA256SUMS.txt`; tryb `--quick` (CSV + 2% losowych rekordów, seed 0).
- Zapis `MANIFEST.json` według `docs/data_contract.md` §2; kod wyjścia 1 przy brakach lub niezgodnościach.
- Sprawdzenie wolnego miejsca na dysku przed pobraniem (≥ 6 GB).

### Poza zakresem (wiążące)

- Budowa indeksu ({{T103}}), cache ({{T106}}). Pobieranie z AWS (opcjonalny wariant ręczny opisany w docs).

### Pliki

- `src/cardioai/data/download.py`, `src/cardioai/data/checksums.py` — nowe
- `scripts/download_ptbxl.py`, `scripts/verify_checksums.py` — nowe
- `tests/unit/data/test_checksums.py`, `tests/unit/data/test_download.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
PTBXL_ZIP_URL: str            # stała w download.py; zweryfikuj link „Download the ZIP file” na stronie projektu

def download_file(url: str, dest: Path, *, chunk_size: int = 1 << 20, resume: bool = True,
                  timeout_s: float = 60.0) -> Path: ...
def extract_dataset(zip_path: Path, dest_root: Path) -> Path: ...         # zwraca data/raw/ptb-xl-1.0.3
def parse_sha256sums(path: Path) -> dict[str, str]: ...                   # ścieżka względna -> hash hex
def sha256_file(path: Path, chunk_size: int = 1 << 20) -> str: ...

@dataclass
class VerificationReport:
    n_files: int; n_ok: int; n_missing: int; n_mismatch: int; total_bytes: int
    missing: list[str]; mismatched: list[str]; quick: bool

def verify_dataset(root: Path, *, quick: bool = False, seed: int = 0) -> VerificationReport: ...
def write_manifest(root: Path, report: VerificationReport) -> Path: ...
def read_manifest(root: Path) -> dict[str, Any]: ...                      # ManifestError, gdy brak lub niezgodny
```

CLI: `download_ptbxl.py [--dest data/raw] [--url URL] [--from-zip PATH] [--force]`,
`verify_checksums.py [--root PATH] [--quick]`.

### Testy do napisania

- `test_checksums.py`: `sha256_file` na znanych bajtach; parsowanie `SHA256SUMS.txt` (spacje, ścieżki z `/`); wykrycie braku i niezgodności; tryb `quick`.
- `test_download.py`: pobieranie z lokalnego `http.server` w wątku albo z mockiem `urlopen`; wznawianie; rozpakowanie ZIP-a z długą nazwą katalogu głównego.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_checksums.py tests/unit/data/test_download.py -q
uv run python scripts/download_ptbxl.py
uv run python scripts/verify_checksums.py
```

### Wskazówki i pułapki

- Katalog główny w ZIP-ie ma długą nazwę (`ptb-xl-a-large-publicly-available-electrocardiography-dataset-1.0.3`) — przenieś zawartość, nie kopiuj dwa razy.
- Ścieżki w `SHA256SUMS.txt` mają `/` — na Windows łącz przez `root / Path(rel)`.
- Pełna weryfikacja ~3 GB trwa od kilkudziesięciu sekund do kilku minut — loguj postęp co 1000 plików.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T101-download-verify.md`](https://github.com/__REPO__/blob/main/tasks/T101-download-verify.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Na prawdziwych danych: `verify_checksums.py` (pełny) daje `n_mismatch == 0`, `n_missing == 0` i zapisuje `MANIFEST.json`.
- [ ] `MANIFEST.json` zawiera wszystkie pola z `docs/data_contract.md` §2.
- [ ] Ponowne `download_ptbxl.py` przy kompletnych danych kończy się bez pobierania.
- [ ] Przerwane pobieranie wznawia się (lub zaczyna od nowa z ostrzeżeniem, gdy serwer nie wspiera `Range`).
- [ ] `--from-zip` działa na ZIP-ie pobranym przeglądarką.
- [ ] Testy nie korzystają z internetu.
- [ ] Wartości `sha256sums_sha256` z trzech maszyn porównane i zgodne (komentarz w PR).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T101 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T001}} — Szkielet repozytorium, pyproject i narzędzia jakości (tydzień 1, właściciel C)

**Odblokowuje:**

- {{T103}} — Indeks etykiet i splitów (parquet + meta) (tydzień 2, właściciel A)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T101` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t101-download-verify`; status karty `in_progress` (`python3 scripts/tasks.py set-status T101 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T101]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T101`.

W Claude Code zadanie realizuje komenda `/task T101`.
__ISSUE_BODY_EOF__
}

body_T102() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T102-mini-ptbxl-fixture.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Mały, deterministyczny zbiór o strukturze identycznej z PTB-XL, generowany w trakcie testów. Dzięki niemu każde zadanie
(i CI) testuje pełny pipeline danych bez pobierania 3 GB i bez commitowania binariów.

| Pole | Wartość |
|---|---|
| Zadanie | **T102** — Syntetyczny mini-PTB-XL jako fixture testów |
| Epik | Dane (`data`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 1 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G1 — Data |
| Eksperyment | — |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§2](https://github.com/__REPO__/blob/main/docs/data_contract.md#2-układ-na-dysku-i-pobieranie) (układ plików), [§3](https://github.com/__REPO__/blob/main/docs/data_contract.md#3-kolumny-źródłowe-i-ich-obróbka) (kolumny), [§7](https://github.com/__REPO__/blob/main/docs/data_contract.md#7-sygnał-odczyt-jednostki-kolejność-odprowadzeń) (sygnał), [§14](https://github.com/__REPO__/blob/main/docs/data_contract.md#14-znane-pułapki-ptb-xl) (pułapki — fixture ma je odtwarzać)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§8](https://github.com/__REPO__/blob/main/AGENTS.md#8-testy) (testy bez prawdziwych danych)

## 🛠️ Szczegóły techniczne

### Zakres

- Funkcja generująca w katalogu docelowym: `ptbxl_database.csv` (wszystkie 28 kolumn), `scp_statements.csv`
  (te same kolumny co oryginał, ok. 15 kodów: `NORM`, `IMI`, `ASMI`, `NDT`, `NST_`, `ISC_`, `LAFB`, `IRBBB`, `CLBBB`, `LVH`, `RVH`
  oraz rytm i forma, np. `SR`, `AFIB`, `PVC`, `LVOLT`), pliki WFDB 100 Hz (`records100/00000/xxxxx_lr`) i 500 Hz (`records500/00000/xxxxx_hr`), `SHA256SUMS.txt`.
- Treść: 40 rekordów, ok. 30 pacjentów (część z 2 rekordami w tym samym foldzie), każdy fold 1–10 z ≥ 3 rekordami (fold 9 z ≥ 5 — razem co najmniej 32 z 40),
  wszystkie 5 superklas, ≥ 5 rekordów wieloetykietowych, ≥ 2 rekordy bez superklasy, `likelihood` 0 w części kodów.
  Fold 9 (val) zawiera dla każdej z 5 superklas co najmniej 1 rekord pozytywny i 1 negatywny — inaczej AUROC i metryki jakości na val byłyby `NaN`.
- Pułapki z §14: `patient_id` jako float, `scp_codes` jako tekst słownika Pythona, wiek 300 i NaN, puste `height`/`weight`,
  pola jakości puste i niepuste (różne formaty), nazwy kanałów `AVR/AVL/AVF` wielkimi literami; jeden rekord z permutowaną kolejnością kanałów w nagłówku.
- Sygnał EKG-podobny (suma funkcji Gaussa na uderzenie, 50–100 bpm, różne wzmocnienia per odprowadzenie), mV, `fmt="16"`, 1 µV/LSB.
- Fixture pytest o zasięgu sesji oraz słownik oczekiwanych wartości do asercji.

### Poza zakresem (wiążące)

- Realistyczna morfologia patologii — etykiety są przypisane, sygnał nie musi ich odzwierciedlać.

### Pliki

- `tests/fixtures/make_mini_ptbxl.py` — nowy (funkcja + uruchamianie jako skrypt)
- `tests/conftest.py` — nowy (fixture `mini_ptbxl_root`)
- `tests/unit/data/test_mini_ptbxl.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def make_mini_ptbxl(root: Path, *, n_records: int = 40, seed: int = 0) -> Path: ...

MINI_EXPECTED: dict[str, Any]    # n_records, n_patients, per_class_counts, n_unlabeled, folds_per_split

@pytest.fixture(scope="session")
def mini_ptbxl_root(tmp_path_factory: pytest.TempPathFactory) -> Path: ...
```

### Testy do napisania

- `test_mini_ptbxl.py`: odczyt CSV i WFDB, deterministyczność, rozłączność pacjentów między foldami, zgodność z `MINI_EXPECTED`, pozytywy i negatywy każdej superklasy w foldzie 9.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_mini_ptbxl.py -q
uv run python tests/fixtures/make_mini_ptbxl.py --out /tmp/mini_ptbxl
```

### Wskazówki i pułapki

- `wfdb.wrsamp` zapisuje w bieżącym katalogu lub w `write_dir` — ustaw `write_dir` jawnie.
- Wersję 100 Hz generuj przez decymację wersji 500 Hz (`scipy.signal.decimate` lub `resample_poly`), żeby obie były spójne.
- Fixture będzie używana przez większość zadań — zmiany w niej wymagają uruchomienia całego zestawu testów.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T102-mini-ptbxl-fixture.md`](https://github.com/__REPO__/blob/main/tasks/T102-mini-ptbxl-fixture.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Generowanie trwa < 3 s i jest deterministyczne (dwa przebiegi z tym samym seedem → identyczny `SHA256SUMS.txt`).
- [ ] `wfdb.rdsamp` czyta rekordy: `[1000, 12]` przy 100 Hz i `[5000, 12]` przy 500 Hz, `units == "mV"`.
- [ ] Każdy pacjent jest w jednym foldzie; każdy fold ma ≥ 3 rekordy, a fold 9 ≥ 5 rekordów z ≥ 1 pozytywem i ≥ 1 negatywem każdej superklasy.
- [ ] `MINI_EXPECTED` zgadza się z wygenerowanymi plikami (test).
- [ ] Żaden plik binarny nie jest commitowany — wszystko powstaje w `tmp_path_factory`.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T102 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T001}} — Szkielet repozytorium, pyproject i narzędzia jakości (tydzień 1, właściciel C)

**Odblokowuje:**

- {{T103}} — Indeks etykiet i splitów (parquet + meta) (tydzień 2, właściciel A)
- {{T604}} — FastAPI v1 z MockPredictorem i typami inferencji (kontrakt-first) (tydzień 3, właściciel C)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T102` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t102-mini-ptbxl-fixture`; status karty `in_progress` (`python3 scripts/tasks.py set-status T102 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(repo): <description> [T102]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T102`.

W Claude Code zadanie realizuje komenda `/task T102`.
__ISSUE_BODY_EOF__
}

body_T103() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T103-label-index.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Jeden indeks wszystkich rekordów z etykietami 5 superklas, splitem i metadanymi — budowany raz, czytany przez wszystkie dalsze etapy.

| Pole | Wartość |
|---|---|
| Zadanie | **T103** — Indeks etykiet i splitów (parquet + meta) |
| Epik | Dane (`data`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 2 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G1 — Data |
| Eksperyment | E00 |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§3](https://github.com/__REPO__/blob/main/docs/data_contract.md#3-kolumny-źródłowe-i-ich-obróbka) (kolumny i obróbka), [§4](https://github.com/__REPO__/blob/main/docs/data_contract.md#4-etykiety-superklas) (etykiety), [§5](https://github.com/__REPO__/blob/main/docs/data_contract.md#5-split-i-niezmienniki) (split), [§6](https://github.com/__REPO__/blob/main/docs/data_contract.md#6-indeks--schemat) (schemat indeksu), [§11](https://github.com/__REPO__/blob/main/docs/data_contract.md#11-etykiety-jakości-słabe) (flagi jakości), [§15](https://github.com/__REPO__/blob/main/docs/data_contract.md#15-liczby-kontrolne-i-wyniki-eda) (liczby kontrolne)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-004](https://github.com/__REPO__/blob/main/docs/decisions.md#d-004--etykiety-superklas-zgodne-z-benchmarkiem), [D-016](https://github.com/__REPO__/blob/main/docs/decisions.md#d-016--wiek--300-traktowany-jako-90), [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) (nazwa `build_index.py`)

## 🛠️ Szczegóły techniczne

### Zakres

- Parsowanie `scp_codes`, mapowanie kodów diagnostycznych na superklasy (§4), obróbka kolumn (§3), flagi jakości `q_*` (§11).
- Zapis `ptbxl_index_v1.0.3.parquet` i `.meta.json` (§6), z `index_sha256` liczonym z kanonicznej serializacji (nie z bajtów parquet).
- Sprawdzenie `MANIFEST.json` przed budową (flaga `--skip-manifest-check` tylko dla fixture'a).
- `load_index` z walidacją schematu i typów.

### Poza zakresem (wiążące)

- Pełne testy niezmienników ({{T104}}) — tu wywołanie podstawowej walidacji schematu.
- Etykiety podklas, rytmu i formy ({{T403}} korzysta z `scp_codes_json`).

### Pliki

- `src/cardioai/data/labels.py`, `src/cardioai/data/index.py` — nowe
- `scripts/build_index.py` — nowy
- `tests/unit/data/test_labels.py`, `tests/unit/data/test_index.py` — nowe
- `tests/data/test_index_real.py` — nowy (`requires_data`)

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def parse_scp_codes(raw: str) -> dict[str, float]: ...                   # ast.literal_eval
def load_scp_statements(root: Path) -> pd.DataFrame: ...
def superclass_mapping(statements: pd.DataFrame) -> dict[str, str]: ...  # kod -> superklasa (diagnostic == 1)
def derive_superclasses(scp: Mapping[str, float], mapping: Mapping[str, str],
                        min_likelihood: float = 0.0) -> list[str]: ...    # w kolejności SUPERCLASSES
def build_index(root: Path, *, min_likelihood: float = 0.0, check_manifest: bool = True) -> pd.DataFrame: ...
def compute_index_sha256(df: pd.DataFrame) -> str: ...
def save_index(df: pd.DataFrame, path: Path) -> Path: ...                 # zapisuje też .meta.json
def load_index(path: Path) -> pd.DataFrame: ...                           # IndexSchemaError przy niezgodności
def default_index_path(cfg: RunConfig) -> Path: ...
class IndexBuildError(RuntimeError): ...
class IndexSchemaError(ValueError): ...
```

CLI: `build_index.py [--data-root PATH] [--out PATH] [--min-likelihood 0.0] [--skip-manifest-check]` — wypisuje tabelę liczebności per split i klasa.

### Testy do napisania

- `test_labels.py`: parsowanie (w tym `likelihood` 0), mapowanie, kody rytmu ignorowane, rekord bez superklasy, próg `min_likelihood`.
- `test_index.py`: budowa na `mini_ptbxl_root`, schemat, typy, wiek 300, flagi jakości, stabilność `index_sha256`, `load_index` odrzuca uszkodzony plik.
- `test_index_real.py` (`requires_data`): liczby kontrolne z §15.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_labels.py tests/unit/data/test_index.py -q
uv run python scripts/build_index.py
uv run pytest -m requires_data tests/data/test_index_real.py
```

### Wskazówki i pułapki

- `scp_codes` to tekst słownika Pythona — `json.loads` nie zadziała.
- `strat_fold` i `patient_id` rzutuj jawnie; pandas lubi zamieniać int na float przy NaN w innych kolumnach.
- Do `compute_index_sha256` użyj CSV z ustalonym formatem liczb (np. `float_format="%.6g"`) i posortowanymi kolumnami.

## 🧪 Eksperyment E00 — EDA i sanity checks

**Cel decyzyjny:** liczebności, split, brak przecieku · zadania: {{T104}}, {{T110}} · właściciel eksperymentu: A · tydzień: 2–3

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Pytanie:** czy indeks odtwarza liczby z PhysioNet i czy split jest wolny od przecieku?
- **Wynik:** `reports/eda/` + uzupełnienie `docs/data_contract.md` §15.
- **Reguła:** wszystkie testy kontraktu danych ({{T104}}) zielone; różnice liczebności wyjaśnione.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T103-label-index.md`](https://github.com/__REPO__/blob/main/tasks/T103-label-index.md)
- Decyzja [D-004](https://github.com/__REPO__/blob/main/docs/decisions.md#d-004--etykiety-superklas-zgodne-z-benchmarkiem) — Etykiety superklas zgodne z benchmarkiem
- Decyzja [D-016](https://github.com/__REPO__/blob/main/docs/decisions.md#d-016--wiek--300-traktowany-jako-90) — Wiek ≥ 300 traktowany jako 90+
- Decyzja [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) — Drobne odstępstwa od specyfikacji
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Kolumny, typy i kolejność zgodne z `docs/data_contract.md` §6; plik meta z wszystkimi polami.
- [ ] Na prawdziwych danych: 21 799 wierszy, 18 869 pacjentów, liczby klas zgodne z §15 — albo różnica opisana w §15 i w PR (bez zmiany algorytmu na siłę).
- [ ] Wiek ≥ 300 → 90 + `age_90plus = 1`; `patient_id` jako `int32`; `scp_codes_json` jest poprawnym JSON-em.
- [ ] Brak lub niezgodny `MANIFEST.json` → `IndexBuildError` (chyba że `--skip-manifest-check`).
- [ ] `index_sha256` identyczny przy dwóch budowach i na różnych systemach operacyjnych.
- [ ] Na fixture: liczności zgodne z `MINI_EXPECTED`.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T103 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T101}} — Pobieranie PTB-XL 1.0.3, weryfikacja SHA-256 i manifest (tydzień 1, właściciel A)
- {{T102}} — Syntetyczny mini-PTB-XL jako fixture testów (tydzień 1, właściciel A)

**Odblokowuje:**

- {{T104}} — Testy kontraktu danych i ochrona przed przeciekiem (tydzień 2, właściciel A)
- {{T105}} — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu (tydzień 2, właściciel A)
- {{T110}} — EDA i raport danych (E00) (tydzień 3, właściciel A)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T103` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t103-label-index`; status karty `in_progress` (`python3 scripts/tasks.py set-status T103 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T103]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T103`.

W Claude Code zadanie realizuje komenda `/task T103`.
__ISSUE_BODY_EOF__
}

body_T104() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T104-data-contract-tests.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Automatyczny dowód, że split jest rozłączny pacjentowo i zgodny z foldami — uruchamiany przy budowie indeksu, w CI (fixture) i lokalnie na prawdziwych danych.

| Pole | Wartość |
|---|---|
| Zadanie | **T104** — Testy kontraktu danych i ochrona przed przeciekiem |
| Epik | Dane (`data`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 2 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G1 — Data |
| Eksperyment | E00 |
| Właściciel | A (Data & Signal ML) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§5](https://github.com/__REPO__/blob/main/docs/data_contract.md#5-split-i-niezmienniki) (niezmienniki), [§6](https://github.com/__REPO__/blob/main/docs/data_contract.md#6-indeks--schemat) (schemat)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§2](https://github.com/__REPO__/blob/main/AGENTS.md#2-zasady-nienaruszalne) pkt 1–3
- Specyfikacja §13.1 (rejestr ryzyk: przeciek między pacjentami)

## 🛠️ Szczegóły techniczne

### Zakres

- `check_index_invariants` zwracająca listę naruszeń dla niezmienników 1–4 z §5 oraz: kolejność kolumn etykiet, wartości kategorii `split`, brak duplikatów kolumn.
- `assert_index_invariants` (wyjątek z listą naruszeń) wywoływana w `build_index` przed zapisem.
- Sprawdzenie istnienia plików WFDB dla wszystkich wierszy (tylko test `requires_data`).

### Poza zakresem (wiążące)

- Niezmiennik 5 (źródło statystyk) — sprawdzają {{T107}} i {{T801}}.

### Pliki

- `src/cardioai/data/contract.py` — nowy
- `src/cardioai/data/index.py` — zmiana (wywołanie `assert_index_invariants`)
- `tests/unit/data/test_contract.py` — nowy
- `tests/data/test_contract_real.py` — nowy (`requires_data`)

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def check_index_invariants(df: pd.DataFrame) -> list[str]: ...    # pusta lista = OK
def assert_index_invariants(df: pd.DataFrame) -> None: ...        # DataContractError
class DataContractError(ValueError): ...
```

### Testy do napisania

- `test_contract.py`: ramka poprawna; duplikat `ecg_id`; fold 11; pacjent w dwóch splitach; `split` niezgodny z foldem;
  etykieta 2; `n_superclasses` niezgodne z sumą; zła kolejność kolumn etykiet.
- `test_contract_real.py`: niezmienniki + istnienie plików na prawdziwych danych.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_contract.py -q
uv run pytest -m requires_data tests/data/test_contract_real.py
```

### Wskazówki i pułapki

- Komunikaty błędów mają wskazywać przykładowe identyfikatory (max 10), żeby diagnoza była szybka.

## 🧪 Eksperyment E00 — EDA i sanity checks

**Cel decyzyjny:** liczebności, split, brak przecieku · zadania: T104, {{T110}} · właściciel eksperymentu: A · tydzień: 2–3

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Pytanie:** czy indeks odtwarza liczby z PhysioNet i czy split jest wolny od przecieku?
- **Wynik:** `reports/eda/` + uzupełnienie `docs/data_contract.md` §15.
- **Reguła:** wszystkie testy kontraktu danych (T104) zielone; różnice liczebności wyjaśnione.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T104-data-contract-tests.md`](https://github.com/__REPO__/blob/main/tasks/T104-data-contract-tests.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] Dla każdego niezmiennika istnieje test negatywny: celowo zepsuta ramka → konkretny komunikat (np. pacjent w train i val).
- [ ] Indeks z fixture'a i z prawdziwych danych przechodzi bez naruszeń.
- [ ] `build_index` nie zapisze indeksu łamiącego kontrakt.
- [ ] Test `requires_data` sprawdza, że każdy `filename_lr` i `filename_hr` ma pliki `.hea` i `.dat`.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T104 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T103}} — Indeks etykiet i splitów (parquet + meta) (tydzień 2, właściciel A)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T104` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t104-data-contract-tests`; status karty `in_progress` (`python3 scripts/tasks.py set-status T104 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T104]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T104`.

W Claude Code zadanie realizuje komenda `/task T104`.
__ISSUE_BODY_EOF__
}

body_T105() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T105-wfdb-dataset-loader.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Dataset zwracający próbki w formacie z kontraktu, z deterministyczną losowością niezależną od liczby workerów,
punktami rozszerzeń dla kolejnych zadań (pipeline, cache, metadane) i twardą blokadą foldu 10.

| Pole | Wartość |
|---|---|
| Zadanie | **T105** — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu |
| Epik | Dane (`data`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 2 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G1 — Data |
| Eksperyment | — |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§7](https://github.com/__REPO__/blob/main/docs/data_contract.md#7-sygnał-odczyt-jednostki-kolejność-odprowadzeń) (sygnał, kolejność odprowadzeń), [§8](https://github.com/__REPO__/blob/main/docs/data_contract.md#8-próbka-z-dataset-i-pipeline-transformacji) (próbka, pipeline, determinizm), [§13](https://github.com/__REPO__/blob/main/docs/data_contract.md#13-brakujące-odprowadzenia) (brakujące odprowadzenia)
- [`docs/evaluation.md`](https://github.com/__REPO__/blob/main/docs/evaluation.md) [§7](https://github.com/__REPO__/blob/main/docs/evaluation.md#7-blokada-testu-i-protokół-finalny) (blokada testu)
- [`docs/environment.md`](https://github.com/__REPO__/blob/main/docs/environment.md) [§6](https://github.com/__REPO__/blob/main/docs/environment.md#6-windows--pułapki) (Windows: spawn, pickle)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-010](https://github.com/__REPO__/blob/main/docs/decisions.md#d-010--kolejność-transformacji-i-konwencja-brakującego-odprowadzenia), [D-020](https://github.com/__REPO__/blob/main/docs/decisions.md#d-020--deterministyczne-augmentacje-niezależne-od-workerów)

## 🛠️ Szczegóły techniczne

### Zakres

- `read_record` z porządkowaniem kanałów po nazwach z nagłówka (bez rozróżniania wielkości liter), kontrolą `fs`, długości, jednostek i NaN/Inf.
- `SignalSample`, protokół `Transform`, `Compose`, `ApplyLeadMask` (krok 8 z §8) — fundament pipeline'u rozwijanego w {{T107}}–{{T109}}.
- `SignalSource` + `WFDBSource`; `PTBXLDataset` z filtrowaniem splitu i rekordów bez etykiet; `FieldProvider` dla dodatkowych pól ({{T402}}, {{T403}}).
- `EpochAwareSampler` zwracający `(epoch, index)`; `build_dataset`, `build_dataloader`, `build_dataloaders` z fabryką pipeline'u.
- `cardioai.data.test_lock` (`docs/evaluation.md` §7): `split="test"` bez odblokowania → `LockedSplitError`.

### Poza zakresem (wiążące)

- Cache ({{T106}}), normalizacja ({{T107}}), filtry i `build_pipeline` ({{T108}}), augmentacje ({{T109}}), etykiety jakości ({{T301}}), metadane ({{T402}}).

### Pliki

- `src/cardioai/data/wfdb_io.py`, `transforms.py`, `samplers.py`, `dataset.py`, `datamodule.py`, `test_lock.py` — nowe
- `tests/unit/data/test_wfdb_io.py`, `test_dataset.py`, `test_samplers.py`, `test_test_lock.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def canonicalize_leads(signal: np.ndarray, names: Sequence[str]) -> np.ndarray: ...   # [12, T] w kolejności LEADS
def read_record(root: Path, rel_path: str, *, expected_fs: int | None = None) -> tuple[np.ndarray, int]: ...
class RecordFormatError(ValueError): ...

@dataclass
class SignalSample:
    x: np.ndarray            # [12, T] float32
    fs: int
    lead_mask: np.ndarray    # [12] bool, True = obecne
    quality: np.ndarray      # [4] int8, etykiety z korupcji (kolejność QUALITY_LABELS)

class Transform(Protocol):
    def __call__(self, s: SignalSample, rng: np.random.Generator) -> SignalSample: ...
class Compose:
    def __init__(self, transforms: Sequence[Transform]) -> None: ...
class ApplyLeadMask: ...                     # x[~lead_mask] = 0.0

class SignalSource(Protocol):
    def get(self, ecg_id: int, rel_path: str) -> np.ndarray: ...   # [12, T] float32, mV
class WFDBSource:
    def __init__(self, root: Path, sampling_rate: int) -> None: ...

class FieldProvider(Protocol):
    def __call__(self, row: Mapping[str, Any]) -> dict[str, torch.Tensor]: ...

class PTBXLDataset(torch.utils.data.Dataset):
    def __init__(self, index: pd.DataFrame, split: Literal["train", "val", "test"], *, sampling_rate: int,
                 source: SignalSource, pipeline: Transform | None = None, seed: int = 0,
                 drop_unlabeled: bool = True, return_quality: bool = False,
                 extra_fields: Sequence[FieldProvider] = ()) -> None: ...
    def __getitem__(self, key: int | tuple[int, int]) -> dict[str, Any]: ...   # key = idx albo (epoch, idx)

class EpochAwareSampler(torch.utils.data.Sampler[tuple[int, int]]):
    def __init__(self, n: int, *, shuffle: bool, seed: int) -> None: ...
    def set_epoch(self, epoch: int) -> None: ...

def build_dataset(cfg: RunConfig, split: str, *, index: pd.DataFrame | None = None,
                  pipeline: Transform | None = None) -> PTBXLDataset: ...
def build_dataloader(dataset: PTBXLDataset, *, batch_size: int, shuffle: bool, num_workers: int,
                     seed: int) -> DataLoader: ...
def build_dataloaders(cfg: RunConfig, splits: Sequence[str] = ("train", "val"), *,
                      pipeline_factory: Callable[[str], Transform | None] | None = None) -> dict[str, DataLoader]: ...

class LockedSplitError(RuntimeError): ...
def is_test_unlocked(repo_root: Path | None = None) -> bool: ...   # CARDIOAI_ALLOW_TEST=1 i release/final_freeze.json
def require_test_unlocked(context: str) -> None: ...
```

### Testy do napisania

- `test_wfdb_io.py`: kształty 100/500 Hz, jednostki, permutacja kanałów, zły `fs`, NaN → `RecordFormatError`.
- `test_dataset.py`: filtrowanie splitów, `drop_unlabeled`, klucze próbki, pickle, `FieldProvider`.
- `test_samplers.py`: deterministyczna permutacja per epoka; klucze `(epoch, idx)`.
- `test_test_lock.py`: brak zmiennej, brak pliku, oba obecne (w `tmp_path`).

### Weryfikacja

```bash
uv run pytest tests/unit/data -q
```

### Wskazówki i pułapki

- RNG próbki: `np.random.default_rng([seed, epoch, ecg_id])` — nie używaj `torch.initial_seed()` w workerze.
- Na Windows DataLoader z `num_workers > 0` wymaga picklowalnych obiektów — żadnych lambd w `pipeline` i `extra_fields`.
- `collate` domyślny PyTorch obsłuży słownik z tensorami i intami; nie dokładaj własnego bez potrzeby.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T105-wfdb-dataset-loader.md`](https://github.com/__REPO__/blob/main/tasks/T105-wfdb-dataset-loader.md)
- Decyzja [D-010](https://github.com/__REPO__/blob/main/docs/decisions.md#d-010--kolejność-transformacji-i-konwencja-brakującego-odprowadzenia) — Kolejność transformacji i konwencja brakującego odprowadzenia
- Decyzja [D-020](https://github.com/__REPO__/blob/main/docs/decisions.md#d-020--deterministyczne-augmentacje-niezależne-od-workerów) — Deterministyczne augmentacje niezależne od workerów
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Próbka ma klucze i kształty z `docs/data_contract.md` §8 (`x`, `y`, `lead_mask`, `ecg_id`, `patient_id`, `fold`; `y_quality` gdy `return_quality`).
- [ ] Rekord z permutowaną kolejnością kanałów w nagłówku (fixture) daje tę samą tablicę co rekord wzorcowy.
- [ ] `drop_unlabeled=True` usuwa rekordy z `n_superclasses == 0`.
- [ ] Te same `(seed, epoch)` → identyczne batche przy `num_workers=0` i `num_workers=2` (z transformem losowym w teście).
- [ ] `split="test"` bez odblokowania → `LockedSplitError` z instrukcją ({{T801}}).
- [ ] `PTBXLDataset` i źródła są picklowalne (test `pickle.dumps`).
- [ ] `build_dataloaders` działa na `mini_ptbxl_root` z `e00_smoke.yaml`.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T105 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T002}} — System konfiguracji (YAML + Pydantic, extends, --set, config_hash) (tydzień 1, właściciel B)
- {{T003}} — Device, seed, AMP, git i informacje o środowisku (tydzień 1, właściciel B)
- {{T103}} — Indeks etykiet i splitów (parquet + meta) (tydzień 2, właściciel A)

**Odblokowuje:**

- {{T106}} — Cache sygnałów NPY z dostępem memmap (tydzień 3, właściciel A)
- {{T107}} — Statystyki normalizacji z train i transformacja Normalize (tydzień 3, właściciel A)
- {{T110}} — EDA i raport danych (E00) (tydzień 3, właściciel A)
- {{T203}} — Baseline klasyczny na cechach sygnałowych (E01) (tydzień 3, właściciel C)
- {{T204}} — Pętla treningowa, straty, checkpointy i scripts/train.py (tydzień 3, właściciel B)
- {{T301}} — Słabe etykiety jakości w Dataset i analiza ich wiarygodności (tydzień 5, właściciel A)
- {{T602}} — Parsowanie i walidacja wejścia (WFDB, NPZ, CSV) (tydzień 8, właściciel A)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T105` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t105-wfdb-dataset-loader`; status karty `in_progress` (`python3 scripts/tasks.py set-status T105 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T105]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T105`.

W Claude Code zadanie realizuje komenda `/task T105`.
__ISSUE_BODY_EOF__
}

body_T106() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T106-signal-cache.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Szybki odczyt sygnałów bez parsowania tysięcy plików WFDB w każdej epoce i bez ładowania całego zbioru do RAM
(500 Hz to ok. 5,2 GB).

| Pole | Wartość |
|---|---|
| Zadanie | **T106** — Cache sygnałów NPY z dostępem memmap |
| Epik | Dane (`data`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 3 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G1 — Data |
| Eksperyment | — |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§10](https://github.com/__REPO__/blob/main/docs/data_contract.md#10-cache-sygnałów) (format cache, zasady memmap)
- [`docs/environment.md`](https://github.com/__REPO__/blob/main/docs/environment.md) [§1](https://github.com/__REPO__/blob/main/docs/environment.md#1-sprzęt-zespołu-i-podział-pracy) (16 GB RAM), [§6](https://github.com/__REPO__/blob/main/docs/environment.md#6-windows--pułapki) (Windows: spawn)

## 🛠️ Szczegóły techniczne

### Zakres

- `build_cache`: zapis `signals.npy` przez `np.lib.format.open_memmap` (bez trzymania całości w pamięci), `ecg_ids.npy`, `meta.json`.
- `CacheSource` (implementuje `SignalSource`): memmap otwierany leniwie przy pierwszym `get` w danym procesie; mapowanie `ecg_id → wiersz`.
- Kontrola zgodności z indeksem (`index_sha256`) → `CacheMismatchError` z poleceniem przebudowy.
- `build_dataloaders` wybiera `CacheSource`, gdy `data.cache_dir` jest ustawione i cache istnieje; w przeciwnym razie `WFDBSource` z ostrzeżeniem.
- `scripts/build_cache.py --sampling-rate {100,500}`.

### Poza zakresem (wiążące)

- Cache po preprocessingu lub normalizacji — cache przechowuje wyłącznie surowe mV.

### Pliki

- `src/cardioai/data/cache.py` — nowy
- `src/cardioai/data/datamodule.py` — zmiana (wybór źródła)
- `scripts/build_cache.py` — nowy
- `tests/unit/data/test_cache.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def default_cache_dir(cache_root: Path, sampling_rate: int) -> Path: ...    # .../ptbxl_v1.0.3_{fs}hz
def build_cache(index: pd.DataFrame, root: Path, sampling_rate: int, out_dir: Path) -> Path: ...
class CacheSource:
    def __init__(self, cache_dir: Path, *, expected_index_sha256: str | None = None) -> None: ...
    def get(self, ecg_id: int, rel_path: str | None = None) -> np.ndarray: ...   # kopia [12, T] float32
class CacheMismatchError(RuntimeError): ...
```

### Testy do napisania

- `test_cache.py`: zgodność z WFDB, meta, pickle, niezgodny hash, brak katalogu → czytelny błąd.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_cache.py -q
uv run python scripts/build_cache.py --sampling-rate 100
```

### Wskazówki i pułapki

- `np.load(path, mmap_mode="r")` w `__init__` + pickle → kopia całej tablicy do workera. Otwieraj w `get`, gdy atrybut jest `None`, i usuń go w `__getstate__`.
- `get` zwraca kopię (`np.array(view, dtype=np.float32)`), bo transformy modyfikują tablice.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T106-signal-cache.md`](https://github.com/__REPO__/blob/main/tasks/T106-signal-cache.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] Na fixture: `CacheSource.get` i `WFDBSource.get` zwracają identyczne tablice (`np.array_equal`) dla wszystkich rekordów.
- [ ] `pickle.dumps(CacheSource(...))` ma < 10 KB (memmap nie jest serializowany).
- [ ] Niezgodny `index_sha256` → `CacheMismatchError`.
- [ ] Budowa cache 100 Hz na prawdziwych danych zakończona; czas i rozmiar zapisane w PR.
- [ ] Trening na cache z `num_workers=2` działa na Windows (potwierdzenie z laptopa RTX).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T106 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T105}} — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu (tydzień 2, właściciel A)

**Odblokowuje:**

- {{T110}} — EDA i raport danych (E00) (tydzień 3, właściciel A)
- {{T404}} — Porównanie 100 Hz vs 500 Hz — jakość a koszt (E10, H5) (tydzień 11, właściciel B)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T106` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t106-signal-cache`; status karty `in_progress` (`python3 scripts/tasks.py set-status T106 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T106]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T106`.

W Claude Code zadanie realizuje komenda `/task T106`.
__ISSUE_BODY_EOF__
}

body_T107() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T107-normalization-stats.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Normalizacja per odprowadzenie liczona wyłącznie na train, zapisana w wersjonowanym pliku i weryfikowana przy użyciu —
ta sama w treningu, ewaluacji i inferencji.

| Pole | Wartość |
|---|---|
| Zadanie | **T107** — Statystyki normalizacji z train i transformacja Normalize |
| Epik | Dane (`data`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 3 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G1 — Data |
| Eksperyment | — |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§8](https://github.com/__REPO__/blob/main/docs/data_contract.md#8-próbka-z-dataset-i-pipeline-transformacji) (krok 6), [§9](https://github.com/__REPO__/blob/main/docs/data_contract.md#9-normalizacja--plik-statystyk) (tryby i plik statystyk)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§2](https://github.com/__REPO__/blob/main/AGENTS.md#2-zasady-nienaruszalne) pkt 3 (statystyki tylko z train)

## 🛠️ Szczegóły techniczne

### Zakres

- Strumieniowe liczenie średniej i odchylenia per odprowadzenie (float64 w NumPy, np. algorytm Welforda lub sumy) na datasecie train
  z pipeline'em bez augmentacji, bez korupcji i bez normalizacji.
- `NormStats` z zapisem i odczytem JSON (§9) oraz kontrolą zgodności `sampling_rate`, `preprocessing_id`, `leads`.
- `Normalize` (Transform): tryby `per_lead_train`, `per_record`, `none`; wynik float32.
- `scripts/compute_norm_stats.py` (ścieżka domyślna z §2).
- `PREPROCESSING_CODE_VERSION`, `preprocessing_id` i `preprocessing_version` (np. `"1:none"`) — jedyne źródło tych wartości w projekcie;
  {{T108}} je importuje i rozszerza o identyfikatory filtrów.

### Poza zakresem (wiążące)

- Identyfikatory wariantów z filtrami w `preprocessing_id` ({{T108}} rozszerza funkcję; tu wystarcza `"none"`, a dla ustawionego `bandpass` lub `notch_hz` — `NotImplementedError` do czasu {{T108}}).

### Pliki

- `src/cardioai/data/normalization.py` — nowy (także `PREPROCESSING_CODE_VERSION`, `preprocessing_id`, `preprocessing_version`)
- `scripts/compute_norm_stats.py` — nowy
- `tests/unit/data/test_normalization.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
@dataclass(frozen=True)
class NormStats:
    sampling_rate: int
    preprocessing_id: str
    leads: tuple[str, ...]
    mean: np.ndarray        # [12] float64 w pliku, float32 przy użyciu
    std: np.ndarray         # [12]
    split: str
    folds: tuple[int, ...]
    n_records: int
    index_sha256: str
    std_floor: float = 1e-6
    def to_dict(self) -> dict[str, Any]: ...          # typy proste (do checkpointu i bundla)
    @classmethod
    def from_dict(cls, d: Mapping[str, Any]) -> "NormStats": ...
    def to_json(self, path: Path) -> None: ...
    @classmethod
    def from_json(cls, path: Path) -> "NormStats": ...

def compute_lead_stats(dataset: PTBXLDataset, *, preprocessing_id: str, index_sha256: str,
                       batch_size: int = 256) -> NormStats: ...       # ValueError, gdy dataset.split != "train"
class Normalize:                                                      # Transform
    def __init__(self, mode: Literal["per_lead_train", "per_record", "none"], stats: NormStats | None = None,
                 *, expected_fs: int | None = None, expected_preprocessing_id: str | None = None,
                 eps: float = 1e-6) -> None: ...
def default_norm_stats_path(cfg: RunConfig, preprocessing_id: str) -> Path: ...
class NormStatsMismatchError(ValueError): ...

PREPROCESSING_CODE_VERSION: Final = 1
def preprocessing_id(cfg: PreprocessingConfig) -> str: ...        # T107: "none"; T108 dodaje filtry (np. "bp0.5-40_n50")
def preprocessing_version(cfg: PreprocessingConfig) -> str: ...   # f"{PREPROCESSING_CODE_VERSION}:{preprocessing_id(cfg)}"
```

### Testy do napisania

- `test_normalization.py`: zgodność z referencją, odmowa dla val/test, round-trip JSON, niezgodności, tryb `per_record`, `none`; `preprocessing_id` i `preprocessing_version` dla configu bez filtrów.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_normalization.py -q
uv run python scripts/compute_norm_stats.py --config configs/experiment/e00_smoke.yaml
```

### Wskazówki i pułapki

- Sumy kwadratów w float32 tracą precyzję przy 17 tys. rekordów × 1000 próbek — akumuluj w float64.
- Statystyki zależą od filtra (krok 4) — nazwa pliku zawiera `preprocessing_id` (D-011).

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T107-normalization-stats.md`](https://github.com/__REPO__/blob/main/tasks/T107-normalization-stats.md)
- Decyzja [D-011](https://github.com/__REPO__/blob/main/docs/decisions.md#d-011--brak-filtracji-w-wariancie-bazowym) — Brak filtracji w wariancie bazowym
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] `compute_lead_stats` na datasecie val lub test → `ValueError`; plik ma `split: "train"` i foldy 1–8.
- [ ] Na fixture średnie i odchylenia zgodne z referencją NumPy liczoną na całej tablicy train (`rtol=1e-6`).
- [ ] Plik JSON ma wszystkie pola z `docs/data_contract.md` §9.
- [ ] `Normalize` z niezgodnym `fs` lub `preprocessing_id` → `NormStatsMismatchError`.
- [ ] `per_record` dla płaskiego odprowadzenia nie daje NaN (dolna granica odchylenia).
- [ ] Wyjście zawsze float32.
- [ ] `preprocessing_version(cfg)` daje `"1:none"` dla configu bez filtrów; funkcja jest jedynym źródłem wartości trafiającej do checkpointu ({{T204}}) i bundla ({{T601}}).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T107 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T105}} — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu (tydzień 2, właściciel A)

**Odblokowuje:**

- {{T108}} — Pipeline preprocessingu, filtry zerofazowe i resampling (tydzień 4, właściciel A)
- {{T204}} — Pętla treningowa, straty, checkpointy i scripts/train.py (tydzień 3, właściciel B)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T107` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t107-normalization-stats`; status karty `in_progress` (`python3 scripts/tasks.py set-status T107 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T107]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T107`.

W Claude Code zadanie realizuje komenda `/task T107`.
__ISSUE_BODY_EOF__
}

body_T108() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T108-preprocessing-filters.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Jedna funkcja budująca pipeline z configu — używana przez Dataset w treningu, ewaluacji, robustness i przez `Predictor` w inferencji.

| Pole | Wartość |
|---|---|
| Zadanie | **T108** — Pipeline preprocessingu, filtry zerofazowe i resampling |
| Epik | Dane (`data`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 4 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G3 — Core model |
| Eksperyment | — |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§8](https://github.com/__REPO__/blob/main/docs/data_contract.md#8-próbka-z-dataset-i-pipeline-transformacji) (kolejność transformacji), [§9](https://github.com/__REPO__/blob/main/docs/data_contract.md#9-normalizacja--plik-statystyk) (`preprocessing_id`), [§14](https://github.com/__REPO__/blob/main/docs/data_contract.md#14-znane-pułapki-ptb-xl) pkt 8 (notch przy 100 Hz)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-010](https://github.com/__REPO__/blob/main/docs/decisions.md#d-010--kolejność-transformacji-i-konwencja-brakującego-odprowadzenia), [D-011](https://github.com/__REPO__/blob/main/docs/decisions.md#d-011--brak-filtracji-w-wariancie-bazowym), [D-023](https://github.com/__REPO__/blob/main/docs/decisions.md#d-023--korupcja-robustness-w-build_pipeline-przy-trainfalse)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§2](https://github.com/__REPO__/blob/main/AGENTS.md#2-zasady-nienaruszalne) pkt 7 (jedna implementacja preprocessingu)

## 🛠️ Szczegóły techniczne

### Zakres

- Filtry: pasmowy Butterworth (`butter(..., output="sos")` + `sosfiltfilt`), notch (`iirnotch` + `filtfilt`), resampling (`resample_poly`).
- Rozszerzenie `preprocessing_id` o identyfikatory filtrów (np. `"bp0.5-40_n50"`, wersja np. `"1:bp0.5-40_n50"`); `PREPROCESSING_CODE_VERSION`, `preprocessing_id` i `preprocessing_version` są zdefiniowane w {{T107}} — T108 je importuje, nie definiuje ich ponownie.
- `build_pipeline` składający kroki 2–9 z `docs/data_contract.md` §8, z miejscami na augmentacje oraz korupcje przekazywane z zewnątrz ({{T109}}, {{T302}}):
  `corruption` (trening, `train=True`) i `robustness_corruption` (ewaluacja, stosowana w kroku 3 **tylko** przy `train=False`; D-023).
- Domyślna fabryka pipeline'u w `build_dataloaders` (train / eval) korzystająca z `build_pipeline` i pliku statystyk.

### Poza zakresem (wiążące)

- Implementacje augmentacji ({{T109}}) i korupcji ({{T302}}).

### Pliki

- `src/cardioai/data/filters.py`, `src/cardioai/data/preprocessing.py` — nowe
- `src/cardioai/data/normalization.py` — zmiana (identyfikatory filtrów w `preprocessing_id`)
- `scripts/compute_norm_stats.py` — zmiana (statystyki liczone z filtrem z configu, bez normalizacji; `preprocessing_id` wariantu w nazwie i treści pliku)
- `src/cardioai/data/datamodule.py` — zmiana (domyślna fabryka)
- `tests/unit/data/test_filters.py`, `tests/unit/data/test_preprocessing.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def bandpass(x: np.ndarray, fs: int, low_hz: float, high_hz: float, order: int = 4) -> np.ndarray: ...
def notch(x: np.ndarray, fs: int, freq_hz: float, quality: float = 30.0) -> np.ndarray: ...
def resample(x: np.ndarray, fs_in: int, fs_out: int) -> np.ndarray: ...       # oś czasu = ostatnia

from cardioai.data.normalization import (       # definiowane w T107; tu tylko import
    PREPROCESSING_CODE_VERSION, preprocessing_id, preprocessing_version)

def build_pipeline(pp_cfg: PreprocessingConfig, *, sampling_rate: int, train: bool, stats: NormStats | None,
                   fs_in: int | None = None, corruption: Transform | None = None,
                   robustness_corruption: Transform | None = None,
                   physical_augs: Sequence[Transform] = (),
                   normalized_augs: Sequence[Transform] = ()) -> Compose: ...
```

Funkcja przyjmuje tylko sekcję `preprocessing` (a nie cały `RunConfig`), bo `Predictor` ({{T603}}) odtwarza ją z `bundle.json`.

Krok 3 (korupcje): przy `train=True` działa `corruption`, a `robustness_corruption` jest ignorowane z ostrzeżeniem; przy `train=False`
działa wyłącznie `robustness_corruption` (przed filtrem i normalizacją), a `corruption` oraz wszystkie augmentacje są ignorowane (D-023).

### Testy do napisania

- `test_filters.py`: zero-phase (korelacja wzajemna), tłumienie, notch przy 500 Hz, resampling (długość, energia).
- `test_preprocessing.py`: kolejność kroków (transformy-szpiedzy zapisujące wywołania), `train=False`, `preprocessing_id` dla kilku configów;
  przy `train=False` korupcja z `robustness_corruption` jest stosowana przed filtrem i normalizacją, a augmentacje nie są stosowane;
  zgodność `preprocessing_id`: plik statystyk policzony przez `compute_norm_stats.py` dla configu z filtrem ma `preprocessing_id` równy `preprocessing_id(cfg)`
  i jest akceptowany przez `Normalize` w `build_pipeline` z tym samym configiem (a dla innego wariantu filtra → `NormStatsMismatchError`).

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_filters.py tests/unit/data/test_preprocessing.py -q
```

### Wskazówki i pułapki

- `sosfiltfilt` działa wzdłuż `axis=-1` — sygnał ma kształt `[12, T]`.
- Przy 100 Hz górna częstotliwość 40 Hz jest blisko Nyquista (50 Hz) — test zbocza rób na częstotliwościach w paśmie i daleko poza nim.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T108-preprocessing-filters.md`](https://github.com/__REPO__/blob/main/tasks/T108-preprocessing-filters.md)
- Decyzja [D-010](https://github.com/__REPO__/blob/main/docs/decisions.md#d-010--kolejność-transformacji-i-konwencja-brakującego-odprowadzenia) — Kolejność transformacji i konwencja brakującego odprowadzenia
- Decyzja [D-011](https://github.com/__REPO__/blob/main/docs/decisions.md#d-011--brak-filtracji-w-wariancie-bazowym) — Brak filtracji w wariancie bazowym
- Decyzja [D-023](https://github.com/__REPO__/blob/main/docs/decisions.md#d-023--korupcja-robustness-w-build_pipeline-przy-trainfalse) — Korupcja robustness w `build_pipeline` przy `train=False`
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Kolejność kroków dokładnie jak w `docs/data_contract.md` §8; przy `train=False` augmentacje i `corruption` są ignorowane (nawet jeśli przekazane) z ostrzeżeniem, a `robustness_corruption` jest stosowane w kroku 3 (D-023).
- [ ] Filtr pasmowy 0,5–40 Hz przy 100 Hz: sinus 10 Hz zachowany (amplituda ±1%, przesunięcie fazowe 0 próbek), składowa 0,05 Hz stłumiona ≥ 20 dB.
- [ ] `notch_hz ≥ fs/2` → `ConfigError` przy budowie pipeline'u.
- [ ] `resample(x, 500, 100)` daje `[12, 1000]` dla `[12, 5000]`; kształty i float32 zachowane we wszystkich krokach.
- [ ] `preprocessing_id` rozróżnia warianty z filtrami (np. `bp0.5-40_n50`); `preprocessing_version` trafia do checkpointu ({{T204}}) i bundla ({{T601}}) — funkcja z {{T107}} jest jedynym źródłem tej wartości (T108 jej nie redefiniuje).
- [ ] Bez filtrów (`bandpass: null`) pipeline nie wywołuje żadnej funkcji z `filters.py` (D-011).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T108 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T107}} — Statystyki normalizacji z train i transformacja Normalize (tydzień 3, właściciel A)

**Odblokowuje:**

- {{T109}} — Augmentacje treningowe z rejestrem i walidacją parametrów (tydzień 4, właściciel A)
- {{T503}} — XAI — Integrated Gradients, saliency i agregacje (E11) (tydzień 8, właściciel C)
- {{T601}} — Format bundla inferencyjnego i eksport z checkpointu (tydzień 6, właściciel B)
- {{T602}} — Parsowanie i walidacja wejścia (WFDB, NPZ, CSV) (tydzień 8, właściciel A)

**Bramka G3 — Core model** (tydzień 5): ResNet1D stabilny na ≥ 3 runach; brak regresji pipeline'u danych.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T108}}, {{T109}}, {{T207}}, {{T208}}, {{T209}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T108` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t108-preprocessing-filters`; status karty `in_progress` (`python3 scripts/tasks.py set-status T108 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T108]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T108`.

W Claude Code zadanie realizuje komenda `/task T108`.
__ISSUE_BODY_EOF__
}

body_T109() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T109-augmentations.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Odtwarzalne augmentacje sygnału, włączane z configu i działające wyłącznie w treningu — w tym `lead_dropout`, kluczowy dla hipotezy H3.

| Pole | Wartość |
|---|---|
| Zadanie | **T109** — Augmentacje treningowe z rejestrem i walidacją parametrów |
| Epik | Dane (`data`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 4 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G3 — Core model |
| Eksperyment | E06 |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§8](https://github.com/__REPO__/blob/main/docs/data_contract.md#8-próbka-z-dataset-i-pipeline-transformacji) (kroki 5 i 7), [§13](https://github.com/__REPO__/blob/main/docs/data_contract.md#13-brakujące-odprowadzenia) (brakujące odprowadzenia)
- [`docs/config.md`](https://github.com/__REPO__/blob/main/docs/config.md) [§4](https://github.com/__REPO__/blob/main/docs/config.md#4-schemat-pełna-lista-kluczy) (`augmentations`), [§7](https://github.com/__REPO__/blob/main/docs/config.md#7-walidacja-parametrów-modeli-i-augmentacji) (walidacja parametrów)
- Specyfikacja §4.5 (tabela augmentacji)

## 🛠️ Szczegóły techniczne

### Zakres

| Nazwa | Przestrzeń | Parametry (domyślne) |
|---|---|---|
| `gaussian_noise` | mV | `p`, `snr_db: [20, 40]` |
| `baseline_wander` | mV | `p`, `amplitude_mv: [0.05, 0.3]`, `freq_hz: [0.05, 0.5]` |
| `amplitude_scale` | mV | `p`, `scale: [0.8, 1.2]` (wspólna dla odprowadzeń) |
| `time_shift` | mV | `p`, `max_shift_s: 0.5`, `mode: circular \| zero_pad` |
| `temporal_mask` | znorm. | `p`, `n_masks: [1, 2]`, `max_len_s: 0.5` |
| `lead_dropout` | znorm. | `p`, `min_leads: 1`, `max_leads: 2` — ustawia `lead_mask = False` |

- Rejestr z klasą parametrów Pydantic dla każdej augmentacji; `build_augmentations` dzieli je na fizyczne i znormalizowane.
- Podłączenie do domyślnej fabryki pipeline'u (`train=True`).

### Poza zakresem (wiążące)

- Korupcje z etykietami jakości ({{T302}}) — augmentacje nie zmieniają `SignalSample.quality`.

### Pliki

- `src/cardioai/data/augmentations.py` — nowy
- `src/cardioai/data/datamodule.py` — zmiana (augmentacje w fabryce train)
- `tests/unit/data/test_augmentations.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
class Augmentation(Transform, Protocol):
    stage: Literal["physical", "normalized"]
AUGMENTATIONS: Mapping[str, type[Augmentation]]
def build_augmentations(specs: Sequence[AugmentationSpec]) -> tuple[list[Transform], list[Transform]]: ...
    # (fizyczne, znormalizowane); nieznana nazwa -> ConfigError z listą dostępnych
```

### Testy do napisania

- `test_augmentations.py`: prawdopodobieństwo, determinizm, SNR, `lead_dropout` + maska, walidacja parametrów, nieznana nazwa.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_augmentations.py -q
```

### Wskazówki i pułapki

- `time_shift` w trybie `circular` przesuwa też granice uderzeń — w trybie `zero_pad` uzupełniaj zerami w mV (przed normalizacją).
- `temporal_mask` nie może zamaskować więcej niż ~10% sygnału łącznie — morfologia ma pozostać rozpoznawalna.

## 🧪 Eksperyment E06 — Lead dropout i robustness

**Cel decyzyjny:** odporność kanałowa i na zakłócenia · zadania: {{T305}}, {{T306}} · właściciel eksperymentu: B · tydzień: 7

**Hipotezy powiązane z eksperymentem:**

- H3: Lead dropout w treningu zwiększy odporność na brak odprowadzeń bez istotnego spadku na pełnym 12-lead.
- H6: Model wielozadaniowy z zadaniem jakości sygnału jest odporniejszy na artefakty.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** `lead_dropout.p ∈ {0, 0.3, 0.5}`; pełna robustness suite (`docs/reliability.md` §8) dla każdego.
- **Reguła (H3):** wariant z lead dropout przyjmujemy, gdy średni spadek przy 1 brakującym odprowadzeniu maleje co najmniej o połowę,
  a macro AUROC na pełnym 12-lead spada ≤ 0,005.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T109-augmentations.md`](https://github.com/__REPO__/blob/main/tasks/T109-augmentations.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Każda augmentacja stosowana z prawdopodobieństwem `p` (test statystyczny na 2000 losowaniach, tolerancja ±3 p.p.).
- [ ] Ten sam `rng` → identyczny wynik; kształt i float32 zachowane.
- [ ] `gaussian_noise` osiąga zadany SNR z dokładnością ±0,5 dB (moc liczona per odprowadzenie).
- [ ] `lead_dropout` wyłącza 1–2 odprowadzenia, ustawia `lead_mask=False`, a po pipeline odprowadzenia mają wartość 0.0.
- [ ] Pipeline z `train=False` nie zawiera żadnej augmentacji (test na `build_pipeline`).
- [ ] Parametry augmentacji trafiają do MLflow przez config (bez dodatkowego kodu).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T109 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T108}} — Pipeline preprocessingu, filtry zerofazowe i resampling (tydzień 4, właściciel A)

**Odblokowuje:**

- {{T207}} — ResNet1D — model główny (E03) (tydzień 4, właściciel B)
- {{T302}} — Biblioteka korupcji syntetycznych z etykietami jakości (tydzień 5, właściciel A)

**Bramka G3 — Core model** (tydzień 5): ResNet1D stabilny na ≥ 3 runach; brak regresji pipeline'u danych.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T108}}, {{T109}}, {{T207}}, {{T208}}, {{T209}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T109` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t109-augmentations`; status karty `in_progress` (`python3 scripts/tasks.py set-status T109 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T109]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T109`.

W Claude Code zadanie realizuje komenda `/task T109`.
__ISSUE_BODY_EOF__
}

body_T110() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T110-eda-report.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Potwierdzić liczebności, split i jakość danych oraz dostarczyć liczby, od których zależą dalsze decyzje
(rekordy bez etykiet, braki metadanych, częstość artefaktów, rozkład amplitud).

| Pole | Wartość |
|---|---|
| Zadanie | **T110** — EDA i raport danych (E00) |
| Epik | Dane (`data`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 3 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G1 — Data |
| Eksperyment | E00 |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§3](https://github.com/__REPO__/blob/main/docs/data_contract.md#3-kolumny-źródłowe-i-ich-obróbka), [§11](https://github.com/__REPO__/blob/main/docs/data_contract.md#11-etykiety-jakości-słabe), [§12](https://github.com/__REPO__/blob/main/docs/data_contract.md#12-metadane-cechy-pozasygnałowe), [§15](https://github.com/__REPO__/blob/main/docs/data_contract.md#15-liczby-kontrolne-i-wyniki-eda) (tabela wyników EDA do uzupełnienia)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E00)
- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§5](https://github.com/__REPO__/blob/main/docs/inference_api.md#5-walidacja-wejścia--kody) (progi amplitud do doprecyzowania)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) (EDA w tygodniu 3)

## 🛠️ Szczegóły techniczne

### Zakres

- Funkcje analityczne (czyste, zwracające ramki danych) i skrypt renderujący wykresy oraz `summary.md` + `summary.json`.
- Zawartość: liczności klas per split, kardynalność etykiet, macierz współwystępowania, rekordy bez superklasy per split,
  rozkład wieku i płci (weryfikacja kodowania płci), braki `height`/`weight`, częstość flag jakości per split i fold,
  `validated_by_human` per fold, percentyle 99 i 99,9 `|x|` per odprowadzenie (train), przykładowe 12-odprowadzeniowe wykresy po 2 rekordy na klasę (train).
- Uzupełnienie tabeli w `docs/data_contract.md` §15.

### Poza zakresem (wiążące)

- Oglądanie sygnałów z foldu 10 (test) — dla testu tylko liczności etykiet.
- Wnioski modelowe.

### Pliki

- `src/cardioai/data/eda.py` — nowy
- `scripts/eda.py` — nowy (wynik w `reports/eda/`, poza gitem)
- `docs/data_contract.md` — aktualizacja §15
- `tests/unit/data/test_eda.py` — nowy (smoke na fixture)

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def class_counts(index: pd.DataFrame) -> pd.DataFrame: ...                 # split × klasa (+ n, n_unlabeled)
def cooccurrence(index: pd.DataFrame, split: str = "train") -> pd.DataFrame: ...
def missingness(index: pd.DataFrame) -> pd.DataFrame: ...
def quality_prevalence(index: pd.DataFrame) -> pd.DataFrame: ...
def amplitude_percentiles(dataset: PTBXLDataset, q: Sequence[float] = (99.0, 99.9)) -> pd.DataFrame: ...
```

### Testy do napisania

- `test_eda.py`: funkcje analityczne na `mini_ptbxl_root` zgadzają się z `MINI_EXPECTED`; skrypt tworzy pliki wynikowe w `tmp_path`.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_eda.py -q
uv run python scripts/eda.py --config configs/base.yaml --out reports/eda
```

### Wskazówki i pułapki

- Funkcja `quality_prevalence` z tego zadania jest używana ponownie w {{T301}} — nie duplikuj jej tam.
- Wykresy generuj z `matplotlib` bez interaktywnego backendu (`Agg`), żeby skrypt działał w CI i na serwerze.

## 🧪 Eksperyment E00 — EDA i sanity checks

**Cel decyzyjny:** liczebności, split, brak przecieku · zadania: {{T104}}, T110 · właściciel eksperymentu: A · tydzień: 2–3

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Pytanie:** czy indeks odtwarza liczby z PhysioNet i czy split jest wolny od przecieku?
- **Wynik:** `reports/eda/` + uzupełnienie `docs/data_contract.md` §15.
- **Reguła:** wszystkie testy kontraktu danych ({{T104}}) zielone; różnice liczebności wyjaśnione.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T110-eda-report.md`](https://github.com/__REPO__/blob/main/tasks/T110-eda-report.md)
- Decyzja [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) — Drobne odstępstwa od specyfikacji
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] `scripts/eda.py` działa na prawdziwych danych (cache 100 Hz) w < 10 min i na fixture w < 30 s.
- [ ] Tabela w `docs/data_contract.md` §15 uzupełniona; liczby kontrolne zgodne albo różnice wyjaśnione.
- [ ] Kodowanie płci potwierdzone (udział `sex == 0` vs 52% mężczyzn z opisu zbioru) i zapisane w §15.
- [ ] Proponowane progi `AMPLITUDE_HIGH` i `UNITS_SUSPECT` wynikające z percentyli zapisane w PR (decyzję o progach podejmuje A w {{T602}} po konsultacji z C).
- [ ] Brak wykresów sygnałów z foldu 10.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T110 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T103}} — Indeks etykiet i splitów (parquet + meta) (tydzień 2, właściciel A)
- {{T105}} — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu (tydzień 2, właściciel A)
- {{T106}} — Cache sygnałów NPY z dostępem memmap (tydzień 3, właściciel A)

**Odblokowuje:**

- {{T301}} — Słabe etykiety jakości w Dataset i analiza ich wiarygodności (tydzień 5, właściciel A)

**Bramka G1 — Data** (tydzień 3): split i liczebności odtworzone; zero przecieku pacjentów; loader przetestowany.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T001}}, {{T002}}, {{T003}}, {{T004}}, {{T005}}, {{T101}}, {{T102}}, {{T103}}, {{T104}}, {{T105}}, {{T106}}, {{T107}}, {{T110}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T110` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t110-eda-report`; status karty `in_progress` (`python3 scripts/tasks.py set-status T110 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T110]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T110`.

W Claude Code zadanie realizuje komenda `/task T110`.
__ISSUE_BODY_EOF__
}

body_T201() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T201-metrics-thresholds.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Jedna, przetestowana implementacja wszystkich metryk klasyfikacji i kalibracji, używana przez trening, ewaluację, niezawodność i raporty.

| Pole | Wartość |
|---|---|
| Zadanie | **T201** — Moduł metryk i doboru progów |
| Epik | Modele i trening (`training`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 2 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G2 — Baseline |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/evaluation.md`](https://github.com/__REPO__/blob/main/docs/evaluation.md) [§1](https://github.com/__REPO__/blob/main/docs/evaluation.md#1-zasady-ewaluacji) (zasady), [§2](https://github.com/__REPO__/blob/main/docs/evaluation.md#2-metryki-klasyfikacji--definicje) (definicje), [§3](https://github.com/__REPO__/blob/main/docs/evaluation.md#3-progi-decyzyjne) (progi), [§5](https://github.com/__REPO__/blob/main/docs/evaluation.md#5-plik-metryk) (plik metryk)
- [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§3](https://github.com/__REPO__/blob/main/docs/mlops.md#3-parametry-metryki-artefakty) (nazwy metryk w MLflow)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-029](https://github.com/__REPO__/blob/main/docs/decisions.md#d-029--nazwy-metryk-mlflow-i-zestaw-metryk-progowych), [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) (metryki bez `torchmetrics`)

## 🛠️ Szczegóły techniczne

### Zakres

- Metryki z `docs/evaluation.md` §2 (AUROC macro/micro/per klasa, AP, F1, czułość, swoistość, TP/FP/FN/TN, Brier, ECE klasowe, Hamming loss).
- Dobór progów `f1` / `youden` / `fixed` według §3 (siatka 0,01–0,99, remis → bliżej 0,5) i ich stosowanie.
- Spłaszczanie słownika metryk do kluczy MLflow (`val/macro_auroc`, `val/auroc_MI`, …), w tym `val/hamming_loss`, `val/f1_<KLASA>_tuned`, `val/sensitivity_<KLASA>`,
  `val/specificity_<KLASA>`, `val/macro_f1_tuned` (D-029); nazwy tylko ze znaków `[A-Za-z0-9_./-]`.
- Obsługa przypadków brzegowych (klasa bez pozytywów lub negatywów → `NaN` + ostrzeżenie).

### Poza zakresem (wiążące)

- Bootstrap ({{T209}}), krzywe risk–coverage ({{T502}}), wykresy kalibracji ({{T501}}).

### Pliki

- `src/cardioai/evaluation/__init__.py`, `metrics.py`, `thresholds.py` — nowe
- `tests/unit/evaluation/test_metrics.py`, `test_thresholds.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def classification_metrics(y_true: np.ndarray, y_prob: np.ndarray, *,
                           thresholds: Mapping[str, float] | None = None,
                           class_names: Sequence[str] = SUPERCLASSES, ece_bins: int = 15) -> dict[str, Any]: ...
    # struktura jak docs/evaluation.md §5 (bez pól run_id/checkpoint)
def per_class_auroc(y_true: np.ndarray, y_prob: np.ndarray) -> np.ndarray: ...
def expected_calibration_error(y_true: np.ndarray, y_prob: np.ndarray, n_bins: int = 15) -> float: ...  # 1D, binarnie
def brier_per_class(y_true: np.ndarray, y_prob: np.ndarray) -> np.ndarray: ...
def tune_thresholds(y_true: np.ndarray, y_prob: np.ndarray, *, method: Literal["f1", "youden", "fixed"] = "f1",
                    fixed: float = 0.5, class_names: Sequence[str] = SUPERCLASSES) -> dict[str, float]: ...
def apply_thresholds(y_prob: np.ndarray, thresholds: Mapping[str, float],
                     class_names: Sequence[str] = SUPERCLASSES) -> np.ndarray: ...   # int8 [N, C]
def metrics_to_flat(metrics: Mapping[str, Any], prefix: str) -> dict[str, float]: ...  # klucze z docs/mlops.md §3
```

### Testy do napisania

- `test_metrics.py`: porównania ze sklearn, ECE, Brier, przypadki brzegowe, kształty wejścia (N×5), typy wyjścia.
- `test_thresholds.py`: `f1`, `youden`, `fixed`, remisy, `apply_thresholds`.

### Weryfikacja

```bash
uv run pytest tests/unit/evaluation -q
uv run lint-imports
```

### Wskazówki i pułapki

- `roc_auc_score(..., average="macro")` zgłasza wyjątek, gdy któraś klasa ma jedną wartość etykiety — licz per klasa i uśredniaj ręcznie z obsługą `NaN`.
- Tę samą implementację ECE użyje kalibracja ({{T501}}) — nie twórz drugiej.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T201-metrics-thresholds.md`](https://github.com/__REPO__/blob/main/tasks/T201-metrics-thresholds.md)
- Decyzja [D-029](https://github.com/__REPO__/blob/main/docs/decisions.md#d-029--nazwy-metryk-mlflow-i-zestaw-metryk-progowych) — Nazwy metryk MLflow i zestaw metryk progowych
- Decyzja [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) — Drobne odstępstwa od specyfikacji
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Wyniki zgodne z scikit-learn (tolerancja 1e-9) na losowych danych dla wszystkich metryk z odpowiednikiem w sklearn.
- [ ] ECE: idealnie skalibrowane dane syntetyczne (N = 200 000) → ECE < 0,01; stała predykcja 0,5 przy częstości 0,2 → ECE ≈ 0,3.
- [ ] Remis w doborze progu rozstrzygany na korzyść progu bliższego 0,5 (test).
- [ ] Klasa bez pozytywów → `NaN` w metrykach tej klasy, macro liczone z pominięciem `NaN`, ostrzeżenie w logu.
- [ ] `metrics_to_flat` produkuje dokładnie klucze z `docs/mlops.md` §3 (test na liście oczekiwanych kluczy; każdy klucz pasuje do `[A-Za-z0-9_./-]+`).
- [ ] Moduł nie importuje `torch` ani pakietów `cardioai.models` / `cardioai.training`.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T201 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T001}} — Szkielet repozytorium, pyproject i narzędzia jakości (tydzień 1, właściciel C)

**Odblokowuje:**

- {{T203}} — Baseline klasyczny na cechach sygnałowych (E01) (tydzień 3, właściciel C)
- {{T204}} — Pętla treningowa, straty, checkpointy i scripts/train.py (tydzień 3, właściciel B)
- {{T501}} — Kalibracja prawdopodobieństw i diagramy niezawodności (E09) (tydzień 10, właściciel C)

**Bramka G2 — Baseline** (tydzień 3–4): model uczy się sensownego sygnału; metryki > losowe; pipeline MLflow działa (doprecyzowanie: macro AUROC val ≥ 0,80, E02).

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T201}}, {{T202}}, {{T203}}, {{T204}}, {{T205}}, {{T206}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T201` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t201-metrics-thresholds`; status karty `in_progress` (`python3 scripts/tasks.py set-status T201 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(evaluation): <description> [T201]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T201`.

W Claude Code zadanie realizuje komenda `/task T201`.
__ISSUE_BODY_EOF__
}

body_T202() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T202-model-interface.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Wspólny kontrakt dla wszystkich architektur: każdy enkoder rejestruje się raz, a trening, ewaluacja, XAI i bundle
pracują z jednym typem `ECGModel` i jednym typem wyjścia `ModelOutput`.

| Pole | Wartość |
|---|---|
| Zadanie | **T202** — Interfejs modeli, rejestr enkoderów, głowy i narzędzia |
| Epik | Modele i trening (`training`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 2 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G2 — Baseline |
| Eksperyment | — |
| Właściciel | B (Model & Experiments) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§1](https://github.com/__REPO__/blob/main/docs/modeling.md#1-interfejs-modelu) (interfejs), [§2](https://github.com/__REPO__/blob/main/docs/modeling.md#2-rejestr-i-budowanie-modelu) (rejestr), [§4](https://github.com/__REPO__/blob/main/docs/modeling.md#4-głowy-i-fuzja-metadanych) (głowy), [§9](https://github.com/__REPO__/blob/main/docs/modeling.md#9-porównywalność-architektur) (porównywalność)
- [`docs/config.md`](https://github.com/__REPO__/blob/main/docs/config.md) [§7](https://github.com/__REPO__/blob/main/docs/config.md#7-walidacja-parametrów-modeli-i-augmentacji) (walidacja `model.params`)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§3](https://github.com/__REPO__/blob/main/AGENTS.md#3-mapa-repozytorium) (models nie importuje data ani training)

## 🛠️ Szczegóły techniczne

### Zakres

- `ModelOutput`, bazowy `Encoder`, `ECGModel` (enkoder + głowy + opcjonalna gałąź metadanych i fuzja — tu tylko punkty zaczepienia, implementacja fuzji w {{T402}}).
- Rejestr enkoderów z klasą `Params` (Pydantic, `extra="forbid"`), `build_model`, `list_encoders`.
- `MultiTaskHeads` (diagnoza zawsze; jakość i aux opcjonalnie).
- `count_parameters`, `estimate_flops` (`torch.utils.flop_counter.FlopCounterMode`).
- Minimalny enkoder `debug_linear` (średnia po czasie → `Linear(12, 16)`) zarejestrowany na stałe — używany przez `e00_smoke.yaml`
  i testy integracyjne, zanim powstaną prawdziwe architektury.

### Poza zakresem (wiążące)

- Konkretne architektury ({{T205}}, {{T207}}, {{T401}}), fuzja metadanych ({{T402}}).

### Pliki

- `src/cardioai/models/__init__.py`, `base.py`, `registry.py`, `heads.py`, `utils.py`, `debug.py` — nowe
- `tests/unit/models/test_registry.py`, `test_heads.py`, `test_utils.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
# docs/modeling.md §1 — ModelOutput, Encoder, ECGModel
def register_encoder(name: str, *, params: type[BaseModel]) -> Callable[[type[Encoder]], type[Encoder]]: ...
def build_model(model_cfg: ModelConfig, *, n_samples: int, n_leads: int = 12,
                aux_sizes: Mapping[str, int] | None = None, n_metadata: int = 0) -> ECGModel: ...
def list_encoders() -> list[str]: ...

class MultiTaskHeads(nn.Module):
    def __init__(self, in_dim: int, *, n_classes: int = 5, quality: bool = False,
                 aux: Mapping[str, int] | None = None, dropout: float = 0.0) -> None: ...
    def forward(self, z: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor | None, dict[str, torch.Tensor]]: ...

def count_parameters(model: nn.Module, trainable_only: bool = True) -> int: ...
def estimate_flops(model: nn.Module, input_shape: tuple[int, int, int]) -> int: ...
class UnknownModelError(KeyError): ...
```

### Testy do napisania

- `test_registry.py`: rejestracja, duplikaty, walidacja `Params`, `build_model` z enkoderem testowym.
- `test_heads.py`: kształty wyjść, wyłączanie głów, dropout.
- `test_utils.py`: liczenie parametrów i FLOPs.

### Weryfikacja

```bash
uv run pytest tests/unit/models -q
uv run lint-imports
```

### Wskazówki i pułapki

- `ModelOutput` jako `dataclass` nie przechodzi przez eksport ONNX/TorchScript — wrappery eksportowe zwracają krotki ({{T703}}).
- Rejestr wypełnia się przy imporcie modułów — `cardioai/models/__init__.py` importuje wszystkie moduły enkoderów.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T202-model-interface.md`](https://github.com/__REPO__/blob/main/tasks/T202-model-interface.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] Rejestracja dwóch enkoderów o tej samej nazwie → błąd; nieznana nazwa → `UnknownModelError` z listą dostępnych.
- [ ] Błędny klucz w `model.params` → błąd walidacji z nazwą parametru, przed zbudowaniem sieci.
- [ ] `ECGModel` z enkoderem testowym zwraca `logits [B, 5]`, `quality_logits [B, 4]` (gdy włączone) i `aux_logits` zgodne z `aux_sizes`.
- [ ] `meta` przekazane do modelu bez gałęzi metadanych → jednorazowe ostrzeżenie, wynik bez zmian.
- [ ] `estimate_flops` > 0 dla enkodera konwolucyjnego; `count_parameters` zgodne z ręcznym policzeniem dla małej sieci.
- [ ] `lint-imports` potwierdza brak importów `cardioai.data` i `cardioai.training`.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T202 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T002}} — System konfiguracji (YAML + Pydantic, extends, --set, config_hash) (tydzień 1, właściciel B)
- {{T003}} — Device, seed, AMP, git i informacje o środowisku (tydzień 1, właściciel B)

**Odblokowuje:**

- {{T204}} — Pętla treningowa, straty, checkpointy i scripts/train.py (tydzień 3, właściciel B)

**Bramka G2 — Baseline** (tydzień 3–4): model uczy się sensownego sygnału; metryki > losowe; pipeline MLflow działa (doprecyzowanie: macro AUROC val ≥ 0,80, E02).

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T201}}, {{T202}}, {{T203}}, {{T204}}, {{T205}}, {{T206}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T202` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t202-model-interface`; status karty `in_progress` (`python3 scripts/tasks.py set-status T202 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(models): <description> [T202]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T202`.

W Claude Code zadanie realizuje komenda `/task T202`.
__ISSUE_BODY_EOF__
}

body_T203() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T203-classical-baseline.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Szybki, niezależny od sieci neuronowych sanity check etykiet, splitu i metryk. Jego wynik to dolny punkt odniesienia dla modeli głębokich.

| Pole | Wartość |
|---|---|
| Zadanie | **T203** — Baseline klasyczny na cechach sygnałowych (E01) |
| Epik | Modele i trening (`training`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 3 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G2 — Baseline |
| Eksperyment | E01 |
| Właściciel | C (Reliability & Product) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E01)
- [`docs/evaluation.md`](https://github.com/__REPO__/blob/main/docs/evaluation.md) [§2](https://github.com/__REPO__/blob/main/docs/evaluation.md#2-metryki-klasyfikacji--definicje), [§4](https://github.com/__REPO__/blob/main/docs/evaluation.md#4-plik-predykcji) (plik predykcji)
- Specyfikacja §5.1

## 🛠️ Szczegóły techniczne

### Zakres

- Cechy (z surowych mV, per odprowadzenie): średnia, odchylenie, min, max, percentyle (1, 5, 50, 95, 99), skośność, kurtoza, RMS,
  częstość przejść przez zero, względna moc w pasmach 0,5–5 / 5–15 / 15–40 Hz (Welch); globalnie: tętno i odchylenie RR z odprowadzenia II (`find_peaks`).
- Model: `StandardScaler` + `OneVsRestClassifier(LogisticRegression(max_iter=2000))` dopasowany na train; opcjonalnie LightGBM (extra `lgbm`).
  Dopasowanie i predykcja (logity) to czyste funkcje na tablicach NumPy w `cardioai.evaluation.classical` — `scripts/train_classical.py` tylko ładuje dane, wywołuje je i loguje wyniki (skrypt pozostaje cienki).
- Ewaluacja na val: metryki ({{T201}}), plik predykcji (logity = log-odds z `predict_proba`, przycięte), log do MLflow.
- Config `configs/experiment/e01_classical.yaml` (`model.name: classical_logreg`, parametry w `model.params`).

### Poza zakresem (wiążące)

- Strojenie hiperparametrów poza `C ∈ {0.1, 1, 10}`.

### Pliki

- `src/cardioai/data/features.py` — nowy
- `src/cardioai/evaluation/classical.py` — nowy (dopasowanie i predykcja na tablicach NumPy)
- `scripts/train_classical.py` — nowy
- `configs/experiment/e01_classical.yaml` — nowy
- `tests/unit/data/test_features.py`, `tests/unit/evaluation/test_classical.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
FEATURE_NAMES: tuple[str, ...]                                   # stała kolejność cech
def extract_features(x: np.ndarray, fs: int) -> np.ndarray: ...  # [12, T] mV -> [F] float32
def extract_feature_matrix(dataset: PTBXLDataset) -> tuple[np.ndarray, np.ndarray, np.ndarray]: ...  # X, y, ecg_id
```

### Testy do napisania

- `test_features.py`: kształt i kolejność cech, sygnał płaski, sinus o znanej częstotliwości (moc w paśmie), tętno z syntetycznego EKG fixture'a.
- `test_classical.py`: dopasowanie scalera i modelu wyłącznie na przekazanych wierszach (train), kształt i skończoność logitów na danych syntetycznych.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_features.py tests/unit/evaluation/test_classical.py -q
uv run python scripts/train_classical.py --config configs/experiment/e01_classical.yaml
```

### Wskazówki i pułapki

- `scripts/train_classical.py` nie używa `build_model` — `model.name` służy tylko do nazwy runu.
- Ekstrakcję cech równoległą przez `joblib` rób tylko w skrypcie; funkcje w `features.py` mają być czyste.

## 🧪 Eksperyment E01 — Baseline klasyczny

**Cel decyzyjny:** weryfikacja etykiet i metryk · zadania: T203 · właściciel eksperymentu: C · tydzień: 3

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** cechy statystyczne i widmowe + regresja logistyczna (one-vs-rest); opcjonalnie LightGBM.
- **Stałe:** 100 Hz, val = fold 9.
- **Reguła:** macro AUROC val > 0,70 (sanity); niższy wynik → przegląd etykiet i splitu przed dalszą pracą.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T203-classical-baseline.md`](https://github.com/__REPO__/blob/main/tasks/T203-classical-baseline.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] macro AUROC na val > 0,70 (sanity); niższy wynik → przegląd etykiet i splitu przed dalszą pracą (komentarz w PR).
- [ ] Scaler i model dopasowane wyłącznie na train (test sprawdza, że funkcja dopasowania dostaje tylko wiersze train).
- [ ] Run w MLflow z tagami (`exp_id=E01`), metrykami `val/...` i artefaktem `eval/val/predictions_val.parquet` w formacie `docs/evaluation.md` §4.
- [ ] Cechy deterministyczne; brak NaN (odprowadzenie płaskie → wartości skończone).
- [ ] Czas na CPU < 15 min dla 100 Hz (podany w PR).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T203 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T004}} — MLflow — serwer zespołowy i warstwa trackingu (tydzień 1, właściciel C)
- {{T105}} — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu (tydzień 2, właściciel A)
- {{T201}} — Moduł metryk i doboru progów (tydzień 2, właściciel C)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka G2 — Baseline** (tydzień 3–4): model uczy się sensownego sygnału; metryki > losowe; pipeline MLflow działa (doprecyzowanie: macro AUROC val ≥ 0,80, E02).

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T201}}, {{T202}}, {{T203}}, {{T204}}, {{T205}}, {{T206}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T203` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t203-classical-baseline`; status karty `in_progress` (`python3 scripts/tasks.py set-status T203 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T203]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T203`.

W Claude Code zadanie realizuje komenda `/task T203`.
__ISSUE_BODY_EOF__
}

body_T204() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T204-trainer.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Jedna pętla treningowa dla wszystkich architektur, uruchamiana z configu, odporna na różnice urządzeń, z checkpointami
i pełnym logowaniem do MLflow. Rozmiar L: **najpierw plan do akceptacji**.

| Pole | Wartość |
|---|---|
| Zadanie | **T204** — Pętla treningowa, straty, checkpointy i scripts/train.py |
| Epik | Modele i trening (`training`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 3 z 14 |
| Rozmiar | L (3+ osobodni) — zacznij od planu do akceptacji (`AGENTS.md` §6 pkt 3), rozważ podział |
| Bramka | G2 — Baseline |
| Eksperyment | — |
| Właściciel | B (Model & Experiments) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§5](https://github.com/__REPO__/blob/main/docs/modeling.md#5-funkcje-straty) (straty), [§6](https://github.com/__REPO__/blob/main/docs/modeling.md#6-checkpoint--format) (checkpoint), [§7](https://github.com/__REPO__/blob/main/docs/modeling.md#7-protokół-treningu) (protokół), [§8](https://github.com/__REPO__/blob/main/docs/modeling.md#8-amp-urządzenia-determinizm) (AMP, urządzenia)
- [`docs/config.md`](https://github.com/__REPO__/blob/main/docs/config.md) [§4](https://github.com/__REPO__/blob/main/docs/config.md#4-schemat-pełna-lista-kluczy) (`training`), [§6](https://github.com/__REPO__/blob/main/docs/config.md#6-hash-configu-i-nazwy-runów) (nazwy runów, katalog lokalny)
- [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§2](https://github.com/__REPO__/blob/main/docs/mlops.md#2-konwencje-eksperymenty-runy-tagi), [§3](https://github.com/__REPO__/blob/main/docs/mlops.md#3-parametry-metryki-artefakty) (tagi, metryki, artefakty)
- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§8](https://github.com/__REPO__/blob/main/docs/data_contract.md#8-próbka-z-dataset-i-pipeline-transformacji) (próbka, `EpochAwareSampler`)

## 🛠️ Szczegóły techniczne

### Zakres

- `MultiTaskLoss`: `L_diag` (BCE), `L_quality`, `L_aux` z wagami `lambda_*` i składowymi w logach. (`pos_weight` i focal — {{T208}}; tu przyjmij parametr `pos_weight=None`.)
- `build_optimizer` (AdamW, bez weight decay dla biasów i normalizacji), `build_scheduler` (cosine z rozgrzewką, plateau, brak).
- `predict_loader` (wspólna pętla predykcji dla walidacji, ewaluacji i robustness).
- `Trainer.fit`: AMP przez `autocast_context`, akumulacja gradientów, przycinanie normy, walidacja co epokę z metrykami {{T201}},
  early stopping, `best.pt` i `last.pt`, wznawianie (`--resume`), `set_epoch` samplera, logowanie do MLflow (w tym `peak_memory_mb` — na CUDA z `torch.cuda.max_memory_allocated`, na pozostałych urządzeniach pomijane).
- Punkt rozszerzeń `metric_hooks: Sequence[MetricHook]` w konstruktorze `Trainer`: hooki wywoływane po walidacji każdej epoki, ich metryki trafiają do `history` i MLflow
  (korzystają z niego {{T303}} — metryki jakości i {{T403}} — metryki głów aux, bez zmian w `trainer.py`).
- `scripts/train.py`: `--config`, `--set`, `--resume`, `--output-dir`, `--no-tracking`; na końcu JSON z `best_metric`, ścieżką checkpointu i `run_id`.

### Poza zakresem (wiążące)

- `pos_weight`, focal ({{T208}}), metryki jakości ({{T303}}), multi-seed ({{T209}}), konkretne architektury ({{T205}}, {{T207}}).

### Pliki

- `src/cardioai/training/__init__.py`, `trainer.py`, `losses.py`, `optim.py`, `checkpoint.py`, `predict.py` — nowe
- `scripts/train.py` — nowy
- `tests/unit/training/test_losses.py`, `test_optim.py`, `test_checkpoint.py`, `test_trainer.py` — nowe
- `tests/integration/test_train_smoke.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
class MultiTaskLoss(nn.Module):
    def forward(self, out: ModelOutput, batch: Mapping[str, Any]) -> tuple[torch.Tensor, dict[str, float]]: ...
def build_loss(cfg: TrainingConfig, *, pos_weight: torch.Tensor | None = None) -> MultiTaskLoss: ...
def build_optimizer(model: nn.Module, cfg: OptimizerConfig) -> torch.optim.Optimizer: ...
def build_scheduler(optimizer: torch.optim.Optimizer, cfg: SchedulerConfig, *, steps_per_epoch: int,
                    epochs: int) -> Any | None: ...
def save_checkpoint(path: Path, payload: Mapping[str, Any]) -> None: ...          # format docs/modeling.md §6
def load_checkpoint(path: Path, *, map_location: str | torch.device = "cpu") -> dict[str, Any]: ...  # weights_only=True

@dataclass
class PredictionArrays:
    ecg_id: np.ndarray; patient_id: np.ndarray; fold: np.ndarray; y: np.ndarray
    logits: np.ndarray; quality_logits: np.ndarray | None; y_quality: np.ndarray | None
def predict_loader(model: nn.Module, loader: DataLoader, device: torch.device, *, amp: bool = False) -> PredictionArrays: ...

@dataclass
class FitResult:
    best_metric: float; best_epoch: int; best_checkpoint: Path; last_checkpoint: Path
    history: list[dict[str, float]]; run_id: str | None
class MetricHook(Protocol):
    def __call__(self, *, epoch: int, model: nn.Module, device: torch.device,
                 val_predictions: PredictionArrays, val_loader: DataLoader) -> dict[str, float]: ...
    # zwraca metryki z kluczami według docs/mlops.md §3 (np. "val/quality_auroc_static_noise"); logowane bez zmian
class Trainer:
    def __init__(self, cfg: RunConfig, model: ECGModel, loss_fn: MultiTaskLoss, *, device: torch.device,
                 output_dir: Path, metric_hooks: Sequence[MetricHook] = ()) -> None: ...
    def fit(self, train_loader: DataLoader, val_loader: DataLoader, *, resume_from: Path | None = None) -> FitResult: ...
```

### Testy do napisania

- `test_losses.py`: składowe i wagi, maskowanie brakujących głów.
- `test_optim.py`: grupy parametrów bez weight decay, harmonogram cosine z rozgrzewką.
- `test_checkpoint.py`: round-trip, `weights_only=True`, brak typów niedozwolonych.
- `test_trainer.py`: przeuczenie, early stopping (w tym monitor `NaN`), wznowienie, akumulacja, `metric_hooks` (hook-atrapa dodaje metrykę do `history`).
- `tests/integration/test_train_smoke.py`: fixture → indeks → statystyki → `train.py` (bez MLflow albo z tymczasowym URI).

### Weryfikacja

```bash
uv run pytest tests/unit/training tests/integration/test_train_smoke.py -q
uv run python scripts/train.py --config configs/experiment/e00_smoke.yaml --set data.root=<ścieżka do mini_ptbxl>
```

Uwaga: `--set data.root=...` ma pierwszeństwo nad `CARDIOAI_DATA_ROOT` (`docs/config.md` §1 pkt 4). Bez `--set` zmienna z `.env` wskazująca prawdziwy PTB-XL nadpisze `data.root`
z YAML — do testów na `mini_ptbxl_root` użyj `--set` albo ustaw `CARDIOAI_DATA_ROOT` na fixture.

### Wskazówki i pułapki

- Metryki walidacyjne licz na całym splicie po zebraniu predykcji, nie średnią z batchy.
- `GradScaler` + przycinanie normy: najpierw `scaler.unscale_(optimizer)`, potem `clip_grad_norm_`.
- Nie zapisuj w checkpoincie obiektów `Path`, dataclass ani tablic NumPy — konwertuj do typów prostych (D-013).

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T204-trainer.md`](https://github.com/__REPO__/blob/main/tasks/T204-trainer.md)
- Decyzja [D-013](https://github.com/__REPO__/blob/main/docs/decisions.md#d-013--checkpoint-ładowany-z-weights_onlytrue) — Checkpoint ładowany z `weights_only=True`
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** L (3+ osobodni) — zacznij od planu do akceptacji (`AGENTS.md` §6 pkt 3), rozważ podział

## ✅ Kryteria akceptacji

- [ ] Przeuczenie małego modelu na 16 próbkach: strata spada o ≥ 50% w 50 krokach (CPU).
- [ ] Checkpoint: zapis → `torch.load(weights_only=True)` → identyczne wyjścia modelu; zawiera wszystkie pola z `docs/modeling.md` §6 (w tym `preprocessing.version`, której źródłem jest `preprocessing_version` z {{T107}}).
- [ ] Early stopping zatrzymuje trening po `patience` epokach bez poprawy; `best.pt` odpowiada najlepszemu `val/macro_auroc`.
- [ ] Wartość `NaN` monitorowanej metryki liczy się jako brak poprawy i wywołuje ostrzeżenie w logu; `best.pt` jest zapisany co najmniej po pierwszej epoce (także gdy monitor jest `NaN`).
- [ ] `metric_hooks`: metryki zwrócone przez hook trafiają do `history` i do MLflow; wyjątek z hooka nie jest połykany.
- [ ] MLflow: na CUDA logowane jest `peak_memory_mb` (`docs/mlops.md` §3); na CPU i MPS metryka jest pomijana.
- [ ] Wznowienie z `last.pt` kontynuuje numerację epok; na CPU dalsze metryki identyczne jak w treningu bez przerwy.
- [ ] Akumulacja: `grad_accum_steps=2, batch=4` daje gradienty zgodne z `batch=8` (tolerancja 1e-5, bez BatchNorm w modelu testowym).
- [ ] `amp: true` na CPU/MPS → informacja w logu i trening w float32; na CUDA → fp16 + `GradScaler`.
- [ ] MLflow: metryki `train/...`, `val/...`, `lr`, `epoch_time_s` z `docs/mlops.md` §3; artefakty `config/resolved.yaml`, `env/env_info.json`, `checkpoints/best.pt`.
- [ ] `scripts/train.py` z `e00_smoke.yaml` na `mini_ptbxl_root` kończy się w < 60 s (test integracyjny).
- [ ] Pętla działa z `num_workers > 0` na Windows (`if __name__ == "__main__":` w skrypcie).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T204 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T004}} — MLflow — serwer zespołowy i warstwa trackingu (tydzień 1, właściciel C)
- {{T105}} — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu (tydzień 2, właściciel A)
- {{T107}} — Statystyki normalizacji z train i transformacja Normalize (tydzień 3, właściciel A)
- {{T201}} — Moduł metryk i doboru progów (tydzień 2, właściciel C)
- {{T202}} — Interfejs modeli, rejestr enkoderów, głowy i narzędzia (tydzień 2, właściciel B)

**Odblokowuje:**

- {{T205}} — Płytki CNN 1D i pierwszy run end-to-end (E02) (tydzień 3, właściciel B)
- {{T206}} — Ewaluacja checkpointu, pliki predykcji i metryk (tydzień 4, właściciel B)

**Bramka G2 — Baseline** (tydzień 3–4): model uczy się sensownego sygnału; metryki > losowe; pipeline MLflow działa (doprecyzowanie: macro AUROC val ≥ 0,80, E02).

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T201}}, {{T202}}, {{T203}}, {{T204}}, {{T205}}, {{T206}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T204` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy) i **poczekaj na jego akceptację** (rozmiar L).
4. Gałąź: `t204-trainer`; status karty `in_progress` (`python3 scripts/tasks.py set-status T204 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(training): <description> [T204]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T204`.

W Claude Code zadanie realizuje komenda `/task T204`.
__ISSUE_BODY_EOF__
}

body_T205() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T205-cnn-baseline.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Pierwszy model głęboki przechodzący cały pipeline na prawdziwych danych — dowód, że dane, trening, metryki i MLflow działają razem.

| Pole | Wartość |
|---|---|
| Zadanie | **T205** — Płytki CNN 1D i pierwszy run end-to-end (E02) |
| Epik | Modele i trening (`training`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 3 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G2 — Baseline |
| Eksperyment | E02 |
| Właściciel | B (Model & Experiments) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§3.1](https://github.com/__REPO__/blob/main/docs/modeling.md#31-cnn_small--płytki-cnn-1d-baseline-e02) (architektura `cnn_small`)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E02)
- [`tasks/README.md`](https://github.com/__REPO__/blob/main/tasks/README.md) [§5](https://github.com/__REPO__/blob/main/tasks/README.md#5-bramki-jakościowe-g1g6) (bramka G2)

## 🛠️ Szczegóły techniczne

### Zakres

- Enkoder `cnn_small` zarejestrowany w rejestrze (4 bloki `Conv1d(k=7) → BN → ReLU → MaxPool(2)`, szerokości `[32, 64, 128, 128]`, GAP).
- `configs/model/cnn_small.yaml`, `configs/experiment/e02_cnn_small.yaml` (100 Hz, bez augmentacji, 30 epok).
- Trening na prawdziwych danych (seed 0) i zapis wyniku w PR.

### Poza zakresem (wiążące)

- Strojenie hiperparametrów; ResNet1D ({{T207}}).

### Pliki

- `src/cardioai/models/cnn.py` — nowy
- `configs/model/cnn_small.yaml`, `configs/experiment/e02_cnn_small.yaml` — nowe
- `tests/unit/models/test_cnn.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
class CNNSmallParams(BaseModel):
    widths: list[int] = [32, 64, 128, 128]
    kernel_size: int = 7
    dropout: float = 0.1
@register_encoder("cnn_small", params=CNNSmallParams)
class CNNSmallEncoder(Encoder): ...
```

### Testy do napisania

- `test_cnn.py`: kształty, gradient dociera do pierwszej warstwy, deterministyczny forward w `eval()`.

### Weryfikacja

```bash
uv run pytest tests/unit/models/test_cnn.py -q
uv run python scripts/train.py --config configs/experiment/e02_cnn_small.yaml
```

### Wskazówki i pułapki

- Jeśli AUROC utknie na ~0,5: sprawdź kolejność etykiet, normalizację (statystyki z train) i czy `y` nie jest przesunięte względem `x`.

## 🧪 Eksperyment E02 — Mały CNN 1D

**Cel decyzyjny:** pierwszy end-to-end deep baseline · zadania: T205 · właściciel eksperymentu: B · tydzień: 3

**Hipotezy powiązane z eksperymentem:**

- H1: Residual 1D (ResNet1D) osiągnie wyższą jakość i stabilność niż płytki CNN przy akceptowalnym koszcie inferencji.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** `cnn_small`, 1 seed (3 seedy do tabeli H1).
- **Reguła:** macro AUROC val ≥ 0,80 i pipeline MLflow kompletny → bramka G2.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T205-cnn-baseline.md`](https://github.com/__REPO__/blob/main/tasks/T205-cnn-baseline.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] Forward dla `[2, 12, 1000]` i `[2, 12, 5000]` działa; `out_dim = widths[-1]`.
- [ ] Run na prawdziwych danych w MLflow (`exp_id=E02`): macro AUROC val ≥ 0,80.
- [ ] Liczba parametrów i MFLOPs zalogowane jako parametry runu.
- [ ] Bramka G2 (wspólnie z {{T206}}): zespół potwierdza, że model uczy się sensownie (krzywe strat, AUROC per klasa > 0,5).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T205 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T204}} — Pętla treningowa, straty, checkpointy i scripts/train.py (tydzień 3, właściciel B)

**Odblokowuje:**

- {{T207}} — ResNet1D — model główny (E03) (tydzień 4, właściciel B)

**Bramka G2 — Baseline** (tydzień 3–4): model uczy się sensownego sygnału; metryki > losowe; pipeline MLflow działa (doprecyzowanie: macro AUROC val ≥ 0,80, E02).

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T201}}, {{T202}}, {{T203}}, {{T204}}, {{T205}}, {{T206}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T205` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t205-cnn-baseline`; status karty `in_progress` (`python3 scripts/tasks.py set-status T205 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(models): <description> [T205]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T205`.

W Claude Code zadanie realizuje komenda `/task T205`.
__ISSUE_BODY_EOF__
}

body_T206() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T206-evaluate-predictions.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Standardowy plik predykcji i metryk dla dowolnego checkpointu — wejście dla progów, kalibracji, quality gate, abstention,
robustness i raportów. Bez tego każda analiza liczyłaby predykcje po swojemu.

| Pole | Wartość |
|---|---|
| Zadanie | **T206** — Ewaluacja checkpointu, pliki predykcji i metryk |
| Epik | Modele i trening (`training`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 4 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G2 — Baseline |
| Eksperyment | — |
| Właściciel | B (Model & Experiments) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/evaluation.md`](https://github.com/__REPO__/blob/main/docs/evaluation.md) [§3](https://github.com/__REPO__/blob/main/docs/evaluation.md#3-progi-decyzyjne) (progi), [§4](https://github.com/__REPO__/blob/main/docs/evaluation.md#4-plik-predykcji) (plik predykcji), [§5](https://github.com/__REPO__/blob/main/docs/evaluation.md#5-plik-metryk) (plik metryk), [§7](https://github.com/__REPO__/blob/main/docs/evaluation.md#7-blokada-testu-i-protokół-finalny) (blokada testu)
- [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§2](https://github.com/__REPO__/blob/main/docs/mlops.md#2-konwencje-eksperymenty-runy-tagi), [§3](https://github.com/__REPO__/blob/main/docs/mlops.md#3-parametry-metryki-artefakty) (logowanie do runu treningowego, artefakty `eval/<split>/`)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E08 — podgrupy używane przez `subgroup_metrics`)

## 🛠️ Szczegóły techniczne

### Zakres

- Budowa, zapis i odczyt ramki predykcji (schemat §4, metadane w schemacie parquet).
- Raport per klasa w Markdown, zapis `metrics_<split>.json` (§5), `thresholds.json` (§3) przy `--thresholds tune`.
- `scripts/evaluate.py`: ładowanie checkpointu, odtworzenie pipeline'u z configu w checkpoincie, predykcja przez `predict_loader`,
  metryki, logowanie do runu źródłowego (`resume_run`) w `eval/<split>/`.
- Split `test` wyłącznie przez `require_test_unlocked`.
- `cardioai.evaluation.subgroups.subgroup_metrics` — metryki (n, macro AUROC, ECE) per podgrupa na ramce predykcji; korzysta z niej {{T402}} (E08).
  Obowiązkowe podgrupy (budowane przez wywołującego jako `groups`): płeć i wiek (< 40, 40–60, 60–75, > 75); `device` i `site` opcjonalnie.

### Poza zakresem (wiążące)

- Kalibracja ({{T501}}), predykcje na zbiorze z korupcjami ({{T303}}).

### Pliki

- `src/cardioai/evaluation/predictions.py`, `src/cardioai/evaluation/report.py`, `src/cardioai/evaluation/subgroups.py` — nowe
- `scripts/evaluate.py` — nowy
- `tests/unit/evaluation/test_predictions.py`, `tests/unit/evaluation/test_subgroups.py`, `tests/integration/test_evaluate_smoke.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def build_prediction_frame(*, ecg_id: np.ndarray, patient_id: np.ndarray, strat_fold: np.ndarray, y_true: np.ndarray,
                           logits: np.ndarray, quality_logits: np.ndarray | None = None,
                           y_quality: np.ndarray | None = None, prob_cal: np.ndarray | None = None) -> pd.DataFrame: ...
def save_predictions(df: pd.DataFrame, path: Path, *, metadata: Mapping[str, str]) -> None: ...
def load_predictions(path: Path) -> tuple[pd.DataFrame, dict[str, str]]: ...      # walidacja schematu
def arrays_from_frame(df: pd.DataFrame, kind: Literal["y", "logit", "prob", "prob_cal", "qlogit", "yq"]) -> np.ndarray: ...
def per_class_table_md(metrics: Mapping[str, Any]) -> str: ...
def save_metrics_json(metrics: Mapping[str, Any], path: Path, *, run_meta: Mapping[str, str]) -> None: ...

# evaluation/subgroups.py (przeniesione z T402; używane w E08)
def subgroup_metrics(pred: pd.DataFrame, groups: pd.Series, *, min_size: int = 50) -> pd.DataFrame: ...   # n, macro AUROC, ECE per grupa; grupy < min_size oznaczone
```

CLI: `evaluate.py --checkpoint PATH --split {val,test} [--thresholds tune|PATH] [--out DIR] [--run-id ID] [--batch-size N]`.

### Testy do napisania

- `test_predictions.py`: round-trip parquet z metadanymi, walidacja schematu, `arrays_from_frame`.
- `test_subgroups.py`: metryki per grupa, pominięcie (oznaczenie) małych grup, podgrupy płci i wieku (progi 40 / 60 / 75).
- `test_evaluate_smoke.py`: checkpoint z {{T204}} na fixture → predykcje i metryki; odmowa dla `test`.

### Weryfikacja

```bash
uv run pytest tests/unit/evaluation/test_predictions.py tests/unit/evaluation/test_subgroups.py tests/integration/test_evaluate_smoke.py -q
uv run python scripts/evaluate.py --checkpoint outputs/e02_cnn_small/<run>/checkpoints/best.pt --split val --thresholds tune
```

### Wskazówki i pułapki

- Pipeline odtwarzaj z configu zapisanego w checkpoincie, nie z bieżących plików YAML — inaczej ewaluacja może użyć innego preprocessingu.
- Metadane parquet (`schema.metadata`) są bajtami — koduj UTF-8 i dekoduj przy odczycie.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T206-evaluate-predictions.md`](https://github.com/__REPO__/blob/main/tasks/T206-evaluate-predictions.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Kolumny i typy pliku predykcji zgodne z `docs/evaluation.md` §4; `load_predictions` odrzuca plik niezgodny.
- [ ] Ewaluacja `best.pt` na val odtwarza najlepszy `val/macro_auroc` z treningu (|Δ| < 1e-6 na CPU).
- [ ] `--thresholds tune` zapisuje `thresholds.json` (`fitted_on: "val"`); `--thresholds PATH` stosuje progi bez ich zmiany.
- [ ] `--split test` bez odblokowania kończy się `LockedSplitError` i kodem wyjścia ≠ 0.
- [ ] Artefakty w MLflow w `eval/val/`: predykcje, metryki, tabela Markdown.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T206 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T204}} — Pętla treningowa, straty, checkpointy i scripts/train.py (tydzień 3, właściciel B)

**Odblokowuje:**

- {{T208}} — Nierównowaga klas — pos_weight, focal loss, progi (E04) (tydzień 5, właściciel B)
- {{T303}} — Model jakości — głowa multitask i osobny QualityNet (E05) (tydzień 6, właściciel A)
- {{T305}} — Robustness suite — testy odporności z raportem (tydzień 7, właściciel B)
- {{T501}} — Kalibracja prawdopodobieństw i diagramy niezawodności (E09) (tydzień 10, właściciel C)
- {{T601}} — Format bundla inferencyjnego i eksport z checkpointu (tydzień 6, właściciel B)

**Bramka G2 — Baseline** (tydzień 3–4): model uczy się sensownego sygnału; metryki > losowe; pipeline MLflow działa (doprecyzowanie: macro AUROC val ≥ 0,80, E02).

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T201}}, {{T202}}, {{T203}}, {{T204}}, {{T205}}, {{T206}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T206` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t206-evaluate-predictions`; status karty `in_progress` (`python3 scripts/tasks.py set-status T206 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(evaluation): <description> [T206]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T206`.

W Claude Code zadanie realizuje komenda `/task T206`.
__ISSUE_BODY_EOF__
}

body_T207() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T207-resnet1d.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Residualny CNN 1D jako model referencyjny projektu, konfigurowalny dla 100 i 500 Hz, z pierwszym runem na prawdziwych danych.

| Pole | Wartość |
|---|---|
| Zadanie | **T207** — ResNet1D — model główny (E03) |
| Epik | Modele i trening (`training`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 4 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G3 — Core model |
| Eksperyment | E03 |
| Właściciel | B (Model & Experiments) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§3.2](https://github.com/__REPO__/blob/main/docs/modeling.md#32-resnet1d--model-główny-e03) (architektura i parametry), [§7](https://github.com/__REPO__/blob/main/docs/modeling.md#7-protokół-treningu) (protokół), [§9](https://github.com/__REPO__/blob/main/docs/modeling.md#9-porównywalność-architektur) (porównywalność)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E03)
- [`docs/evaluation.md`](https://github.com/__REPO__/blob/main/docs/evaluation.md) [§9](https://github.com/__REPO__/blob/main/docs/evaluation.md#9-punkt-odniesienia-z-literatury) (punkt odniesienia z literatury)

## 🛠️ Szczegóły techniczne

### Zakres

- `ResNet1DEncoder` z `ResNet1DParams` dokładnie według `docs/modeling.md` §3.2 (`BasicBlock1D`, skróty 1×1, etapy ze `stride=2`).
- `configs/model/resnet1d.yaml`, `configs/experiment/e03_resnet1d.yaml` (100 Hz, BCE, augmentacje bazowe: `gaussian_noise` p=0,3, `amplitude_scale` p=0,3).
- Run seed 0 na laptopie A; opcjonalny mały sweep (`lr`, `kernel_size`) według E03.
- Liczba parametrów, MFLOPs dla `[1, 12, 1000]` i `[1, 12, 5000]`, czas epoki — w PR.

### Poza zakresem (wiążące)

- Warianty funkcji straty ({{T208}}), multi-seed ({{T209}}), 500 Hz ({{T404}}).

### Pliki

- `src/cardioai/models/resnet1d.py` — nowy
- `configs/model/resnet1d.yaml`, `configs/experiment/e03_resnet1d.yaml` — nowe
- `tests/unit/models/test_resnet1d.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
class ResNet1DParams(BaseModel):
    stem_kernel: int = 15
    stem_stride: int = 2
    stem_pool: bool = True
    widths: list[int] = [64, 128, 256, 512]
    blocks: list[int] = [2, 2, 2, 2]
    kernel_size: int = 7
    block_dropout: float = 0.1
    activation: Literal["relu", "gelu"] = "relu"
@register_encoder("resnet1d", params=ResNet1DParams)
class ResNet1DEncoder(Encoder): ...      # out_dim = widths[-1]
```

### Testy do napisania

- `test_resnet1d.py`: kształty (100/500 Hz, różne `widths`/`blocks`), walidacja parametrów, przepływ gradientu, skrót przy zmianie wymiaru.

### Weryfikacja

```bash
uv run pytest tests/unit/models/test_resnet1d.py -q
uv run python scripts/train.py --config configs/experiment/e03_resnet1d.yaml
```

### Wskazówki i pułapki

- Padding `kernel_size // 2` przy nieparzystych jądrach zachowuje długość przed `stride`.
- Przy 6 GB VRAM i `batch_size=128` włącz `training.amp: true` na CUDA; bez AMP może być potrzebne `grad_accum_steps=2`.

## 🧪 Eksperyment E03 — ResNet1D

**Cel decyzyjny:** model referencyjny · zadania: T207, {{T209}} · właściciel eksperymentu: B · tydzień: 4–5

**Hipotezy powiązane z eksperymentem:**

- H1: Residual 1D (ResNet1D) osiągnie wyższą jakość i stabilność niż płytki CNN przy akceptowalnym koszcie inferencji.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** `resnet1d` z configu startowego; ewentualny mały sweep `lr ∈ {1e-3, 3e-4, 1e-4}` i `kernel_size ∈ {5, 7, 9}`.
- **Stałe:** 100 Hz, BCE bez wag (do E04), augmentacje bazowe.
- **Metryki:** macro/micro AUROC, AP, per klasa, parametry, MFLOPs, czas epoki.
- **Reguła:** ResNet1D stabilny na 3 seedach (std macro AUROC ≤ 0,01) → bramka G3; porównanie z E02 → H1.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T207-resnet1d.md`](https://github.com/__REPO__/blob/main/tasks/T207-resnet1d.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Forward dla 100 Hz i 500 Hz (także z `stem_kernel=75, stem_stride=10`) daje embedding `[B, widths[-1]]`.
- [ ] `len(widths) != len(blocks)` → błąd walidacji `Params`.
- [ ] Run E03 (seed 0) w MLflow z macro AUROC val zapisanym w PR wraz z porównaniem do E02.
- [ ] Liczba parametrów i MFLOPs zalogowane; wartości wpisane w PR.
- [ ] Forward w `eval()` deterministyczny; gradient dociera do stemu.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T207 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T109}} — Augmentacje treningowe z rejestrem i walidacją parametrów (tydzień 4, właściciel A)
- {{T205}} — Płytki CNN 1D i pierwszy run end-to-end (E02) (tydzień 3, właściciel B)

**Odblokowuje:**

- {{T208}} — Nierównowaga klas — pos_weight, focal loss, progi (E04) (tydzień 5, właściciel B)
- {{T303}} — Model jakości — głowa multitask i osobny QualityNet (E05) (tydzień 6, właściciel A)
- {{T401}} — Transformer czasowy jako model porównawczy (E07) (tydzień 8, właściciel B)
- {{T403}} — Głowy pomocnicze rhythm/form (opcjonalne, E05) (tydzień 9, właściciel A)
- {{T503}} — XAI — Integrated Gradients, saliency i agregacje (E11) (tydzień 8, właściciel C)

**Bramka G3 — Core model** (tydzień 5): ResNet1D stabilny na ≥ 3 runach; brak regresji pipeline'u danych.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T108}}, {{T109}}, {{T207}}, {{T208}}, {{T209}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T207` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t207-resnet1d`; status karty `in_progress` (`python3 scripts/tasks.py set-status T207 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(models): <description> [T207]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T207`.

W Claude Code zadanie realizuje komenda `/task T207`.
__ISSUE_BODY_EOF__
}

body_T208() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T208-imbalance-thresholds.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Rozstrzygnąć na val, jak obsłużyć nierównowagę klas (HYP jest ok. 3,5× rzadsza niż NORM), i ustalić domyślną stratę oraz metodę progów dla dalszych eksperymentów.

| Pole | Wartość |
|---|---|
| Zadanie | **T208** — Nierównowaga klas — pos_weight, focal loss, progi (E04) |
| Epik | Modele i trening (`training`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 5 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G3 — Core model |
| Eksperyment | E04 |
| Właściciel | B (Model & Experiments) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§5](https://github.com/__REPO__/blob/main/docs/modeling.md#5-funkcje-straty) (straty)
- [`docs/evaluation.md`](https://github.com/__REPO__/blob/main/docs/evaluation.md) [§3](https://github.com/__REPO__/blob/main/docs/evaluation.md#3-progi-decyzyjne) (progi)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E04 — reguła decyzyjna)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§2](https://github.com/__REPO__/blob/main/AGENTS.md#2-zasady-nienaruszalne) pkt 3 (`pos_weight` tylko z train)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-031](https://github.com/__REPO__/blob/main/docs/decisions.md#d-031--jeden-eksperyment-mlflow-na-pozycję-exx)

## 🛠️ Szczegóły techniczne

### Zakres

- `compute_pos_weight` (`none`, `train`, `sqrt_train`) liczone wyłącznie z wierszy train indeksu.
- Strata `focal` (na logitach, `γ = focal_gamma`) jako wariant `training.loss.name`.
- Configi `e04a_bce.yaml`, `e04b_posweight.yaml`, `e04c_focal.yaml`, wszystkie z `experiment.name: e04_imbalance` (wariant tylko w `experiment.variant`, np. `bce`, `posweight`, `focal`; D-031); run seed 0 dla każdego wariantu (3 seedy dla zwycięzcy uruchamia {{T209}}).
- Porównanie progów `f1` vs `youden` na najlepszym wariancie.
- Wniosek w `docs/experiments.md` (E04) i — jeśli zmienia domyślną stratę w `configs/base.yaml` — wpis w `docs/decisions.md`.

### Poza zakresem (wiążące)

- Złożone funkcje kosztu (asymetryczne, z marginesem) — tylko jeśli E04 wykaże potrzebę, jako osobne zadanie.

### Pliki

- `src/cardioai/training/losses.py` — zmiana (focal, `pos_weight`)
- `src/cardioai/training/class_weights.py` — nowy
- `configs/experiment/e04a_bce.yaml`, `e04b_posweight.yaml`, `e04c_focal.yaml` — nowe
- `tests/unit/training/test_class_weights.py`, `tests/unit/training/test_focal.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def compute_pos_weight(index: pd.DataFrame, mode: Literal["none", "train", "sqrt_train"],
                       *, drop_unlabeled: bool = True) -> torch.Tensor | None: ...   # [5] float32, kolejność SUPERCLASSES
def focal_loss_with_logits(logits: torch.Tensor, targets: torch.Tensor, *, gamma: float = 2.0,
                           pos_weight: torch.Tensor | None = None, reduction: str = "mean") -> torch.Tensor: ...
```

### Testy do napisania

- `test_class_weights.py`: wartości dla znanego indeksu, tryby, wyłącznie train.
- `test_focal.py`: równoważność z BCE przy `γ = 0`, stabilność numeryczna przy dużych logitach (±50).

### Weryfikacja

```bash
uv run pytest tests/unit/training/test_class_weights.py tests/unit/training/test_focal.py -q
uv run python scripts/train.py --config configs/experiment/e04b_posweight.yaml
```

### Wskazówki i pułapki

- Focal licz przez `binary_cross_entropy_with_logits(reduction="none")` i `p_t = exp(-bce)` — bez jawnego `sigmoid` i `log`.
- Wysokie `pos_weight` psują kalibrację — patrz E09; zapisz ECE każdego wariantu.

## 🧪 Eksperyment E04 — Nierównowaga klas

**Cel decyzyjny:** wybór funkcji straty i metody progów · zadania: T208 · właściciel eksperymentu: B · tydzień: 5

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** `e04a_bce`, `e04b_posweight` (`pos_weight: train`), `e04c_focal` (`γ = 2`); progi `f1` vs `youden`.
- **Reguła:** wybieramy wariant z najwyższym macro F1 (progi z val), o ile macro AUROC nie spada o więcej niż 0,005 względem `e04a`.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T208-imbalance-thresholds.md`](https://github.com/__REPO__/blob/main/tasks/T208-imbalance-thresholds.md)
- Decyzja [D-031](https://github.com/__REPO__/blob/main/docs/decisions.md#d-031--jeden-eksperyment-mlflow-na-pozycję-exx) — Jeden eksperyment MLflow na pozycję Exx
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] `compute_pos_weight` korzysta tylko z wierszy `split == "train"` (test: zmiana etykiet val/test nie zmienia wyniku).
- [ ] Focal z `γ = 0` daje wynik równy BCE (tolerancja 1e-6); dla `γ > 0` zgodność z referencją na wartościach testowych.
- [ ] Trzy warianty w MLflow (`exp_id=E04`), tabela w `docs/experiments.md` (E04) wygenerowana przez `summarize_runs.py` ({{T209}}) lub tymczasowo z MLflow z linkami do runów.
- [ ] Decyzja według reguły E04 zapisana w sekcji „Wniosek” eksperymentu.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T208 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T206}} — Ewaluacja checkpointu, pliki predykcji i metryk (tydzień 4, właściciel B)
- {{T207}} — ResNet1D — model główny (E03) (tydzień 4, właściciel B)

**Odblokowuje:**

- {{T209}} — Uruchamianie wielu seedów i tabele wyników z MLflow (bramka G3) (tydzień 5, właściciel B)

**Bramka G3 — Core model** (tydzień 5): ResNet1D stabilny na ≥ 3 runach; brak regresji pipeline'u danych.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T108}}, {{T109}}, {{T207}}, {{T208}}, {{T209}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T208` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t208-imbalance-thresholds`; status karty `in_progress` (`python3 scripts/tasks.py set-status T208 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(training): <description> [T208]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T208`.

W Claude Code zadanie realizuje komenda `/task T208`.
__ISSUE_BODY_EOF__
}

body_T209() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T209-multiseed-summary.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Wyniki w dokumentacji i raporcie pochodzą automatycznie z MLflow (średnia ± std z seedów), a ResNet1D jest potwierdzony jako stabilny.

| Pole | Wartość |
|---|---|
| Zadanie | **T209** — Uruchamianie wielu seedów i tabele wyników z MLflow (bramka G3) |
| Epik | Modele i trening (`training`) |
| Poziom | MVP (obowiązkowe) |
| Planowany tydzień | 5 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G3 — Core model |
| Eksperyment | E03 |
| Właściciel | B (Model & Experiments) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/evaluation.md`](https://github.com/__REPO__/blob/main/docs/evaluation.md) [§6](https://github.com/__REPO__/blob/main/docs/evaluation.md#6-wiele-seedów-i-raportowanie) (wiele seedów, kolumny tabeli, istotność), [§8](https://github.com/__REPO__/blob/main/docs/evaluation.md#8-przedziały-ufności-bootstrap) (bootstrap pacjentów)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§1](https://github.com/__REPO__/blob/main/docs/experiments.md#1-zasady), [§5](https://github.com/__REPO__/blob/main/docs/experiments.md#5-tabela-zbiorcza) (znaczniki `<!-- BEGIN:Exx -->`)
- [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§2](https://github.com/__REPO__/blob/main/docs/mlops.md#2-konwencje-eksperymenty-runy-tagi), [§3](https://github.com/__REPO__/blob/main/docs/mlops.md#3-parametry-metryki-artefakty), [§5](https://github.com/__REPO__/blob/main/docs/mlops.md#5-reprodukowalność) (tagi, metryki, `git_dirty`)
- [`tasks/README.md`](https://github.com/__REPO__/blob/main/tasks/README.md) [§5](https://github.com/__REPO__/blob/main/tasks/README.md#5-bramki-jakościowe-g1g6) (G3)

## 🛠️ Szczegóły techniczne

### Zakres

- `scripts/run_seeds.py --config PATH --seeds 0 1 2 [--set ...]` — kolejne treningi z `--set seed=N`.
- `cardioai.tracking.summary`: pobranie runów, agregacja po `config_hash`, tabela Markdown, podmiana treści między znacznikami w dokumentach.
- `scripts/summarize_runs.py --experiment NAME [--write-docs Exx] [--all]` — kolumny z `docs/evaluation.md` §6; domyślnie bez runów `git_dirty=true`.
- `cardioai.evaluation.bootstrap`: bootstrap pacjentów (B = 1000, seed 0) i wariant sparowany (`docs/evaluation.md` §8) — przeniesione z {{T801}}; korzysta z nich {{T801}} (przedziały ufności na teście)
  oraz porównania wariantów na val (reguła istotności z §6).
- Uruchomienie 3 seedów dla wybranego wariantu ResNet1D (po E04) i wpis tabel E02–E04 do `docs/experiments.md`.

### Poza zakresem (wiążące)

- Testy statystyczne poza regułą z `docs/evaluation.md` §6 i bootstrapem z §8; wykresy do raportu ({{T803}}).

### Pliki

- `src/cardioai/tracking/summary.py` — nowy
- `src/cardioai/evaluation/bootstrap.py` — nowy
- `scripts/run_seeds.py`, `scripts/summarize_runs.py` — nowe
- `docs/experiments.md` — aktualizacja (tabele E01–E04)
- `tests/unit/tracking/test_summary.py`, `tests/unit/evaluation/test_bootstrap.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def fetch_runs(experiment_names: Sequence[str], *, filter_tags: Mapping[str, str] | None = None,
               include_dirty: bool = False) -> pd.DataFrame: ...
def aggregate_by_config(runs: pd.DataFrame, metrics: Sequence[str]) -> pd.DataFrame: ...   # mean, std, n_seeds
def to_markdown_table(df: pd.DataFrame, columns: Sequence[str], *, float_fmt: str = "{:.3f}") -> str: ...
def update_doc_section(doc_path: Path, marker: str, content: str) -> None: ...             # BEGIN/END:marker

# cardioai.evaluation.bootstrap (przeniesione z T801)
def patient_bootstrap(y_true: np.ndarray, y_prob: np.ndarray, patient_id: np.ndarray, *,
                      metric: Callable[[np.ndarray, np.ndarray], float], n_boot: int = 1000,
                      seed: int = 0, alpha: float = 0.05) -> tuple[float, float, float]: ...   # (estimate, low, high)
def paired_patient_bootstrap(y_true: np.ndarray, prob_a: np.ndarray, prob_b: np.ndarray, patient_id: np.ndarray, *,
                             metric: Callable[[np.ndarray, np.ndarray], float], n_boot: int = 1000,
                             seed: int = 0) -> tuple[float, float, float]: ...                  # różnica A − B
```

### Testy do napisania

- `test_summary.py`: agregacja na sztucznej ramce runów, format liczb, podmiana sekcji w pliku tymczasowym, brak znacznika; jeden test z tymczasowym store MLflow.
- `test_bootstrap.py`: deterministyczność, losowanie po pacjentach (wszystkie rekordy pacjenta razem), zbieżność na prostym przykładzie.

### Weryfikacja

```bash
uv run pytest tests/unit/tracking/test_summary.py tests/unit/evaluation/test_bootstrap.py -q
uv run python scripts/run_seeds.py --config configs/experiment/e03_resnet1d.yaml --seeds 0 1 2
uv run python scripts/summarize_runs.py --experiment e03_resnet1d --write-docs E03
```

### Wskazówki i pułapki

- Grupuj po `config_hash`, nie po nazwie runu — nazwa zawiera seed.
- Ten sam config na różnych urządzeniach ma ten sam hash; filtruj po tagu `device` dla tabel finalnych (D-019).

## 🧪 Eksperyment E03 — ResNet1D

**Cel decyzyjny:** model referencyjny · zadania: {{T207}}, T209 · właściciel eksperymentu: B · tydzień: 4–5

**Hipotezy powiązane z eksperymentem:**

- H1: Residual 1D (ResNet1D) osiągnie wyższą jakość i stabilność niż płytki CNN przy akceptowalnym koszcie inferencji.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** `resnet1d` z configu startowego; ewentualny mały sweep `lr ∈ {1e-3, 3e-4, 1e-4}` i `kernel_size ∈ {5, 7, 9}`.
- **Stałe:** 100 Hz, BCE bez wag (do E04), augmentacje bazowe.
- **Metryki:** macro/micro AUROC, AP, per klasa, parametry, MFLOPs, czas epoki.
- **Reguła:** ResNet1D stabilny na 3 seedach (std macro AUROC ≤ 0,01) → bramka G3; porównanie z E02 → H1.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

1. **Split wyłącznie z `strat_fold`:** train = foldy 1–8, val = fold 9, test = fold 10. Żadnego `random_split`, `train_test_split` ani własnego podziału.
2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T209-multiseed-summary.md`](https://github.com/__REPO__/blob/main/tasks/T209-multiseed-summary.md)
- Decyzja [D-019](https://github.com/__REPO__/blob/main/docs/decisions.md#d-019--kanoniczne-urządzenie-dla-wyników-finalnych) — Kanoniczne urządzenie dla wyników finalnych
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] Bramka G3: ResNet1D na 3 seedach, odchylenie standardowe macro AUROC val ≤ 0,01 (albo opis przyczyny i plan w PR).
- [ ] Tabele E01–E04 w `docs/experiments.md` wygenerowane skryptem; ponowne uruchomienie bez nowych runów nie zmienia pliku.
- [ ] `update_doc_section` zmienia wyłącznie treść między znacznikami; brak znacznika → czytelny błąd.
- [ ] Runy z `git_dirty=true` pominięte domyślnie (flaga `--include-dirty`).
- [ ] Bootstrap: przedziały zawierają estymację punktową; ten sam seed → te same przedziały (test).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T209 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T208}} — Nierównowaga klas — pos_weight, focal loss, progi (E04) (tydzień 5, właściciel B)

**Odblokowuje:**

- {{T306}} — Eksperyment lead dropout i odporność kanałowa (E06, H3) (tydzień 7, właściciel B)
- {{T402}} — Fuzja metadanych i analiza podgrup (E08, H2) (tydzień 9, właściciel B)
- {{T404}} — Porównanie 100 Hz vs 500 Hz — jakość a koszt (E10, H5) (tydzień 11, właściciel B)
- {{T801}} — Zamrożenie konfiguracji i jednorazowa ewaluacja na foldzie 10 (G6) (tydzień 14, właściciel B)

**Bramka G3 — Core model** (tydzień 5): ResNet1D stabilny na ≥ 3 runach; brak regresji pipeline'u danych.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T108}}, {{T109}}, {{T207}}, {{T208}}, {{T209}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T209` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t209-multiseed-summary`; status karty `in_progress` (`python3 scripts/tasks.py set-status T209 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(tracking): <description> [T209]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T209`.

W Claude Code zadanie realizuje komenda `/task T209`.
__ISSUE_BODY_EOF__
}

body_T301() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T301-weak-quality-labels.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Dataset dostarcza wektor `y_quality` (słabe etykiety PTB-XL połączone z etykietami korupcji), a zespół zna ograniczenia tych etykiet, zanim zacznie na nich trenować.

| Pole | Wartość |
|---|---|
| Zadanie | **T301** — Słabe etykiety jakości w Dataset i analiza ich wiarygodności |
| Epik | Jakość i odporność (`quality`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 5 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G4 — Reliability |
| Eksperyment | E05 |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§8](https://github.com/__REPO__/blob/main/docs/data_contract.md#8-próbka-z-dataset-i-pipeline-transformacji) (`y_quality`), [§11](https://github.com/__REPO__/blob/main/docs/data_contract.md#11-etykiety-jakości-słabe) (reguły słabych etykiet)
- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§2](https://github.com/__REPO__/blob/main/docs/reliability.md#2-etykiety-jakości-i-korupcje-syntetyczne), [§3](https://github.com/__REPO__/blob/main/docs/reliability.md#3-model-jakości-głowa--qualitynet)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-012](https://github.com/__REPO__/blob/main/docs/decisions.md#d-012--etykiety-jakości-4-klasy)

## 🛠️ Szczegóły techniczne

### Zakres

- `weak_quality_matrix(index)` z kolumn `q_*` indeksu (kolejność `QUALITY_LABELS`).
- `PTBXLDataset(return_quality=True)`: `y_quality = weak OR SignalSample.quality` (korupcje z pipeline'u, {{T302}}).
- Analiza wiarygodności: przegląd wizualny 20 oznaczonych i 20 nieoznaczonych rekordów **z train** (wykresy w `reports/quality/`), krótki opis ograniczeń w `docs/reliability.md` §3.
- Częstość etykiet per split i fold — przez istniejącą funkcję `cardioai.data.eda.quality_prevalence` ({{T110}}), bez duplikowania.

### Poza zakresem (wiążące)

- Parsowanie per odprowadzenie (poza MVP), model jakości ({{T303}}).

### Pliki

- `src/cardioai/data/quality_labels.py` — nowy
- `src/cardioai/data/dataset.py` — zmiana (`return_quality`)
- `scripts/review_quality_labels.py` — nowy
- `docs/reliability.md` — aktualizacja §3 (ograniczenia)
- `tests/unit/data/test_quality_labels.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def weak_quality_matrix(index: pd.DataFrame) -> np.ndarray: ...   # [N, 4] int8, kolejność QUALITY_LABELS
def merge_quality(weak: np.ndarray, synthetic: np.ndarray) -> np.ndarray: ...   # OR, int8
```

### Testy do napisania

- `test_quality_labels.py`: macierz z fixture'a, scalanie OR, integracja z `PTBXLDataset`.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_quality_labels.py -q
uv run python scripts/review_quality_labels.py --n 20 --out reports/quality
```

### Wskazówki i pułapki

- Brak flagi nie znaczy „czysty sygnał” — nie używaj rekordów bez flag jako twardych negatywów w raportach bez zastrzeżenia.

## 🧪 Eksperyment E05 — Multitask z jakością sygnału

**Cel decyzyjny:** czy włączyć głowę jakości / głowy aux · zadania: {{T303}}, {{T403}} · właściciel eksperymentu: A · tydzień: 6, 9

**Hipotezy powiązane z eksperymentem:**

- H6: Model wielozadaniowy z zadaniem jakości sygnału jest odporniejszy na artefakty.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** tylko diagnoza; diagnoza + jakość (`lambda_quality ∈ {0.5, 1.0}`, korupcje syntetyczne `p = 0.3`);
  osobny QualityNet; opcjonalnie głowy rhythm/form ({{T403}}).
- **Metryki:** macro AUROC diagnozy na czystym val, macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`, {{T303}}), AUROC jakości (syntetyczny val i słabe etykiety), FRR quality gate.
  Krzywe robustness z E06 są raportowane w {{T306}} jako uzupełnienie, nie jako warunek decyzji.
- **Reguła (D-027, status: proponowana):** włączamy głowę jakości, jeśli spadek macro AUROC diagnozy na czystym val ≤ 0,005, a macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`) wzrasta. Głowy aux — analogicznie.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T301-weak-quality-labels.md`](https://github.com/__REPO__/blob/main/tasks/T301-weak-quality-labels.md)
- Decyzja [D-012](https://github.com/__REPO__/blob/main/docs/decisions.md#d-012--etykiety-jakości-4-klasy) — Etykiety jakości: 4 klasy
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] Próbka z `return_quality=True` ma `y_quality` `FloatTensor [4]` zgodny z indeksem (fixture).
- [ ] Gdy pipeline dodał korupcję, `y_quality` zawiera OR słabych i syntetycznych etykiet (test z transformem ustawiającym `quality`).
- [ ] Przegląd 40 rekordów wykonany; wnioski (np. odsetek oczywistych błędów etykiet) w `docs/reliability.md` §3.
- [ ] Brak wykresów rekordów z val i test.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T301 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T105}} — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu (tydzień 2, właściciel A)
- {{T110}} — EDA i raport danych (E00) (tydzień 3, właściciel A)

**Odblokowuje:**

- {{T303}} — Model jakości — głowa multitask i osobny QualityNet (E05) (tydzień 6, właściciel A)

**Bramka G4 — Reliability** (tydzień 11): kalibracja i abstention ocenione; quality gate nie degraduje wyników bez kontroli.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T301}}, {{T302}}, {{T303}}, {{T304}}, {{T305}}, {{T306}}, {{T501}}, {{T502}}, {{T504}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T301` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t301-weak-quality-labels`; status karty `in_progress` (`python3 scripts/tasks.py set-status T301 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T301]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T301`.

W Claude Code zadanie realizuje komenda `/task T301`.
__ISSUE_BODY_EOF__
}

body_T302() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T302-synthetic-corruptions.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Kontrolowane artefakty o znanej etykiecie — do treningu modelu jakości ({{T303}}), doboru quality gate ({{T304}}) i testów odporności ({{T305}}).

| Pole | Wartość |
|---|---|
| Zadanie | **T302** — Biblioteka korupcji syntetycznych z etykietami jakości |
| Epik | Jakość i odporność (`quality`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 5 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G4 — Reliability |
| Eksperyment | E05 |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§2](https://github.com/__REPO__/blob/main/docs/reliability.md#2-etykiety-jakości-i-korupcje-syntetyczne) (katalog korupcji, wiążące API), [§8](https://github.com/__REPO__/blob/main/docs/reliability.md#8-robustness-suite) (siatki robustness)
- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§8](https://github.com/__REPO__/blob/main/docs/data_contract.md#8-próbka-z-dataset-i-pipeline-transformacji) (krok 3), [§13](https://github.com/__REPO__/blob/main/docs/data_contract.md#13-brakujące-odprowadzenia) (`electrode_flat` vs brakujące odprowadzenie)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-010](https://github.com/__REPO__/blob/main/docs/decisions.md#d-010--kolejność-transformacji-i-konwencja-brakującego-odprowadzenia), [D-012](https://github.com/__REPO__/blob/main/docs/decisions.md#d-012--etykiety-jakości-4-klasy), [D-023](https://github.com/__REPO__/blob/main/docs/decisions.md#d-023--korupcja-robustness-w-build_pipeline-przy-trainfalse)

## 🛠️ Szczegóły techniczne

### Zakres

- Korupcje z tabeli `docs/reliability.md` §2: `gaussian_noise`, `powerline`, `burst_noise`, `baseline_drift`, `electrode_flat`, `electrode_pop`, `saturation`.
- `apply_corruption` (parametry jawne) i `CorruptionSampler` (trening: z prawdopodobieństwem `p` 1–2 korupcje z zakresów).
- `CorruptionTransform` — Transform kroku 3 pipeline'u, ustawiający `SignalSample.quality`; przekazywany do `build_pipeline` jako `corruption` (trening, `train=True`)
  albo jako `robustness_corruption` (ewaluacja, stosowany tylko przy `train=False`; D-023).
- `corrupt_for_eval` — deterministyczna korupcja do ewaluacji (RNG z `[seed, ecg_id, id korupcji]`).
- Podłączenie `quality.synthetic` z configu do fabryki pipeline'u train.

### Poza zakresem (wiążące)

- Brakujące odprowadzenie jako maska po normalizacji — to `lead_dropout` ({{T109}}) i test robustness ({{T305}}).

### Pliki

- `src/cardioai/data/corruptions.py` — nowy
- `src/cardioai/data/datamodule.py` — zmiana (korupcje w fabryce train)
- `tests/unit/data/test_corruptions.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
# docs/reliability.md §2: CorruptionResult, apply_corruption, CorruptionSampler
CORRUPTIONS: Mapping[str, Callable[..., CorruptionResult]]
class CorruptionTransform:                      # Transform
    def __init__(self, sampler: CorruptionSampler) -> None: ...
def corrupt_for_eval(x: np.ndarray, fs: int, *, ecg_id: int, name: str, severity: float | int,
                     seed: int = 0) -> CorruptionResult: ...
```

### Testy do napisania

- `test_corruptions.py`: etykiety, SNR, zakresy parametrów, `powerline` przy 100/500 Hz, determinizm, sampler (rozkład liczby korupcji).

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_corruptions.py -q
```

### Wskazówki i pułapki

- Moc sygnału do SNR licz z wariancji odprowadzenia po odjęciu średniej; dla odprowadzenia płaskiego użyj dolnej granicy, żeby nie dzielić przez 0.
- Zakresy parametrów trzymaj w klasach parametrów (Pydantic), nie w kodzie funkcji — robustness nadpisuje je siatką.

## 🧪 Eksperyment E05 — Multitask z jakością sygnału

**Cel decyzyjny:** czy włączyć głowę jakości / głowy aux · zadania: {{T303}}, {{T403}} · właściciel eksperymentu: A · tydzień: 6, 9

**Hipotezy powiązane z eksperymentem:**

- H6: Model wielozadaniowy z zadaniem jakości sygnału jest odporniejszy na artefakty.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** tylko diagnoza; diagnoza + jakość (`lambda_quality ∈ {0.5, 1.0}`, korupcje syntetyczne `p = 0.3`);
  osobny QualityNet; opcjonalnie głowy rhythm/form ({{T403}}).
- **Metryki:** macro AUROC diagnozy na czystym val, macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`, {{T303}}), AUROC jakości (syntetyczny val i słabe etykiety), FRR quality gate.
  Krzywe robustness z E06 są raportowane w {{T306}} jako uzupełnienie, nie jako warunek decyzji.
- **Reguła (D-027, status: proponowana):** włączamy głowę jakości, jeśli spadek macro AUROC diagnozy na czystym val ≤ 0,005, a macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`) wzrasta. Głowy aux — analogicznie.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T302-synthetic-corruptions.md`](https://github.com/__REPO__/blob/main/tasks/T302-synthetic-corruptions.md)
- Decyzja [D-010](https://github.com/__REPO__/blob/main/docs/decisions.md#d-010--kolejność-transformacji-i-konwencja-brakującego-odprowadzenia) — Kolejność transformacji i konwencja brakującego odprowadzenia
- Decyzja [D-012](https://github.com/__REPO__/blob/main/docs/decisions.md#d-012--etykiety-jakości-4-klasy) — Etykiety jakości: 4 klasy
- Decyzja [D-023](https://github.com/__REPO__/blob/main/docs/decisions.md#d-023--korupcja-robustness-w-build_pipeline-przy-trainfalse) — Korupcja robustness w `build_pipeline` przy `train=False`
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Każda korupcja ustawia etykietę jakości zgodnie z tabelą (`saturation` — brak etykiety).
- [ ] `gaussian_noise` osiąga zadany SNR ±0,5 dB per odprowadzenie.
- [ ] `powerline` przy `fs ≤ 100` → `ValueError` z wyjaśnieniem (Nyquist); `CorruptionSampler` pomija ją przy 100 Hz.
- [ ] `electrode_flat` nie zmienia `lead_mask` (kanał istnieje, jest płaski).
- [ ] Determinizm: ten sam RNG → identyczny wynik; `corrupt_for_eval` niezależny od kolejności wywołań.
- [ ] Kształt `[12, T]` i float32 zachowane; brak NaN.
- [ ] Korupcja przekazana jako `corruption` nie jest aplikowana w pipeline'ie `train=False`; przekazana jako `robustness_corruption` jest aplikowana tylko tam (test).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T302 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T109}} — Augmentacje treningowe z rejestrem i walidacją parametrów (tydzień 4, właściciel A)

**Odblokowuje:**

- {{T303}} — Model jakości — głowa multitask i osobny QualityNet (E05) (tydzień 6, właściciel A)
- {{T305}} — Robustness suite — testy odporności z raportem (tydzień 7, właściciel B)

**Bramka G4 — Reliability** (tydzień 11): kalibracja i abstention ocenione; quality gate nie degraduje wyników bez kontroli.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T301}}, {{T302}}, {{T303}}, {{T304}}, {{T305}}, {{T306}}, {{T501}}, {{T502}}, {{T504}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T302` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t302-synthetic-corruptions`; status karty `in_progress` (`python3 scripts/tasks.py set-status T302 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T302]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T302`.

W Claude Code zadanie realizuje komenda `/task T302`.
__ISSUE_BODY_EOF__
}

body_T303() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T303-quality-head.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Model ocenia jakość sygnału (4 typy artefaktów), a eksperyment E05 rozstrzyga, czy wspólny enkoder z głową jakości jest lepszy niż osobny QualityNet i czy nie szkodzi diagnozie (H6).

| Pole | Wartość |
|---|---|
| Zadanie | **T303** — Model jakości — głowa multitask i osobny QualityNet (E05) |
| Epik | Jakość i odporność (`quality`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 6 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G4 — Reliability |
| Eksperyment | E05 |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§3](https://github.com/__REPO__/blob/main/docs/reliability.md#3-model-jakości-głowa--qualitynet) (warianty i ewaluacja), [§2](https://github.com/__REPO__/blob/main/docs/reliability.md#2-etykiety-jakości-i-korupcje-syntetyczne) (korupcje)
- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§4](https://github.com/__REPO__/blob/main/docs/modeling.md#4-głowy-i-fuzja-metadanych) (głowy), [§5](https://github.com/__REPO__/blob/main/docs/modeling.md#5-funkcje-straty) (`L_quality`, `lambda_quality`)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E05 — reguła decyzyjna)
- [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§3](https://github.com/__REPO__/blob/main/docs/mlops.md#3-parametry-metryki-artefakty) (metryki `val/quality_*`)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-023](https://github.com/__REPO__/blob/main/docs/decisions.md#d-023--korupcja-robustness-w-build_pipeline-przy-trainfalse), [D-027](https://github.com/__REPO__/blob/main/docs/decisions.md#d-027--reguła-decyzyjna-e05-auroc-diagnozy-na-syntetycznym-val), [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) (parametr `lambda_diag`)

## 🛠️ Szczegóły techniczne

### Zakres

- Metryki jakości w walidacji `Trainer` (gdy `model.heads.quality`), dostarczane przez hook `MetricHook` z {{T204}} (`training/hooks_quality.py`, bez zmian w `trainer.py`):
  AUROC per etykieta na słabych etykietach val i na deterministycznym syntetycznym val (każdy rekord val czysty + jedna korupcja z `corrupt_for_eval`).
- `SyntheticQualityDataset` — dataset val zwracający wersje czyste i skorumpowane z etykietą `corruption`; buduje własny dataset val z pipeline'em
  `build_pipeline(train=False, robustness_corruption=...)` zamiast opakowywać gotowy `PTBXLDataset` (D-023).
- `scripts/evaluate.py --quality-synthetic` → `predictions_val_qsynth.parquet` (z kolumnami `qlogit_*`, `yq_*`, `corruption`).
- Configi: `e05a_diag_only.yaml`, `e05b_quality_l05.yaml`, `e05c_quality_l10.yaml` (korupcje `p = 0.3`), `e05d_qualitynet.yaml` (`cnn_small`, `lambda_diag = 0`).
- Wniosek E05 według reguły decyzyjnej.

### Poza zakresem (wiążące)

- Progi quality gate ({{T304}}), krzywe odporności ({{T305}}).

### Pliki

- `src/cardioai/data/quality_eval.py` — nowy (`SyntheticQualityDataset`)
- `src/cardioai/training/hooks_quality.py` — nowy (hook metryk jakości dla `Trainer.metric_hooks`, {{T204}})
- `scripts/train.py` — zmiana (podpięcie hooka jakości, gdy `model.heads.quality`)
- `scripts/evaluate.py` — zmiana (`--quality-synthetic`)
- `configs/experiment/e05a_diag_only.yaml`, `e05b_quality_l05.yaml`, `e05c_quality_l10.yaml`, `e05d_qualitynet.yaml` — nowe
- `tests/unit/data/test_quality_eval.py`, `tests/unit/training/test_quality_metrics.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
class SyntheticQualityDataset(torch.utils.data.Dataset):
    def __init__(self, cfg: RunConfig, corruptions: Sequence[str], *, seed: int = 0,
                 severities: Mapping[str, float] | None = None) -> None: ...
    # wewnątrz: build_dataset(cfg, "val", pipeline=build_pipeline(..., train=False, robustness_corruption=...)) — jeden pipeline na korupcję + wersja czysta
    # próbka jak w PTBXLDataset + "corruption": str ("none" dla wersji czystej)
```

### Testy do napisania

- `test_quality_eval.py`: liczba próbek (2× val), etykiety korupcji, determinizm.
- `test_quality_metrics.py`: metryki jakości liczone tylko przy włączonej głowie; brak wyjątków, gdy etykieta nie ma pozytywów.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_quality_eval.py tests/unit/training/test_quality_metrics.py -q
uv run python scripts/train.py --config configs/experiment/e05b_quality_l05.yaml
```

### Wskazówki i pułapki

- Rzadkie słabe etykiety (np. `burst_noise`) dają niestabilny AUROC na val — raportuj liczność pozytywów obok wyniku.
- Korupcje w treningu zmieniają rozkład wejścia — porównuj diagnozę zawsze na czystym val.

## 🧪 Eksperyment E05 — Multitask z jakością sygnału

**Cel decyzyjny:** czy włączyć głowę jakości / głowy aux · zadania: T303, {{T403}} · właściciel eksperymentu: A · tydzień: 6, 9

**Hipotezy powiązane z eksperymentem:**

- H6: Model wielozadaniowy z zadaniem jakości sygnału jest odporniejszy na artefakty.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** tylko diagnoza; diagnoza + jakość (`lambda_quality ∈ {0.5, 1.0}`, korupcje syntetyczne `p = 0.3`);
  osobny QualityNet; opcjonalnie głowy rhythm/form ({{T403}}).
- **Metryki:** macro AUROC diagnozy na czystym val, macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`, T303), AUROC jakości (syntetyczny val i słabe etykiety), FRR quality gate.
  Krzywe robustness z E06 są raportowane w {{T306}} jako uzupełnienie, nie jako warunek decyzji.
- **Reguła (D-027, status: proponowana):** włączamy głowę jakości, jeśli spadek macro AUROC diagnozy na czystym val ≤ 0,005, a macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`) wzrasta. Głowy aux — analogicznie.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T303-quality-head.md`](https://github.com/__REPO__/blob/main/tasks/T303-quality-head.md)
- Decyzja [D-023](https://github.com/__REPO__/blob/main/docs/decisions.md#d-023--korupcja-robustness-w-build_pipeline-przy-trainfalse) — Korupcja robustness w `build_pipeline` przy `train=False`
- Decyzja [D-027](https://github.com/__REPO__/blob/main/docs/decisions.md#d-027--reguła-decyzyjna-e05-auroc-diagnozy-na-syntetycznym-val) — Reguła decyzyjna E05: AUROC diagnozy na syntetycznym val
- Decyzja [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) — Drobne odstępstwa od specyfikacji
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Metryki `val/quality_auroc_<etykieta>` i `val/quality_auroc_synth_<etykieta>` w MLflow dla runów z głową jakości.
- [ ] `SyntheticQualityDataset` deterministyczny (dwa przebiegi → identyczne tensory) i niezależny od `num_workers`.
- [ ] Cztery warianty E05 zalogowane; tabela w `docs/experiments.md` (E05) wygenerowana przez `summarize_runs.py`.
- [ ] Wniosek E05: decyzja o włączeniu głowy jakości do modelu finalnego według reguły decyzyjnej E05 (D-027: spadek macro AUROC diagnozy na czystym val ≤ 0,005 i wzrost macro AUROC diagnozy
      na syntetycznym val, `predictions_val_qsynth.parquet`), z wartościami liczbowymi w tekście.
- [ ] `predictions_val_qsynth.parquet` gotowy dla {{T304}}.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T303 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T206}} — Ewaluacja checkpointu, pliki predykcji i metryk (tydzień 4, właściciel B)
- {{T207}} — ResNet1D — model główny (E03) (tydzień 4, właściciel B)
- {{T301}} — Słabe etykiety jakości w Dataset i analiza ich wiarygodności (tydzień 5, właściciel A)
- {{T302}} — Biblioteka korupcji syntetycznych z etykietami jakości (tydzień 5, właściciel A)

**Odblokowuje:**

- {{T304}} — Quality gate ACCEPT/WARN/REJECT z regułami twardymi i progami z val (tydzień 6, właściciel A)

**Bramka G4 — Reliability** (tydzień 11): kalibracja i abstention ocenione; quality gate nie degraduje wyników bez kontroli.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T301}}, {{T302}}, {{T303}}, {{T304}}, {{T305}}, {{T306}}, {{T501}}, {{T502}}, {{T504}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T303` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t303-quality-head`; status karty `in_progress` (`python3 scripts/tasks.py set-status T303 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T303]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T303`.

W Claude Code zadanie realizuje komenda `/task T303`.
__ISSUE_BODY_EOF__
}

body_T304() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T304-quality-gate.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

System potrafi jawnie odmówić klasyfikacji słabego sygnału, a koszt tej decyzji (ile rekordów odrzuca, jak zmienia się jakość na pozostałych) jest zmierzony.

| Pole | Wartość |
|---|---|
| Zadanie | **T304** — Quality gate ACCEPT/WARN/REJECT z regułami twardymi i progami z val |
| Epik | Jakość i odporność (`quality`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 6 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G4 — Reliability |
| Eksperyment | E05 |
| Właściciel | A (Data & Signal ML) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§4](https://github.com/__REPO__/blob/main/docs/reliability.md#4-quality-gate) (reguły, wynik, dobór progów, format JSON, wiążące API)
- [`docs/architecture.md`](https://github.com/__REPO__/blob/main/docs/architecture.md) [§7](https://github.com/__REPO__/blob/main/docs/architecture.md#7-statusy-i-semantyka-odpowiedzi) (statusy)
- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§5](https://github.com/__REPO__/blob/main/docs/inference_api.md#5-walidacja-wejścia--kody) (ostrzeżenia `FLAT_LEAD`, `SATURATION`, `QUALITY_WARN`)

## 🛠️ Szczegóły techniczne

### Zakres

- `HardRules` (płaskie odprowadzenia, saturacja) działające na sygnale w mV.
- `QualityGate.decide` łączący reguły i wynik modelu (`quality_score = 1 − max sigmoid`), status = najgorszy z obu.
- `fit_gate_thresholds` według kryteriów §4 i `gate_tradeoff_table` (siatka progów: odsetek odrzuceń, FRR na czystym val,
  wykrywalność korupcji, macro AUROC na zaakceptowanych).
- `scripts/fit_quality_gate.py`: wejście `predictions_val.parquet` + `predictions_val_qsynth.parquet` → `quality_gate.json`, tabela, wykres; log do MLflow (`quality_gate/`).

### Poza zakresem (wiążące)

- Integracja z `Predictor` ({{T610}}).

### Pliki

- `src/cardioai/reliability/__init__.py`, `src/cardioai/reliability/quality_gate.py` — nowe
- `scripts/fit_quality_gate.py` — nowy
- `tests/unit/reliability/test_quality_gate.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
@dataclass
class QualityDecision:
    status: Literal["ACCEPT", "WARN", "REJECT"]
    score: float | None
    artifacts: dict[str, float]
    reasons: list[str]

class HardRules:
    def __init__(self, *, flat_std_mv: float = 0.01, flat_reject_min_leads: int = 3,
                 saturation_fraction: float = 0.02) -> None: ...
    def check(self, signal_mv: np.ndarray) -> tuple[str, list[str]]: ...

class QualityGate:
    def __init__(self, *, t_warn: float, t_reject: float, rules: HardRules, enabled: bool = True) -> None: ...
    def decide(self, quality_probs: np.ndarray | None, signal_mv: np.ndarray) -> QualityDecision: ...
    def to_dict(self) -> dict[str, Any]: ...
    @classmethod
    def from_dict(cls, d: Mapping[str, Any]) -> "QualityGate": ...

def fit_gate_thresholds(scores_clean: np.ndarray, *, max_false_reject: float = 0.02,
                        max_warn: float = 0.10) -> tuple[float, float]: ...   # (t_warn, t_reject)
def gate_tradeoff_table(scores: np.ndarray, *, is_clean: np.ndarray, is_corrupted: np.ndarray,
                        y_true: np.ndarray, y_prob: np.ndarray, grid: Sequence[float]) -> pd.DataFrame: ...
```

### Testy do napisania

- `test_quality_gate.py`: reguły na syntetycznych sygnałach, łączenie statusów, dobór progów na rozkładach znanych z góry, round-trip JSON.

### Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_quality_gate.py -q
uv run python scripts/fit_quality_gate.py --predictions <eval/val/predictions_val.parquet> --synthetic <eval/val/predictions_val_qsynth.parquet>
```

### Wskazówki i pułapki

- „Czysty val” = rekordy bez słabych flag jakości i bez korupcji; to przybliżenie — zaznacz to w raporcie.
- Saturację wykrywaj jako plateau (wiele kolejnych próbek na tej samej wartości ekstremalnej), nie jako samą wysoką amplitudę.

## 🧪 Eksperyment E05 — Multitask z jakością sygnału

**Cel decyzyjny:** czy włączyć głowę jakości / głowy aux · zadania: {{T303}}, {{T403}} · właściciel eksperymentu: A · tydzień: 6, 9

**Hipotezy powiązane z eksperymentem:**

- H6: Model wielozadaniowy z zadaniem jakości sygnału jest odporniejszy na artefakty.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** tylko diagnoza; diagnoza + jakość (`lambda_quality ∈ {0.5, 1.0}`, korupcje syntetyczne `p = 0.3`);
  osobny QualityNet; opcjonalnie głowy rhythm/form ({{T403}}).
- **Metryki:** macro AUROC diagnozy na czystym val, macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`, {{T303}}), AUROC jakości (syntetyczny val i słabe etykiety), FRR quality gate.
  Krzywe robustness z E06 są raportowane w {{T306}} jako uzupełnienie, nie jako warunek decyzji.
- **Reguła (D-027, status: proponowana):** włączamy głowę jakości, jeśli spadek macro AUROC diagnozy na czystym val ≤ 0,005, a macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`) wzrasta. Głowy aux — analogicznie.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T304-quality-gate.md`](https://github.com/__REPO__/blob/main/tasks/T304-quality-gate.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] FRR na czystym val ≤ 2% przy dobranym `t_reject`; `WARN` na czystym val ≤ 10% przy `t_warn`.
- [ ] Tabela trade-off i wykres w MLflow; wybrane progi w `quality_gate.json` zgodnym z `docs/reliability.md` §4.
- [ ] Reguły twarde: 1–2 płaskie odprowadzenia → `WARN` z powodem `FLAT_LEAD`, ≥ 3 → `REJECT`; saturacja → `WARN` (`SATURATION`).
- [ ] `quality_probs=None` (model bez głowy jakości) → decyzja tylko z reguł, `score=None`.
- [ ] `to_dict` → `from_dict` daje identyczne decyzje.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T304 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T303}} — Model jakości — głowa multitask i osobny QualityNet (E05) (tydzień 6, właściciel A)

**Odblokowuje:**

- {{T305}} — Robustness suite — testy odporności z raportem (tydzień 7, właściciel B)
- {{T502}} — Abstention i krzywe risk–coverage (E09, H4) (tydzień 10, właściciel C)
- {{T504}} — Raport niezawodności i przegląd bramki G4 (tydzień 11, właściciel C)
- {{T610}} — Integracja quality gate, kalibracji, abstention i XAI w Predictorze (tydzień 12, właściciel C)

**Bramka G4 — Reliability** (tydzień 11): kalibracja i abstention ocenione; quality gate nie degraduje wyników bez kontroli.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T301}}, {{T302}}, {{T303}}, {{T304}}, {{T305}}, {{T306}}, {{T501}}, {{T502}}, {{T504}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T304` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t304-quality-gate`; status karty `in_progress` (`python3 scripts/tasks.py set-status T304 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(reliability): <description> [T304]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T304`.

W Claude Code zadanie realizuje komenda `/task T304`.
__ISSUE_BODY_EOF__
}

body_T305() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T305-robustness-suite.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Powtarzalny pomiar, jak spada jakość modelu przy brakujących odprowadzeniach, szumie, dryfcie i zmianie preprocessingu — dla każdego kandydata na model finalny.

| Pole | Wartość |
|---|---|
| Zadanie | **T305** — Robustness suite — testy odporności z raportem |
| Epik | Jakość i odporność (`quality`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 7 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G4 — Reliability |
| Eksperyment | E06 |
| Właściciel | B (Model & Experiments) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§8](https://github.com/__REPO__/blob/main/docs/reliability.md#8-robustness-suite) (lista testów, siatki, format CSV)
- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§8](https://github.com/__REPO__/blob/main/docs/data_contract.md#8-próbka-z-dataset-i-pipeline-transformacji) (kroki 3 i 7–8), [§13](https://github.com/__REPO__/blob/main/docs/data_contract.md#13-brakujące-odprowadzenia) (konwencja brakującego odprowadzenia)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E06)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-023](https://github.com/__REPO__/blob/main/docs/decisions.md#d-023--korupcja-robustness-w-build_pipeline-przy-trainfalse)

## 🛠️ Szczegóły techniczne

### Zakres

- `RobustnessTest`, `run_robustness` z wstrzykiwaną funkcją predykcji (bez importu `cardioai.training`, zgodnie z granicami modułów).
- Testy: `missing_lead`, `random_lead_dropout`, `gaussian_noise`, `baseline_drift`, `powerline` (tylko `fs > 100`),
  `electrode_flat`, `preprocessing_shift`, `sampling_rate` — parametry z `configs/robustness/default.yaml`.
- Progi z val zamrożone (`thresholds.json`); opcjonalnie quality gate → kolumna `gate_reject_rate`.
- `scripts/robustness.py --checkpoint PATH --split val [--suite PATH] [--gate PATH]` → `robustness.csv` + wykresy (krzywe degradacji, mapa Δ per odprowadzenie), log do MLflow (`robustness/`).

### Poza zakresem (wiążące)

- Uruchamianie na teście (tylko {{T801}}), trening z lead dropout ({{T306}}).

### Pliki

- `src/cardioai/reliability/robustness.py` — nowy
- `scripts/robustness.py` — nowy
- `configs/robustness/default.yaml` — nowy
- `tests/unit/reliability/test_robustness.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
@dataclass
class RobustnessTest:
    name: str
    values: list[float | int | str]
    repeats: int = 1

PredictFn = Callable[[DataLoader], tuple[np.ndarray, np.ndarray]]   # -> (y_true [N,5], y_prob [N,5])
def run_robustness(predict_fn: PredictFn, make_loader: Callable[[RobustnessTest, Any, int], DataLoader],
                   tests: Sequence[RobustnessTest], *, thresholds: Mapping[str, float],
                   gate: QualityGate | None = None, seed: int = 0) -> pd.DataFrame: ...   # kolumny z docs/reliability.md §8
def load_suite(path: Path) -> list[RobustnessTest]: ...
def plot_degradation(df: pd.DataFrame, out_dir: Path) -> list[Path]: ...
```

### Testy do napisania

- `test_robustness.py`: na fixture z funkcją predykcji-atrapą — kolejność kroków, format CSV, determinizm, pominięcie `powerline` przy 100 Hz.

### Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_robustness.py -q
uv run python scripts/robustness.py --checkpoint <best.pt> --split val
```

### Wskazówki i pułapki

- `make_loader` buduje dataset val przez `build_pipeline(train=False, robustness_corruption=...)` — korupcja testu trafia do kroku 3 (w mV, przed filtrem i normalizacją; D-023); nie mieszaj z augmentacjami.
- `preprocessing_shift` wymaga dwóch statystyk normalizacji (dla wariantu z filtrem i bez) — pliki z {{T107}}/{{T108}}.

## 🧪 Eksperyment E06 — Lead dropout i robustness

**Cel decyzyjny:** odporność kanałowa i na zakłócenia · zadania: T305, {{T306}} · właściciel eksperymentu: B · tydzień: 7

**Hipotezy powiązane z eksperymentem:**

- H3: Lead dropout w treningu zwiększy odporność na brak odprowadzeń bez istotnego spadku na pełnym 12-lead.
- H6: Model wielozadaniowy z zadaniem jakości sygnału jest odporniejszy na artefakty.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** `lead_dropout.p ∈ {0, 0.3, 0.5}`; pełna robustness suite (`docs/reliability.md` §8) dla każdego.
- **Reguła (H3):** wariant z lead dropout przyjmujemy, gdy średni spadek przy 1 brakującym odprowadzeniu maleje co najmniej o połowę,
  a macro AUROC na pełnym 12-lead spada ≤ 0,005.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T305-robustness-suite.md`](https://github.com/__REPO__/blob/main/tasks/T305-robustness-suite.md)
- Decyzja [D-023](https://github.com/__REPO__/blob/main/docs/decisions.md#d-023--korupcja-robustness-w-build_pipeline-przy-trainfalse) — Korupcja robustness w `build_pipeline` przy `train=False`
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Wszystkie testy z `docs/reliability.md` §8 zaimplementowane; `powerline` pomijany z informacją przy 100 Hz.
- [ ] `missing_lead` zeruje odprowadzenie **po** normalizacji (test: wartość 0.0 i `lead_mask=False` na wejściu modelu); korupcje w mV **przed** filtrem.
- [ ] CSV ma kolumny `test, param, value, repeat, metric, score, clean_score, delta, gate_reject_rate`.
- [ ] Wynik deterministyczny dla tego samego seeda.
- [ ] Pełna suite dla ResNet1D na val działa w < 30 min na laptopie z RTX (czas w PR).
- [ ] Odmowa uruchomienia na `test` bez odblokowania.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T305 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T206}} — Ewaluacja checkpointu, pliki predykcji i metryk (tydzień 4, właściciel B)
- {{T302}} — Biblioteka korupcji syntetycznych z etykietami jakości (tydzień 5, właściciel A)
- {{T304}} — Quality gate ACCEPT/WARN/REJECT z regułami twardymi i progami z val (tydzień 6, właściciel A)

**Odblokowuje:**

- {{T306}} — Eksperyment lead dropout i odporność kanałowa (E06, H3) (tydzień 7, właściciel B)
- {{T504}} — Raport niezawodności i przegląd bramki G4 (tydzień 11, właściciel C)

**Bramka G4 — Reliability** (tydzień 11): kalibracja i abstention ocenione; quality gate nie degraduje wyników bez kontroli.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T301}}, {{T302}}, {{T303}}, {{T304}}, {{T305}}, {{T306}}, {{T501}}, {{T502}}, {{T504}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T305` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t305-robustness-suite`; status karty `in_progress` (`python3 scripts/tasks.py set-status T305 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(reliability): <description> [T305]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T305`.

W Claude Code zadanie realizuje komenda `/task T305`.
__ISSUE_BODY_EOF__
}

body_T306() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T306-lead-dropout-experiment.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Odpowiedzieć na H3: czy `lead_dropout` w treningu zwiększa odporność na brak odprowadzeń bez istotnej straty na pełnym 12-lead.

| Pole | Wartość |
|---|---|
| Zadanie | **T306** — Eksperyment lead dropout i odporność kanałowa (E06, H3) |
| Epik | Jakość i odporność (`quality`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 7 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G4 — Reliability |
| Eksperyment | E06 |
| Właściciel | B (Model & Experiments) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§2](https://github.com/__REPO__/blob/main/docs/experiments.md#2-hipotezy) (H3), [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E06 — reguła decyzyjna)
- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§8](https://github.com/__REPO__/blob/main/docs/reliability.md#8-robustness-suite)
- [`docs/config.md`](https://github.com/__REPO__/blob/main/docs/config.md) [§5](https://github.com/__REPO__/blob/main/docs/config.md#5-przykład-configu-eksperymentu) (przykład configu z `lead_dropout`)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-027](https://github.com/__REPO__/blob/main/docs/decisions.md#d-027--reguła-decyzyjna-e05-auroc-diagnozy-na-syntetycznym-val)

## 🛠️ Szczegóły techniczne

### Zakres

- Configi `e06a_leaddrop_p0.yaml`, `e06b_leaddrop_p03.yaml`, `e06c_leaddrop_p05.yaml` (ResNet1D, strata wybrana w E04).
- Trening: seed 0 dla wszystkich wariantów, 3 seedy dla `p = 0` i najlepszego wariantu.
- Robustness suite ({{T305}}) dla każdego wariantu; tabela porównawcza i wykres Δ macro AUROC vs liczba brakujących odprowadzeń.
- Krzywe robustness ({{T305}}) także dla wariantów E05 (`e05a`–`e05d`), jako uzupełnienie wniosku E05 — raportowane, nie są warunkiem decyzji o głowie jakości (D-027).
- Wniosek H3 w `docs/experiments.md` (E06) i decyzja o domyślnej augmentacji w `configs/base.yaml` (wpis w `docs/decisions.md`, jeśli zmiana).

### Poza zakresem (wiążące)

- Nowe typy augmentacji.

### Pliki

- `configs/experiment/e06a_leaddrop_p0.yaml`, `e06b_leaddrop_p03.yaml`, `e06c_leaddrop_p05.yaml` — nowe
- `docs/experiments.md` — aktualizacja (E06)

### Testy do napisania

- Brak nowych testów jednostkowych (zadanie eksperymentalne); configi walidowane przez `load_config` w teście parametryzowanym wszystkich plików `configs/experiment/*.yaml` (dodaj, jeśli nie istnieje).

### Weryfikacja

```bash
uv run python scripts/run_seeds.py --config configs/experiment/e06b_leaddrop_p03.yaml --seeds 0 1 2
uv run python scripts/robustness.py --checkpoint <best.pt> --split val
uv run python scripts/summarize_runs.py --experiment e06_lead_dropout --write-docs E06
```

### Wskazówki i pułapki

- Porównuj warianty na tym samym val i tych samych progach z ich własnego val — nie przenoś progów między modelami.

## 🧪 Eksperyment E06 — Lead dropout i robustness

**Cel decyzyjny:** odporność kanałowa i na zakłócenia · zadania: {{T305}}, T306 · właściciel eksperymentu: B · tydzień: 7

**Hipotezy powiązane z eksperymentem:**

- H3: Lead dropout w treningu zwiększy odporność na brak odprowadzeń bez istotnego spadku na pełnym 12-lead.
- H6: Model wielozadaniowy z zadaniem jakości sygnału jest odporniejszy na artefakty.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** `lead_dropout.p ∈ {0, 0.3, 0.5}`; pełna robustness suite (`docs/reliability.md` §8) dla każdego.
- **Reguła (H3):** wariant z lead dropout przyjmujemy, gdy średni spadek przy 1 brakującym odprowadzeniu maleje co najmniej o połowę,
  a macro AUROC na pełnym 12-lead spada ≤ 0,005.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
4. **Augmentacje tylko w treningu.** W ewaluacji i w inferencji pipeline jest deterministyczny.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T306-lead-dropout-experiment.md`](https://github.com/__REPO__/blob/main/tasks/T306-lead-dropout-experiment.md)
- Decyzja [D-027](https://github.com/__REPO__/blob/main/docs/decisions.md#d-027--reguła-decyzyjna-e05-auroc-diagnozy-na-syntetycznym-val) — Reguła decyzyjna E05: AUROC diagnozy na syntetycznym val
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] Wszystkie warianty zalogowane w MLflow z artefaktami robustness.
- [ ] Tabela E06 wygenerowana (`summarize_runs.py --write-docs E06`) + wykres w artefaktach.
- [ ] Wniosek H3 zgodny z regułą decyzyjną E06 (wartości liczbowe w tekście wniosku).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T306 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T209}} — Uruchamianie wielu seedów i tabele wyników z MLflow (bramka G3) (tydzień 5, właściciel B)
- {{T305}} — Robustness suite — testy odporności z raportem (tydzień 7, właściciel B)

**Odblokowuje:**

- {{T801}} — Zamrożenie konfiguracji i jednorazowa ewaluacja na foldzie 10 (G6) (tydzień 14, właściciel B)

**Bramka G4 — Reliability** (tydzień 11): kalibracja i abstention ocenione; quality gate nie degraduje wyników bez kontroli.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T301}}, {{T302}}, {{T303}}, {{T304}}, {{T305}}, {{T306}}, {{T501}}, {{T502}}, {{T504}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T306` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t306-lead-dropout-experiment`; status karty `in_progress` (`python3 scripts/tasks.py set-status T306 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(configs): <description> [T306]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T306`.

W Claude Code zadanie realizuje komenda `/task T306`.
__ISSUE_BODY_EOF__
}

body_T401() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T401-transformer.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Sprawdzić, czy jawna uwaga długozasięgowa daje przewagę nad silną bazą konwolucyjną przy 10-sekundowym EKG — w uczciwym porównaniu kosztu.

| Pole | Wartość |
|---|---|
| Zadanie | **T401** — Transformer czasowy jako model porównawczy (E07) |
| Epik | Rozszerzenia (`extended`) |
| Poziom | Extended (po ustabilizowaniu Core) |
| Planowany tydzień | 8 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | none |
| Eksperyment | E07 |
| Właściciel | B (Model & Experiments) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§3.3](https://github.com/__REPO__/blob/main/docs/modeling.md#33-transformer--model-porównawczy-e07) (architektura), [§9](https://github.com/__REPO__/blob/main/docs/modeling.md#9-porównywalność-architektur) (porównywalność parametrów i FLOPs)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E07)
- Specyfikacja §5.3

## 🛠️ Szczegóły techniczne

### Zakres

- `ECGTransformerEncoder` według §3.3: patch embedding (`Conv1d` ze `stride = patch_size`), token `[CLS]`, uczone pozycje,
  `nn.TransformerEncoder` (`norm_first=True`, `batch_first=True`, GELU), pooling `cls` lub `mean`, LayerNorm.
- `configs/model/transformer.yaml`, `configs/experiment/e07_transformer.yaml` (wariant `cls` i `mean`).
- Dobór `d_model`/`depth` tak, by stosunek parametrów do ResNet1D był w przedziale 0,5–2,0; FLOPs w tabeli.
- Trening: seed 0 dla obu wariantów poolingu, 3 seedy dla lepszego; preferowane urządzenie: Mac (MPS) do eksploracji, laptop A do runów do tabeli.
- Wniosek E07.

### Poza zakresem (wiążące)

- Pretrening self-supervised, warianty efektywnej uwagi.

### Pliki

- `src/cardioai/models/transformer.py` — nowy
- `configs/model/transformer.yaml`, `configs/experiment/e07_transformer.yaml` — nowe
- `tests/unit/models/test_transformer.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
class TransformerParams(BaseModel):
    patch_size: int = 25
    d_model: int = 256
    depth: int = 6
    nhead: int = 8
    dim_feedforward: int = 1024
    dropout: float = 0.1
    pooling: Literal["cls", "mean"] = "cls"
@register_encoder("transformer", params=TransformerParams)
class ECGTransformerEncoder(Encoder): ...      # out_dim = d_model
```

### Testy do napisania

- `test_transformer.py`: kształty dla 100/500 Hz (`patch_size` 25/125), oba poolingi, walidacja `patch_size`, deterministyczny `eval()`.

### Weryfikacja

```bash
uv run pytest tests/unit/models/test_transformer.py -q
uv run python scripts/train.py --config configs/experiment/e07_transformer.yaml
```

### Wskazówki i pułapki

- Transformery są wrażliwe na `lr` i rozgrzewkę — zacznij od `lr = 1e-4`, `warmup_epochs = 5`.
- Na MPS sprawdź `PYTORCH_ENABLE_MPS_FALLBACK=1`, jeśli któraś operacja uwagi nie jest wspierana.

## 🧪 Eksperyment E07 — Transformer

**Cel decyzyjny:** porównanie biasów indukcyjnych · zadania: T401 · właściciel eksperymentu: B · tydzień: 8

**Hipotezy powiązane z eksperymentem:**

- H1: Residual 1D (ResNet1D) osiągnie wyższą jakość i stabilność niż płytki CNN przy akceptowalnym koszcie inferencji.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** `transformer` (patch 25, `d_model 256`, 6 warstw) z liczbą parametrów w przedziale 0,5–2× ResNet1D; pooling `cls` vs `mean`.
- **Reguła:** raportujemy niezależnie od wyniku; Transformer zastępuje ResNet1D tylko przy przewadze ≥ 0,005 macro AUROC i nie gorszej kalibracji.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T401-transformer.md`](https://github.com/__REPO__/blob/main/tasks/T401-transformer.md)
- Decyzja [D-030](https://github.com/__REPO__/blob/main/docs/decisions.md#d-030--transformer-a-3-rodziny-modeli-opcje-do-rozstrzygnięcia) — Transformer a „3 rodziny modeli” (opcje do rozstrzygnięcia)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] `T % patch_size != 0` → błąd walidacji przy budowie modelu (z sugestią poprawnego `patch_size`).
- [ ] Forward działa na CPU, MPS (Mac) i CUDA; brak ostrzeżeń o nested tensors (`enable_nested_tensor=False`).
- [ ] Stosunek parametrów do ResNet1D w przedziale 0,5–2,0 (albo uzasadnienie w PR).
- [ ] Tabela E07 wygenerowana; wniosek według reguły E07.
- [ ] Jeśli Transformer nie zostanie ukończony, „3 rodziny modeli” z Definition of Done spełniają baseline klasyczny, CNN i ResNet1D — zaznacz to w raporcie (opcje i decyzja zespołu: D-030, status: proponowana).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T401 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T207}} — ResNet1D — model główny (E03) (tydzień 4, właściciel B)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka:** zadanie nie należy do żadnej bramki jakościowej.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T401` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t401-transformer`; status karty `in_progress` (`python3 scripts/tasks.py set-status T401 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(models): <description> [T401]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T401`.

W Claude Code zadanie realizuje komenda `/task T401`.
__ISSUE_BODY_EOF__
}

body_T402() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T402-metadata-fusion.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Zmierzyć wartość danych pozasygnałowych (wiek, płeć, wzrost, waga) i ryzyko uczenia się na skrótach — wynik „tylko EKG” zawsze pozostaje w tabeli głównej.

| Pole | Wartość |
|---|---|
| Zadanie | **T402** — Fuzja metadanych i analiza podgrup (E08, H2) |
| Epik | Rozszerzenia (`extended`) |
| Poziom | Extended (po ustabilizowaniu Core) |
| Planowany tydzień | 9 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | none |
| Eksperyment | E08 |
| Właściciel | B (Model & Experiments) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§12](https://github.com/__REPO__/blob/main/docs/data_contract.md#12-metadane-cechy-pozasygnałowe) (kodowanie metadanych), [§14](https://github.com/__REPO__/blob/main/docs/data_contract.md#14-znane-pułapki-ptb-xl) (braki wzrostu i wagi)
- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§4](https://github.com/__REPO__/blob/main/docs/modeling.md#4-głowy-i-fuzja-metadanych) (`MetadataBranch`, `ConcatFusion`)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-032](https://github.com/__REPO__/blob/main/docs/decisions.md#d-032--bundle-aux_sizes-n_metadata-i-osobna-cecha-age_90plus)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§2](https://github.com/__REPO__/blob/main/docs/experiments.md#2-hipotezy) (H2), [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E08 — warianty i reguła)

## 🛠️ Szczegóły techniczne

### Zakres

- `MetadataEncoder` (`FieldProvider`): dopasowanie standaryzacji na train, wartości + maski braków, zapis/odczyt JSON (`split: "train"`);
  domyślne cechy `["age", "age_90plus", "sex", "height", "weight"]` (`age_90plus` jako osobna cecha; D-032), a `n_metadata` (liczba cech `M`) trafia do `build_model`, checkpointu i bundla.
- `MetadataBranch` i `ConcatFusion` w `cardioai.models.fusion`; obsługa w `build_model` (`n_metadata`), w checkpoincie i w bundlu (`metadata_encoder`).
- Configi: `e08a_ecg_only.yaml`, `e08b_ecg_meta.yaml`, `e08c_meta_only.yaml` (MLP na metadanych — miara siły skrótu).
- Analiza podgrup na val: płeć, wiek (< 40, 40–60, 60–75, > 75) — macro AUROC i ECE per podgrupa; korzysta z `subgroup_metrics` z {{T206}} (`cardioai.evaluation.subgroups`), tu powstaje tylko `scripts/subgroup_analysis.py`.
- Wniosek H2 i decyzja include/exclude.

### Poza zakresem (wiążące)

- Inne metadane (`device`, `site`) jako cechy — tylko w analizie podgrup, jeśli czas pozwoli.

### Pliki

- `src/cardioai/data/metadata.py` — nowy
- `src/cardioai/models/fusion.py` — nowy; `src/cardioai/models/registry.py` — zmiana
- `src/cardioai/training/trainer.py` — zmiana (przekazanie `meta` i `meta_mask` do modelu; jeśli {{T204}} przewiduje do tego punkt rozszerzeń — użyj go)
- `src/cardioai/training/predict.py` — zmiana (`meta` i `meta_mask` w `predict_loader`)
- `src/cardioai/inference/bundle.py` — zmiana (sekcje `metadata` i `metadata_encoder` w `BundleSpec`)
- `src/cardioai/inference/predictor.py` — zmiana (metadane w `Predictor.predict`)
- `scripts/subgroup_analysis.py` — nowy
- `configs/experiment/e08a_ecg_only.yaml`, `e08b_ecg_meta.yaml`, `e08c_meta_only.yaml` — nowe
- `tests/unit/data/test_metadata.py`, `tests/unit/models/test_fusion.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
class MetadataEncoder:                        # FieldProvider -> {"meta": [M], "meta_mask": [M]}
    def __init__(self, features: Sequence[str]) -> None: ...
    def fit(self, train_index: pd.DataFrame) -> "MetadataEncoder": ...   # ValueError, gdy wiersze spoza train
    def __call__(self, row: Mapping[str, Any]) -> dict[str, torch.Tensor]: ...
    def to_dict(self) -> dict[str, Any]: ...
    @classmethod
    def from_dict(cls, d: Mapping[str, Any]) -> "MetadataEncoder": ...

class MetadataBranch(nn.Module): ...          # Linear(2M, hidden) -> GELU -> Linear(hidden, hidden)
class ConcatFusion(nn.Module): ...            # LayerNorm(concat)

# subgroup_metrics(pred, groups, *, min_size=50) — zdefiniowane w T206 (cardioai.evaluation.subgroups)
```

### Testy do napisania

- `test_metadata.py`: dopasowanie na train, maski, wiek 90+ (`age = 90` i osobna cecha `age_90plus = 1`), `M == len(features)`, round-trip JSON.
- `test_fusion.py`: kształty z metadanymi i bez, gradient przez gałąź metadanych.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_metadata.py tests/unit/models/test_fusion.py -q
uv run python scripts/run_seeds.py --config configs/experiment/e08b_ecg_meta.yaml --seeds 0 1 2
uv run python scripts/subgroup_analysis.py --predictions <predictions_val.parquet>
```

### Wskazówki i pułapki

- Wariant `meta_only` używa trywialnego enkodera sygnału (np. `debug_linear` z wyzerowanym wejściem) albo osobnego MLP — opisz wybór w PR.
- Wzrost i waga są w większości puste — model może nauczyć się „brak = coś”; maska jest jawna, ale sprawdź ten efekt w analizie podgrup.

## 🧪 Eksperyment E08 — Fuzja metadanych

**Cel decyzyjny:** wartość danych pozasygnałowych · zadania: T402 · właściciel eksperymentu: B · tydzień: 9

**Hipotezy powiązane z eksperymentem:**

- H2: Fuzja metadanych może poprawić kalibrację i część klas, ale wymaga kontroli shortcut learning.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** tylko EKG; EKG + metadane (`age`, `sex`, `height`, `weight` z maskami); tylko metadane (MLP — miara siły skrótu).
- **Analiza podgrup:** płeć, wiek (< 40, 40–60, 60–75, > 75) — macro AUROC i ECE per podgrupa.
- **Reguła:** metadane włączamy, gdy zysk ≥ 0,005 macro AUROC lub wyraźna poprawa ECE, bez pogłębienia różnic między podgrupami.
  Wynik „tylko EKG” zawsze w tabeli głównej.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T402-metadata-fusion.md`](https://github.com/__REPO__/blob/main/tasks/T402-metadata-fusion.md)
- Decyzja [D-032](https://github.com/__REPO__/blob/main/docs/decisions.md#d-032--bundle-aux_sizes-n_metadata-i-osobna-cecha-age_90plus) — Bundle: `aux_sizes`, `n_metadata` i osobna cecha `age_90plus`
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Statystyki metadanych tylko z train; braki kodowane maską (test: NaN → wartość 0, maska 0).
- [ ] Model z metadanymi zapisuje i odtwarza encoder z checkpointu; bundle zawiera `metadata_encoder`.
- [ ] Trzy warianty E08 (3 seedy dla `ecg_only` i `ecg_meta`) w MLflow; tabela E08 wygenerowana.
- [ ] Tabela podgrup (n, macro AUROC, ECE) dla wariantów `ecg_only` i `ecg_meta`; podgrupy < 50 rekordów oznaczone.
- [ ] Wniosek H2 i decyzja według reguły E08 z liczbami.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T402 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T209}} — Uruchamianie wielu seedów i tabele wyników z MLflow (bramka G3) (tydzień 5, właściciel B)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka:** zadanie nie należy do żadnej bramki jakościowej.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T402` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t402-metadata-fusion`; status karty `in_progress` (`python3 scripts/tasks.py set-status T402 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T402]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T402`.

W Claude Code zadanie realizuje komenda `/task T402`.
__ISSUE_BODY_EOF__
}

body_T403() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T403-aux-heads.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Sprawdzić, czy dodatkowe zadania (stwierdzenia rytmu i formy z PTB-XL) poprawiają reprezentację i wynik na 5 superklasach.

| Pole | Wartość |
|---|---|
| Zadanie | **T403** — Głowy pomocnicze rhythm/form (opcjonalne, E05) |
| Epik | Rozszerzenia (`extended`) |
| Poziom | Extended (po ustabilizowaniu Core) |
| Planowany tydzień | 9 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | none |
| Eksperyment | E05 |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§4](https://github.com/__REPO__/blob/main/docs/data_contract.md#4-etykiety-superklas) (kody rytmu i formy), [§6](https://github.com/__REPO__/blob/main/docs/data_contract.md#6-indeks--schemat) (`scp_codes_json`)
- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§4](https://github.com/__REPO__/blob/main/docs/modeling.md#4-głowy-i-fuzja-metadanych) (głowy aux), [§5](https://github.com/__REPO__/blob/main/docs/modeling.md#5-funkcje-straty) (`lambda_aux`)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E05)

## 🛠️ Szczegóły techniczne

### Zakres

- Wyznaczenie zestawów etykiet: kody z `scp_statements.csv` z `rhythm == 1` oraz `form == 1`, z ≥ 200 pozytywami w train (lista zapisana w JSON).
- `AuxLabelProvider` (`FieldProvider`) zwracający `aux: {"rhythm": [R], "form": [F]}`; rozmiary przekazywane do `build_model(aux_sizes=...)`.
- Zapis list etykiet aux w checkpoincie (w configu modelu), metryki `val/aux_<nazwa>_macro_auroc` dostarczane przez hook `MetricHook` z {{T204}} (`training/hooks_aux.py`, bez zmian w `trainer.py`).
- Config `e05e_aux.yaml` (`heads.aux: ["rhythm", "form"]`, `lambda_aux ∈ {0.3, 1.0}`); wniosek w E05.

### Poza zakresem (wiążące)

- Serwowanie wyników aux w API (bundle może zawierać głowy, ale API zwraca tylko 5 superklas).

### Pliki

- `src/cardioai/data/aux_labels.py` — nowy
- `src/cardioai/training/hooks_aux.py` — nowy (hook metryk aux dla `Trainer.metric_hooks`, {{T204}})
- `scripts/train.py` — zmiana (podpięcie hooka aux, gdy `model.heads.aux` jest niepuste)
- `configs/experiment/e05e_aux.yaml` — nowy
- `tests/unit/data/test_aux_labels.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def select_aux_labels(index: pd.DataFrame, statements: pd.DataFrame, *, kind: Literal["rhythm", "form"],
                      min_positives: int = 200) -> list[str]: ...      # tylko na train
class AuxLabelProvider:                                                 # FieldProvider
    def __init__(self, labels: Mapping[str, Sequence[str]]) -> None: ...
```

### Testy do napisania

- `test_aux_labels.py`: wybór kodów na fixture, `min_positives`, kształty pól `aux`.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_aux_labels.py -q
uv run python scripts/train.py --config configs/experiment/e05e_aux.yaml
```

### Wskazówki i pułapki

- Niektóre kody są jednocześnie rytmem i formą — dopuszczalne, ale nie licz ich podwójnie w jednej głowie.
- Zadanie jest opcjonalne: realizuj po ustabilizowaniu Core (bramka G4 w toku nie może na nim czekać).

## 🧪 Eksperyment E05 — Multitask z jakością sygnału

**Cel decyzyjny:** czy włączyć głowę jakości / głowy aux · zadania: {{T303}}, T403 · właściciel eksperymentu: A · tydzień: 6, 9

**Hipotezy powiązane z eksperymentem:**

- H6: Model wielozadaniowy z zadaniem jakości sygnału jest odporniejszy na artefakty.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** tylko diagnoza; diagnoza + jakość (`lambda_quality ∈ {0.5, 1.0}`, korupcje syntetyczne `p = 0.3`);
  osobny QualityNet; opcjonalnie głowy rhythm/form (T403).
- **Metryki:** macro AUROC diagnozy na czystym val, macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`, {{T303}}), AUROC jakości (syntetyczny val i słabe etykiety), FRR quality gate.
  Krzywe robustness z E06 są raportowane w {{T306}} jako uzupełnienie, nie jako warunek decyzji.
- **Reguła (D-027, status: proponowana):** włączamy głowę jakości, jeśli spadek macro AUROC diagnozy na czystym val ≤ 0,005, a macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`) wzrasta. Głowy aux — analogicznie.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T403-aux-heads.md`](https://github.com/__REPO__/blob/main/tasks/T403-aux-heads.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Listy etykiet wyznaczane wyłącznie z train; zapisane w checkpoincie i odtwarzane przy ewaluacji.
- [ ] Run E05e w MLflow; porównanie macro AUROC superklas z wariantem bez głów aux (te same seedy).
- [ ] Wniosek (włączyć / nie włączać) w `docs/experiments.md` (E05).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T403 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T207}} — ResNet1D — model główny (E03) (tydzień 4, właściciel B)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka:** zadanie nie należy do żadnej bramki jakościowej.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T403` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t403-aux-heads`; status karty `in_progress` (`python3 scripts/tasks.py set-status T403 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T403]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T403`.

W Claude Code zadanie realizuje komenda `/task T403`.
__ISSUE_BODY_EOF__
}

body_T404() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T404-sampling-rate-500hz.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Odpowiedzieć na H5 liczbami: ile kosztuje 500 Hz (czas, pamięć, opóźnienie) i ile daje (macro AUROC, szczególnie STTC).

| Pole | Wartość |
|---|---|
| Zadanie | **T404** — Porównanie 100 Hz vs 500 Hz — jakość a koszt (E10, H5) |
| Epik | Rozszerzenia (`extended`) |
| Poziom | Extended (po ustabilizowaniu Core) |
| Planowany tydzień | 11 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | none |
| Eksperyment | E10 |
| Właściciel | B (Model & Experiments) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§3.2](https://github.com/__REPO__/blob/main/docs/modeling.md#32-resnet1d--model-główny-e03) (wariant 500 Hz o zbliżonym koszcie), [§9](https://github.com/__REPO__/blob/main/docs/modeling.md#9-porównywalność-architektur)
- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§9](https://github.com/__REPO__/blob/main/docs/data_contract.md#9-normalizacja--plik-statystyk) (statystyki per `fs`), [§10](https://github.com/__REPO__/blob/main/docs/data_contract.md#10-cache-sygnałów) (cache 500 Hz, memmap)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§2](https://github.com/__REPO__/blob/main/docs/experiments.md#2-hipotezy) (H5), [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E10)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-009](https://github.com/__REPO__/blob/main/docs/decisions.md#d-009--100-hz-jako-wariant-domyślny)

## 🛠️ Szczegóły techniczne

### Zakres

- Cache 500 Hz i statystyki normalizacji 500 Hz (istniejące skrypty).
- Configi: `e10a_resnet_100hz.yaml` (referencja z E03), `e10b_resnet_500hz.yaml` (ta sama architektura), `e10c_resnet_500hz_stride10.yaml` (`stem_kernel=75`, `stem_stride=10`).
- 3 seedy dla każdego wariantu (o ile czas pozwoli; minimum 1 seed + uzasadnienie).
- Pomiar: czas epoki, szczytowa pamięć GPU (metryka `peak_memory_mb` logowana przez `Trainer` — {{T204}}), opóźnienie inferencji CPU p50 dla batcha 1.
- Tabela E10 i wniosek H5.

### Poza zakresem (wiążące)

- Transformer przy 500 Hz.

### Pliki

- `configs/experiment/e10a_resnet_100hz.yaml`, `e10b_resnet_500hz.yaml`, `e10c_resnet_500hz_stride10.yaml` — nowe
- `docs/experiments.md` — aktualizacja (E10)

### Testy do napisania

- Brak nowych testów jednostkowych poza walidacją configów (test parametryzowany wszystkich `configs/experiment/*.yaml`).

### Weryfikacja

```bash
uv run python scripts/build_cache.py --sampling-rate 500
uv run python scripts/compute_norm_stats.py --config configs/experiment/e10b_resnet_500hz.yaml
uv run python scripts/run_seeds.py --config configs/experiment/e10b_resnet_500hz.yaml --seeds 0 1 2
```

### Wskazówki i pułapki

- Przy 500 Hz `num_workers` ogranicz do 2 na laptopach 16 GB; memmap otwierany leniwie ({{T106}}).
- Porównuj warianty przy tym samym budżecie epok i tej samej stracie.

## 🧪 Eksperyment E10 — 100 vs 500 Hz

**Cel decyzyjny:** koszt vs jakość · zadania: T404 · właściciel eksperymentu: B · tydzień: 11

**Hipotezy powiązane z eksperymentem:**

- H5: 500 Hz nie poprawi jakości proporcjonalnie do 5× większego kosztu.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** ResNet1D 100 Hz; ResNet1D 500 Hz (ta sama architektura, ok. 5× koszt); ResNet1D 500 Hz z `stem_stride=10` (koszt zbliżony do 100 Hz).
- **Metryki:** macro AUROC (per klasa, szczególnie STTC), czas epoki, opóźnienie, pamięć.
- **Reguła (H5):** 500 Hz uzasadnione tylko przy zysku ≥ 0,005 macro AUROC na 3 seedach.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
9. **Losowość jawna:** seed w configu; w kodzie bibliotecznym `np.random.Generator` / `torch.Generator` zamiast globalnego `np.random.*`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T404-sampling-rate-500hz.md`](https://github.com/__REPO__/blob/main/tasks/T404-sampling-rate-500hz.md)
- Decyzja [D-009](https://github.com/__REPO__/blob/main/docs/decisions.md#d-009--100-hz-jako-wariant-domyślny) — 100 Hz jako wariant domyślny
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Trening 500 Hz na laptopie z RTX 2060 bez OOM (AMP, ewentualnie `grad_accum_steps`); RAM < 16 GB dzięki memmap.
- [ ] Tabela E10: macro AUROC (średnia ± std), AUROC STTC, czas epoki, pamięć, opóźnienie, MFLOPs.
- [ ] Wniosek H5 według reguły E10.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T404 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T106}} — Cache sygnałów NPY z dostępem memmap (tydzień 3, właściciel A)
- {{T209}} — Uruchamianie wielu seedów i tabele wyników z MLflow (bramka G3) (tydzień 5, właściciel B)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka:** zadanie nie należy do żadnej bramki jakościowej.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T404` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t404-sampling-rate-500hz`; status karty `in_progress` (`python3 scripts/tasks.py set-status T404 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(configs): <description> [T404]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T404`.

W Claude Code zadanie realizuje komenda `/task T404`.
__ISSUE_BODY_EOF__
}

body_T501() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T501-calibration.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Prawdopodobieństwa modelu dają się interpretować (0,8 ≈ 80% przypadków pozytywnych), a efekt kalibracji jest zmierzony uczciwie (cross-fitting).

| Pole | Wartość |
|---|---|
| Zadanie | **T501** — Kalibracja prawdopodobieństw i diagramy niezawodności (E09) |
| Epik | Wiarygodność (`reliability`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 10 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G4 — Reliability |
| Eksperyment | E09 |
| Właściciel | C (Reliability & Product) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§1](https://github.com/__REPO__/blob/main/docs/reliability.md#1-przegląd) (kolejność dopasowania, cross-fitting), [§5](https://github.com/__REPO__/blob/main/docs/reliability.md#5-kalibracja) (metody, format JSON)
- [`docs/evaluation.md`](https://github.com/__REPO__/blob/main/docs/evaluation.md) [§2](https://github.com/__REPO__/blob/main/docs/evaluation.md#2-metryki-klasyfikacji--definicje) (Brier, ECE), [§3](https://github.com/__REPO__/blob/main/docs/evaluation.md#3-progi-decyzyjne) (progi po kalibracji)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-015](https://github.com/__REPO__/blob/main/docs/decisions.md#d-015--wielokrotne-użycie-foldu-9)

## 🛠️ Szczegóły techniczne

### Zakres

- Protokół `Calibrator` i implementacje `TemperatureScaler` (globalny i per klasa, optymalizacja log T, ograniczenie `[0.05, 20]`),
  `IsotonicCalibrator` (zapis punktów, `np.interp`), `IdentityCalibrator`; serializacja do/z JSON bez pickle.
- `scripts/calibrate.py --predictions predictions_val.parquet --method ...`: dopasowanie na val, ponowny dobór progów na prawdopodobieństwach po kalibracji,
  zapis `calibration.json` i `thresholds.json`, metryki przed/po (Brier, ECE per klasa i macro), wynik cross-fitting (2 połowy val patient-wise),
  reliability diagrams per klasa (15 przedziałów + histogram), log do MLflow (`calibration/`).
- Porównanie metod w E09.

### Poza zakresem (wiążące)

- Abstention ({{T502}}), integracja z `Predictor` ({{T610}}).

### Pliki

- `src/cardioai/reliability/calibration.py` — nowy
- `scripts/calibrate.py` — nowy
- `tests/unit/reliability/test_calibration.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
class Calibrator(Protocol):
    method: str
    def fit(self, logits: np.ndarray, y: np.ndarray) -> "Calibrator": ...
    def predict_proba(self, logits: np.ndarray) -> np.ndarray: ...       # [N, 5]
    def to_dict(self) -> dict[str, Any]: ...

class TemperatureScaler:
    def __init__(self, *, per_class: bool = True, t_min: float = 0.05, t_max: float = 20.0) -> None: ...
class IsotonicCalibrator:
    def __init__(self, *, min_positives: int = 200) -> None: ...         # klasa z < min_positives pozytywami → metoda niedostępna dla całego modelu: ValueError z listą klas
class IdentityCalibrator: ...

def calibrator_from_dict(d: Mapping[str, Any]) -> Calibrator: ...
def cross_fit_calibration(logits: np.ndarray, y: np.ndarray, patient_id: np.ndarray, *, method: str,
                          seed: int = 0, **kwargs: Any) -> dict[str, float]: ...   # metryki out-of-fold
def reliability_diagram(y_true: np.ndarray, y_prob: np.ndarray, *, n_bins: int = 15, ax: Any | None = None) -> Any: ...
```

### Testy do napisania

- `test_calibration.py`: odzyskanie T, round-trip JSON, niezmienność AUROC, isotonic, podział cross-fitting, ograniczenie T.

### Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_calibration.py -q
uv run python scripts/calibrate.py --predictions <eval/val/predictions_val.parquet> --method temperature --per-class
```

### Wskazówki i pułapki

- Optymalizuj w NumPy/SciPy (`minimize`, L-BFGS-B na log T) — to mały problem, nie potrzebuje PyTorch.
- Logity bardzo duże (|z| > 30) → licz BCE stabilnie (`np.logaddexp`).

## 🧪 Eksperyment E09 — Kalibracja i abstention

**Cel decyzyjny:** wiarygodność predykcji · zadania: T501, {{T502}}, {{T504}} · właściciel eksperymentu: C · tydzień: 10–11

**Hipotezy powiązane z eksperymentem:**

- H4: Kalibracja post-hoc i abstention zwiększą wiarygodność kosztem coverage.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** kalibracja `identity` / `temperature` (globalna, per klasa) / `isotonic`; abstention `max_entropy` / `min_margin` / `combined`.
- **Metryki:** Brier, ECE (przed/po, cross-fitting), AURC, selective risk przy coverage 0,95 / 0,90 / 0,80.
- **Reguła:** wybieramy kalibrator z najniższym ECE w cross-fittingu; metodę abstention z najniższym AURC; τ dla coverage 0,90.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T501-calibration.md`](https://github.com/__REPO__/blob/main/tasks/T501-calibration.md)
- Decyzja [D-015](https://github.com/__REPO__/blob/main/docs/decisions.md#d-015--wielokrotne-użycie-foldu-9) — Wielokrotne użycie foldu 9
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Odzyskanie znanej temperatury: logity syntetyczne z prawdziwym T = 2 → dopasowane T w przedziale 1,9–2,1.
- [ ] `predict_proba` po `to_dict` → `calibrator_from_dict` identyczne (tolerancja 1e-7).
- [ ] Temperatura nie zmienia AUROC (test); isotonic jest monotoniczna.
- [ ] Isotonic: jeśli którakolwiek klasa ma < 200 pozytywów, `fit` zgłasza `ValueError` z listą tych klas (metoda niedostępna dla całego modelu, `docs/reliability.md` §5); `calibrate.py` raportuje to czytelnie.
- [ ] Cross-fitting dzieli val patient-wise (żaden pacjent w obu połowach).
- [ ] Tabela E09 (kalibracja): ECE i Brier przed/po dla każdej metody, w tym out-of-fold; wybór metody według reguły E09.
- [ ] `calibration.json` i `thresholds.json` (`on_calibrated: true`) zgodne z formatami z dokumentacji.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T501 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T201}} — Moduł metryk i doboru progów (tydzień 2, właściciel C)
- {{T206}} — Ewaluacja checkpointu, pliki predykcji i metryk (tydzień 4, właściciel B)

**Odblokowuje:**

- {{T502}} — Abstention i krzywe risk–coverage (E09, H4) (tydzień 10, właściciel C)
- {{T504}} — Raport niezawodności i przegląd bramki G4 (tydzień 11, właściciel C)
- {{T610}} — Integracja quality gate, kalibracji, abstention i XAI w Predictorze (tydzień 12, właściciel C)

**Bramka G4 — Reliability** (tydzień 11): kalibracja i abstention ocenione; quality gate nie degraduje wyników bez kontroli.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T301}}, {{T302}}, {{T303}}, {{T304}}, {{T305}}, {{T306}}, {{T501}}, {{T502}}, {{T504}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T501` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t501-calibration`; status karty `in_progress` (`python3 scripts/tasks.py set-status T501 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(reliability): <description> [T501]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T501`.

W Claude Code zadanie realizuje komenda `/task T501`.
__ISSUE_BODY_EOF__
}

body_T502() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T502-abstention.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

System ma jawne prawo do „nie wiem”, a cena tej decyzji (coverage) i zysk (niższe ryzyko na zaakceptowanych) są zmierzone dla kilku miar niepewności.

| Pole | Wartość |
|---|---|
| Zadanie | **T502** — Abstention i krzywe risk–coverage (E09, H4) |
| Epik | Wiarygodność (`reliability`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 10 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G4 — Reliability |
| Eksperyment | E09 |
| Właściciel | C (Reliability & Product) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§1](https://github.com/__REPO__/blob/main/docs/reliability.md#1-przegląd) (cross-fitting), [§6](https://github.com/__REPO__/blob/main/docs/reliability.md#6-abstention) (miary niepewności, polityka, AURC, format JSON)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§2](https://github.com/__REPO__/blob/main/docs/experiments.md#2-hipotezy) (H4), [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E09)
- [`docs/architecture.md`](https://github.com/__REPO__/blob/main/docs/architecture.md) [§7](https://github.com/__REPO__/blob/main/docs/architecture.md#7-statusy-i-semantyka-odpowiedzi) (status `ABSTAIN`)

## 🛠️ Szczegóły techniczne

### Zakres

- Miary `max_entropy`, `min_margin`, `combined` (z `quality_score` z {{T304}}).
- `AbstentionPolicy` z doborem `τ` dla docelowego coverage; serializacja JSON.
- Krzywe risk–coverage (Hamming loss, macro F1, macro AUROC na zaakceptowanych), AURC, tabela przy coverage 1,00 / 0,95 / 0,90 / 0,80, wynik cross-fitting.
- `scripts/abstention_report.py`: wejście predykcje val + `calibration.json` + `thresholds.json` (+ opcjonalnie `quality_gate.json`) → `abstention.json`, wykresy, tabela, MLflow (`abstention/`)
  oraz metryki `val/aurc`, `val/selective_risk_cov095`, `val/selective_risk_cov090`, `val/selective_risk_cov080` (nazwy: `docs/mlops.md` §3, D-029).
- Wniosek H4 w E09.

### Poza zakresem (wiążące)

- Conformal prediction (rozszerzenie po przedmiocie), integracja z `Predictor` ({{T610}}).

### Pliki

- `src/cardioai/reliability/abstention.py` — nowy
- `scripts/abstention_report.py` — nowy
- `tests/unit/reliability/test_abstention.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def uncertainty_scores(probs: np.ndarray, *, method: Literal["max_entropy", "min_margin", "combined"],
                       thresholds: np.ndarray | None = None, quality_score: np.ndarray | None = None) -> np.ndarray: ...  # [N] w [0, 1]

@dataclass
class AbstentionPolicy:
    method: str
    tau: float
    target_coverage: float
    enabled: bool = True
    def should_abstain(self, u: float | np.ndarray) -> bool | np.ndarray: ...
    def to_dict(self) -> dict[str, Any]: ...
    @classmethod
    def from_dict(cls, d: Mapping[str, Any]) -> "AbstentionPolicy": ...

def fit_tau(u_val: np.ndarray, target_coverage: float) -> float: ...
def risk_coverage_curve(y_true: np.ndarray, y_pred: np.ndarray, y_prob: np.ndarray, u: np.ndarray) -> pd.DataFrame: ...
def aurc(curve: pd.DataFrame, risk_col: str = "hamming_loss") -> float: ...
```

### Testy do napisania

- `test_abstention.py`: wartości graniczne miar, `fit_tau`, krzywa i AURC na przykładzie liczonym ręcznie, round-trip JSON.

### Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_abstention.py -q
uv run python scripts/abstention_report.py --predictions <predictions_val.parquet> --calibration <calibration.json> --thresholds <thresholds.json>
```

### Wskazówki i pułapki

- Niepewność licz na prawdopodobieństwach **po kalibracji** i z progami z `thresholds.json` (`on_calibrated: true`).
- Macro AUROC na małym zaakceptowanym podzbiorze bywa niezdefiniowany — raportuj `NaN` zamiast przerywać.

## 🧪 Eksperyment E09 — Kalibracja i abstention

**Cel decyzyjny:** wiarygodność predykcji · zadania: {{T501}}, T502, {{T504}} · właściciel eksperymentu: C · tydzień: 10–11

**Hipotezy powiązane z eksperymentem:**

- H4: Kalibracja post-hoc i abstention zwiększą wiarygodność kosztem coverage.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** kalibracja `identity` / `temperature` (globalna, per klasa) / `isotonic`; abstention `max_entropy` / `min_margin` / `combined`.
- **Metryki:** Brier, ECE (przed/po, cross-fitting), AURC, selective risk przy coverage 0,95 / 0,90 / 0,80.
- **Reguła:** wybieramy kalibrator z najniższym ECE w cross-fittingu; metodę abstention z najniższym AURC; τ dla coverage 0,90.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T502-abstention.md`](https://github.com/__REPO__/blob/main/tasks/T502-abstention.md)
- Decyzja [D-029](https://github.com/__REPO__/blob/main/docs/decisions.md#d-029--nazwy-metryk-mlflow-i-zestaw-metryk-progowych) — Nazwy metryk MLflow i zestaw metryk progowych
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Miary w zakresie [0, 1]; `max_entropy` = 1 dla p = 0,5 i 0 dla p ∈ {0, 1}.
- [ ] `fit_tau` daje coverage na val równe docelowemu ±0,5 p.p.
- [ ] Na danych syntetycznych, gdzie błędy korelują z niepewnością, ryzyko maleje monotonicznie z malejącym coverage (test).
- [ ] Tabela E09 (abstention): AURC i selective risk dla 3 metod, także out-of-fold; wybór metody i `τ` według reguły E09.
- [ ] `abstention.json` zgodny z `docs/reliability.md` §6.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T502 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T304}} — Quality gate ACCEPT/WARN/REJECT z regułami twardymi i progami z val (tydzień 6, właściciel A)
- {{T501}} — Kalibracja prawdopodobieństw i diagramy niezawodności (E09) (tydzień 10, właściciel C)

**Odblokowuje:**

- {{T504}} — Raport niezawodności i przegląd bramki G4 (tydzień 11, właściciel C)
- {{T610}} — Integracja quality gate, kalibracji, abstention i XAI w Predictorze (tydzień 12, właściciel C)

**Bramka G4 — Reliability** (tydzień 11): kalibracja i abstention ocenione; quality gate nie degraduje wyników bez kontroli.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T301}}, {{T302}}, {{T303}}, {{T304}}, {{T305}}, {{T306}}, {{T501}}, {{T502}}, {{T504}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T502` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t502-abstention`; status karty `in_progress` (`python3 scripts/tasks.py set-status T502 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(reliability): <description> [T502]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T502`.

W Claude Code zadanie realizuje komenda `/task T502`.
__ISSUE_BODY_EOF__
}

body_T503() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T503-xai.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Atrybucja predykcji w czasie i po odprowadzeniach, gotowa do wyświetlenia w UI i opisana uczciwie jako wrażliwość modelu.

| Pole | Wartość |
|---|---|
| Zadanie | **T503** — XAI — Integrated Gradients, saliency i agregacje (E11) |
| Epik | Wiarygodność (`reliability`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 8 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | E11 |
| Właściciel | C (Reliability & Product) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§7](https://github.com/__REPO__/blob/main/docs/reliability.md#7-xai) (metody, wiążące API, agregacje, testy poprawności, budżet czasu, komunikat)
- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§7](https://github.com/__REPO__/blob/main/docs/inference_api.md#7-odpowiedź-v1analyze) (pole `explanation`)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§2](https://github.com/__REPO__/blob/main/AGENTS.md#2-zasady-nienaruszalne) pkt 11 (XAI jako atrybucja, nie wyjaśnienie)

## 🛠️ Szczegóły techniczne

### Zakres

- `explain` dla metod `integrated_gradients` (domyślnie Captum; dopuszczalna własna implementacja), `saliency`, `gradient_x_input`.
- Wybór klasy docelowej (§7), agregacje `lead_importance` i `time_attribution`, `convergence_delta`, przygotowanie do API (uśrednienie do ≤ 100 Hz, skala `[-1, 1]`).
- Testy poprawności: kompletność IG; jednorazowy test randomizacji wag w skrypcie raportowym.
- `scripts/explain_record.py --checkpoint PATH --ecg-id ID --split val` → wykres 12 odprowadzeń z nałożoną atrybucją (PNG) do raportu.
- Pomiar czasu na CPU (100 Hz, ResNet1D) w PR.

### Poza zakresem (wiążące)

- Integracja z `Predictor` ({{T610}}) i UI ({{T609}}).

### Pliki

- `src/cardioai/reliability/xai.py` — nowy
- `scripts/explain_record.py` — nowy
- `tests/unit/reliability/test_xai.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
# docs/reliability.md §7: Attribution, explain(...)
def select_target_class(probs: np.ndarray, thresholds: np.ndarray, requested: str | None = None) -> int: ...
def to_api_payload(attr: Attribution, *, fs: int, max_fs: int = 100) -> dict[str, Any]: ...
    # {"method", "target_class", "lead_importance": {lead: float}, "attribution_fs", "attribution": [[...]], "note"}
XAI_NOTE: Final[str]     # stały komunikat z docs/reliability.md §7
```

### Testy do napisania

- `test_xai.py`: kompletność na małej sieci, sumy i zakresy agregacji, wybór klasy, payload, działanie na CPU bez Captum (jeśli własna implementacja) lub z Captum.

### Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_xai.py -q
uv run python scripts/explain_record.py --checkpoint <best.pt> --ecg-id <ID z val> --split val
```

### Wskazówki i pułapki

- Model w `eval()`; gradienty względem wejścia wymagają `x.requires_grad_(True)` — nie zostawiaj włączonych gradientów parametrów (`torch.no_grad` dla wag nie zadziała przy IG, użyj `requires_grad_(False)` na parametrach).
- Baseline „zera” jest zdefiniowany w przestrzeni znormalizowanej — to „średni sygnał”, nie płaska linia 0 mV.

## 🧪 Eksperyment E11 — XAI i benchmark wdrożeniowy

**Cel decyzyjny:** gotowość systemowa · zadania: T503, {{T703}}, {{T704}} · właściciel eksperymentu: C/B/A · tydzień: 11–13

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Zakres:** testy poprawności XAI (kompletność, randomizacja), przykłady atrybucji dla rekordów val,
  opóźnienie p50/p95, przepustowość, pamięć, rozmiar artefaktu dla PyTorch CPU/CUDA/MPS i ONNX (opcjonalnie INT8).
- **Reguła:** kwantyzację INT8 przyjmujemy, gdy spadek macro AUROC ≤ 0,005, a opóźnienie CPU maleje ≥ 30%.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T503-xai.md`](https://github.com/__REPO__/blob/main/tasks/T503-xai.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Kompletność IG: `|Σ A − (f(x) − f(x₀))| / |f(x) − f(x₀)| < 0,05` przy `n_steps = 50` na modelu testowym.
- [ ] `lead_importance` sumuje się do 1; `time_attribution` w [0, 1]; kształty zgodne z §7.
- [ ] Wybór klasy: wskazana → ta; inaczej pozytywna o najwyższym prawdopodobieństwie; inaczej najwyższe prawdopodobieństwo.
- [ ] Payload API ma kształt `[12][≤ 1000]` i `attribution_fs ≤ 100`.
- [ ] Czas IG na CPU dla ResNet1D przy 100 Hz ≤ 1,5 s na rekord (pomiar w PR) albo plan redukcji (`n_steps`, `internal_batch_size`).
- [ ] Wykresy z `explain_record.py` wyłącznie dla rekordów val.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T503 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T108}} — Pipeline preprocessingu, filtry zerofazowe i resampling (tydzień 4, właściciel A)
- {{T207}} — ResNet1D — model główny (E03) (tydzień 4, właściciel B)

**Odblokowuje:**

- {{T610}} — Integracja quality gate, kalibracji, abstention i XAI w Predictorze (tydzień 12, właściciel C)

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T503` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t503-xai`; status karty `in_progress` (`python3 scripts/tasks.py set-status T503 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(reliability): <description> [T503]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T503`.

W Claude Code zadanie realizuje komenda `/task T503`.
__ISSUE_BODY_EOF__
}

body_T504() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T504-reliability-report.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Jeden wygenerowany raport, który pokazuje kompletny obraz niezawodności kandydata na model finalny i jest dowodem zaliczenia bramki G4.

| Pole | Wartość |
|---|---|
| Zadanie | **T504** — Raport niezawodności i przegląd bramki G4 |
| Epik | Wiarygodność (`reliability`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 11 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G4 — Reliability |
| Eksperyment | E09 |
| Właściciel | C (Reliability & Product) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§1](https://github.com/__REPO__/blob/main/docs/reliability.md#1-przegląd) (przegląd komponentów), [§4–§6](https://github.com/__REPO__/blob/main/docs/reliability.md#4-quality-gate)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E05, E09)
- [`tasks/README.md`](https://github.com/__REPO__/blob/main/tasks/README.md) [§5](https://github.com/__REPO__/blob/main/tasks/README.md#5-bramki-jakościowe-g1g6) (G4)

## 🛠️ Szczegóły techniczne

### Zakres

- `scripts/reliability_report.py --run-id ID`: zbiera z runu MLflow (lub lokalnych plików) kalibrację, progi, quality gate, abstention
  i wynik robustness; tworzy `reports/reliability/<run>/report.md` z tabelami i wykresami; loguje do MLflow (`reliability_report/`).
- Sekcje raportu: podsumowanie, kalibracja (przed/po, out-of-fold), progi, quality gate (trade-off), abstention (krzywe, tabela), odporność (skrót), ograniczenia.
- Przegląd G4 przez zespół; notatka w PR.

### Poza zakresem (wiążące)

- Raport końcowy przedmiotu ({{T803}}).

### Pliki

- `scripts/reliability_report.py` — nowy
- `src/cardioai/reliability/report.py` — nowy (składanie sekcji Markdown z gotowych danych)
- `tests/unit/reliability/test_report.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def build_reliability_report(*, calibration: Mapping[str, Any], thresholds: Mapping[str, Any],
                             quality_gate: Mapping[str, Any] | None, abstention: Mapping[str, Any],
                             tables: Mapping[str, pd.DataFrame], figures: Mapping[str, Path]) -> str: ...
```

### Testy do napisania

- `test_report.py`: składanie raportu z danych syntetycznych, obsługa brakującego komponentu.

### Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_report.py -q
uv run python scripts/reliability_report.py --run-id <run_id>
```

### Wskazówki i pułapki

- Raport ma być czytelny dla prowadzącego: każda tabela z jednym zdaniem interpretacji (generowanym z szablonu, nie „z głowy”).
- Metryki z runu czytaj pod nazwami z `docs/mlops.md` §3 (np. `val/aurc`, `val/selective_risk_cov095`, `val/selective_risk_cov090`, `val/selective_risk_cov080`; D-029).

## 🧪 Eksperyment E09 — Kalibracja i abstention

**Cel decyzyjny:** wiarygodność predykcji · zadania: {{T501}}, {{T502}}, T504 · właściciel eksperymentu: C · tydzień: 10–11

**Hipotezy powiązane z eksperymentem:**

- H4: Kalibracja post-hoc i abstention zwiększą wiarygodność kosztem coverage.

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Warianty:** kalibracja `identity` / `temperature` (globalna, per klasa) / `isotonic`; abstention `max_entropy` / `min_margin` / `combined`.
- **Metryki:** Brier, ECE (przed/po, cross-fitting), AURC, selective risk przy coverage 0,95 / 0,90 / 0,80.
- **Reguła:** wybieramy kalibrator z najniższym ECE w cross-fittingu; metodę abstention z najniższym AURC; τ dla coverage 0,90.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
3. **Statystyki tylko z train** (normalizacja, `pos_weight`, standaryzacja metadanych). Progi decyzyjne, kalibrator, progi quality gate i abstention dopasowujemy na val.
5. **Kod niezależny od urządzenia:** urządzenie tylko z `cardioai.utils.device.get_device()`, zakaz `.cuda()` i `torch.float64` w tensorach; AMP to flaga w configu.
6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T504-reliability-report.md`](https://github.com/__REPO__/blob/main/tasks/T504-reliability-report.md)
- Decyzja [D-029](https://github.com/__REPO__/blob/main/docs/decisions.md#d-029--nazwy-metryk-mlflow-i-zestaw-metryk-progowych) — Nazwy metryk MLflow i zestaw metryk progowych
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] Raport generuje się bez ręcznych kroków dla wskazanego runu; brakujący komponent → sekcja „brak danych” zamiast wyjątku.
- [ ] Wszystkie liczby pochodzą z plików JSON/CSV runu (żadnych wartości wpisanych w kod).
- [ ] Bramka G4 przejrzana przez zespół; decyzje (metoda kalibracji, `τ`, progi gate) zapisane w `docs/experiments.md` (E09) i w `docs/decisions.md`, jeśli zmieniają domyślne ustawienia.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T504 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T304}} — Quality gate ACCEPT/WARN/REJECT z regułami twardymi i progami z val (tydzień 6, właściciel A)
- {{T305}} — Robustness suite — testy odporności z raportem (tydzień 7, właściciel B)
- {{T501}} — Kalibracja prawdopodobieństw i diagramy niezawodności (E09) (tydzień 10, właściciel C)
- {{T502}} — Abstention i krzywe risk–coverage (E09, H4) (tydzień 10, właściciel C)

**Odblokowuje:**

- {{T801}} — Zamrożenie konfiguracji i jednorazowa ewaluacja na foldzie 10 (G6) (tydzień 14, właściciel B)

**Bramka G4 — Reliability** (tydzień 11): kalibracja i abstention ocenione; quality gate nie degraduje wyników bez kontroli.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T301}}, {{T302}}, {{T303}}, {{T304}}, {{T305}}, {{T306}}, {{T501}}, {{T502}}, {{T504}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T504` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t504-reliability-report`; status karty `in_progress` (`python3 scripts/tasks.py set-status T504 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(reliability): <description> [T504]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T504`.

W Claude Code zadanie realizuje komenda `/task T504`.
__ISSUE_BODY_EOF__
}

body_T601() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T601-inference-bundle.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Jeden samowystarczalny artefakt z modelem i wszystkimi parametrami potrzebnymi do inferencji — jedyny łącznik między treningiem a serwowaniem.

| Pole | Wartość |
|---|---|
| Zadanie | **T601** — Format bundla inferencyjnego i eksport z checkpointu |
| Epik | Produkt (API/UI) (`product`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 6 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | — |
| Właściciel | B (Model & Experiments) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§1](https://github.com/__REPO__/blob/main/docs/inference_api.md#1-zasady), [§2](https://github.com/__REPO__/blob/main/docs/inference_api.md#2-bundle-inferencyjny) (format, wersjonowanie, sekcje opcjonalne)
- [`docs/modeling.md`](https://github.com/__REPO__/blob/main/docs/modeling.md) [§6](https://github.com/__REPO__/blob/main/docs/modeling.md#6-checkpoint--format) (checkpoint)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-013](https://github.com/__REPO__/blob/main/docs/decisions.md#d-013--checkpoint-ładowany-z-weights_onlytrue), [D-014](https://github.com/__REPO__/blob/main/docs/decisions.md#d-014--bundle-jako-jedyny-interfejs-trening--serwowanie), [D-032](https://github.com/__REPO__/blob/main/docs/decisions.md#d-032--bundle-aux_sizes-n_metadata-i-osobna-cecha-age_90plus)
- [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§4](https://github.com/__REPO__/blob/main/docs/mlops.md#4-rejestr-modeli-i-promocja), [§8](https://github.com/__REPO__/blob/main/docs/mlops.md#8-wydania) (rejestr, wydania)

## 🛠️ Szczegóły techniczne

### Zakres

- `BundleSpec` (Pydantic) odwzorowujący `bundle.json` z §2 (w tym `model.aux_sizes` i `model.n_metadata`); walidacja `bundle_format`, wersji semver, spójności (`classes`, `leads`, `n_samples`, `n_metadata` zgodne z liczbą cech metadanych).
- `save_bundle` i `load_bundle_spec`; zapis `weights.pt` (sam `state_dict`) i wygenerowanego `README.md` bundla.
- `scripts/export_model.py --checkpoint PATH --version X.Y.Z [--calibration] [--thresholds] [--quality-gate] [--abstention] [--out DIR]`;
  sekcje niepodane → postać wyłączona (`identity`, `enabled: false`, progi 0,5 z ostrzeżeniem).
- Opcjonalnie `--log-mlflow`: bundle jako artefakt runu (`bundle/`).

### Poza zakresem (wiążące)

- Ładowanie i predykcja (`Predictor`, {{T603}}), rejestracja pyfunc i aliasy ({{T702}}), ONNX ({{T703}}).

### Pliki

- `src/cardioai/inference/__init__.py`, `src/cardioai/inference/bundle.py` — nowe
- `scripts/export_model.py` — nowy
- `tests/unit/inference/test_bundle.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
BUNDLE_FORMAT: Final = 1
class BundleSpec(BaseModel): ...                         # pola jak bundle.json w docs/inference_api.md §2
def save_bundle(out_dir: Path, *, state_dict: Mapping[str, torch.Tensor], spec: BundleSpec) -> Path: ...
def load_bundle_spec(bundle_dir: Path) -> BundleSpec: ...  # BundleFormatError przy innym bundle_format
def spec_from_checkpoint(checkpoint: Mapping[str, Any], *, model_version: str,
                         calibration: Mapping[str, Any] | None = None, thresholds: Mapping[str, Any] | None = None,
                         quality_gate: Mapping[str, Any] | None = None,
                         abstention: Mapping[str, Any] | None = None) -> BundleSpec: ...
class BundleFormatError(ValueError): ...
```

### Testy do napisania

- `test_bundle.py`: walidacja specyfikacji, wersje, sekcje wyłączone, round-trip, odrzucenie `bundle_format = 2`.

### Weryfikacja

```bash
uv run pytest tests/unit/inference/test_bundle.py -q
uv run python scripts/export_model.py --checkpoint <best.pt> --version 0.1.0 --out models/bundles/resnet1d-0.1.0
```

### Wskazówki i pułapki

- `inference` nie może importować `training` — odczyt checkpointu do eksportu robi skrypt (który może importować wszystko) i przekazuje słownik do `spec_from_checkpoint`.
- Statystyki normalizacji kopiuj do `bundle.json` (`preprocessing.norm_stats`), nie jako ścieżkę do pliku.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T601-inference-bundle.md`](https://github.com/__REPO__/blob/main/tasks/T601-inference-bundle.md)
- Decyzja [D-013](https://github.com/__REPO__/blob/main/docs/decisions.md#d-013--checkpoint-ładowany-z-weights_onlytrue) — Checkpoint ładowany z `weights_only=True`
- Decyzja [D-014](https://github.com/__REPO__/blob/main/docs/decisions.md#d-014--bundle-jako-jedyny-interfejs-trening--serwowanie) — Bundle jako jedyny interfejs trening → serwowanie
- Decyzja [D-032](https://github.com/__REPO__/blob/main/docs/decisions.md#d-032--bundle-aux_sizes-n_metadata-i-osobna-cecha-age_90plus) — Bundle: `aux_sizes`, `n_metadata` i osobna cecha `age_90plus`
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] `bundle.json` przechodzi walidację `BundleSpec` i zawiera wszystkie sekcje z §2 (wyłączone jawnie, gdy brak danych); sekcja `model` ma `aux_sizes` i `n_metadata` (wyznaczone z checkpointu i configu treningu), wystarczające do wywołania `build_model`.
- [ ] `model_version` w formacie `{model}-MAJOR.MINOR.PATCH`; błędny format → błąd.
- [ ] Bundle nie zawiera plików pickle poza `weights.pt` ładowanym `weights_only=True`.
- [ ] `provenance` zawiera `mlflow_run_id`, `git_sha`, `config_hash`, `dataset_version`, foldy, `test_evaluated: false`, metryki val.
- [ ] Round-trip: `save_bundle` → `load_bundle_spec` → identyczny `BundleSpec`.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T601 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T108}} — Pipeline preprocessingu, filtry zerofazowe i resampling (tydzień 4, właściciel A)
- {{T206}} — Ewaluacja checkpointu, pliki predykcji i metryk (tydzień 4, właściciel B)

**Odblokowuje:**

- {{T603}} — Predictor — pipeline inferencji z bundla (tydzień 9, właściciel C)
- {{T703}} — Eksport ONNX i kwantyzacja INT8 (opcjonalne, E11) (tydzień 13, właściciel B)

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T601` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t601-inference-bundle`; status karty `in_progress` (`python3 scripts/tasks.py set-status T601 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(inference): <description> [T601]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T601`.

W Claude Code zadanie realizuje komenda `/task T601`.
__ISSUE_BODY_EOF__
}

body_T604() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T604-api-mock.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Kontrakt API istnieje i działa od tygodnia 3, zanim powstanie prawdziwy model — frontend i backend rozwijają się równolegle na tym samym schemacie.

| Pole | Wartość |
|---|---|
| Zadanie | **T604** — FastAPI v1 z MockPredictorem i typami inferencji (kontrakt-first) |
| Epik | Produkt (API/UI) (`product`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 3 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§3](https://github.com/__REPO__/blob/main/docs/inference_api.md#3-predictor) (typy), [§6](https://github.com/__REPO__/blob/main/docs/inference_api.md#6-endpointy-api) (endpointy), [§7](https://github.com/__REPO__/blob/main/docs/inference_api.md#7-odpowiedź-v1analyze) (odpowiedź), [§8](https://github.com/__REPO__/blob/main/docs/inference_api.md#8-błędy) (błędy), [§9](https://github.com/__REPO__/blob/main/docs/inference_api.md#9-tryb-mock-i-demo) (mock i demo), [§10](https://github.com/__REPO__/blob/main/docs/inference_api.md#10-openapi-i-wersjonowanie) (OpenAPI), [§11](https://github.com/__REPO__/blob/main/docs/inference_api.md#11-prywatność-i-limity) (prywatność, limity)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-018](https://github.com/__REPO__/blob/main/docs/decisions.md#d-018--frontend-bez-mocków-w-przeglądarce), [D-021](https://github.com/__REPO__/blob/main/docs/decisions.md#d-021--rozszerzenie-odpowiedzi-api-względem-specyfikacji), [D-022](https://github.com/__REPO__/blob/main/docs/decisions.md#d-022--demo-bez-bundla-działa-w-trybie-mock), [D-026](https://github.com/__REPO__/blob/main/docs/decisions.md#d-026--tryby-cardioai_predictor-auto-real-mock), [D-028](https://github.com/__REPO__/blob/main/docs/decisions.md#d-028--rekordy-demo-jako-int16-w-µv), [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) (status `REJECTED`)
- Specyfikacja §13.1 (ryzyko „integracja za późno” — API mock od tygodnia 3)

## 🛠️ Szczegóły techniczne

### Zakres

- `cardioai.inference.types`: wszystkie typy z `docs/inference_api.md` §3 (`Issue`, `RawECG`, `ValidatedECG`, `InputValidationError`,
  `QualityResult`, `UncertaintyResult`, `ExplanationResult`, `SignalPayload`, `PredictionResult`, `ModelInfo`, `PredictorProtocol`).
- `MockPredictor`: deterministyczne wyniki zależne od skrótu sygnału, wszystkie trzy statusy osiągalne (np. przez parametr demo), pełny kształt odpowiedzi.
- Aplikacja FastAPI: `create_app(settings)`, `lifespan` ładujący predyktor (mock, gdy `CARDIOAI_PREDICTOR=mock` albo `auto` i brak bundla; `real` bez bundla → `MODEL_NOT_LOADED`; D-026),
  endpointy z §6, modele Pydantic odpowiedzi z §7, koperta błędów z §8 (także dla błędów walidacji żądania), `request_id`, limity rozmiaru, CORS dla dev.
- Demo: `api/demo/` z 5 syntetycznymi rekordami z generatora mini-PTB-XL ({{T102}}) — zastąpione prawdziwymi w {{T605}}.
- `scripts/export_openapi.py` → `api/openapi.json` (commitowany); test sprawdzający aktualność pliku.

### Poza zakresem (wiążące)

- Parsowanie plików użytkownika ({{T602}}) — w trybie mock upload zwraca wynik dla syntetycznego sygnału z ostrzeżeniem; prawdziwy `Predictor` ({{T603}}, {{T605}}).

### Pliki

- `src/cardioai/inference/types.py`, `src/cardioai/inference/mock.py` — nowe
- `api/cardioai_api/main.py`, `settings.py`, `schemas.py`, `errors.py`, `routes/health.py`, `routes/analyze.py`, `routes/demo.py` — nowe
- `api/demo/demo_records.npz`, `api/demo/demo_records.json` — nowe (syntetyczne, małe)
- `api/openapi.json`, `scripts/export_openapi.py` — nowe
- `tests/api/test_endpoints.py`, `tests/api/test_openapi_up_to_date.py` — nowe

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
def create_app(settings: Settings | None = None) -> FastAPI: ...
app = create_app()                       # na poziomie modułu main.py — `uvicorn cardioai_api.main:app`
class Settings(BaseSettings):            # zmienne z docs/environment.md §4 (prefiks CARDIOAI_)
    predictor: Literal["auto", "real", "mock"] = "auto"
    bundle_path: Path = Path("models/bundles/current")
    max_upload_mb: int = 10
    timeout_s: int = 30
    demo_dir: Path = Path("api/demo")
    cors_origins: list[str] = ["http://localhost:5173"]
class MockPredictor:                      # PredictorProtocol
    def __init__(self, *, seed: int = 0) -> None: ...
```

### Testy do napisania

- `test_endpoints.py` (TestClient): każdy endpoint, trzy statusy, błędy, limity, nieznany `ecg_id` → 404.
- `test_openapi_up_to_date.py`: zgodność pliku z `app.openapi()`.

### Weryfikacja

```bash
uv run pytest tests/api -q
CARDIOAI_PREDICTOR=mock uv run uvicorn cardioai_api.main:app --reload
uv run python scripts/export_openapi.py
```

### Wskazówki i pułapki

- `UploadFile` czytaj z limitem (strumieniowo), zanim zapiszesz cokolwiek na dysk.
- `cors_origins: list[str]` jest czytane z `CARDIOAI_CORS_ORIGINS` jako JSON (`["http://localhost:5173"]`), nie jako lista rozdzielona przecinkami (`docs/environment.md` §4).
- Rekordy demo w `.npz` trzymaj jako `int16` w µV (`np.savez_compressed`), ≤ 50 rekordów (D-028) — hook `check-added-large-files` blokuje pliki > 1 MB; przy odczycie konwertuj do `float32` w mV.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T604-api-mock.md`](https://github.com/__REPO__/blob/main/tasks/T604-api-mock.md)
- Decyzja [D-018](https://github.com/__REPO__/blob/main/docs/decisions.md#d-018--frontend-bez-mocków-w-przeglądarce) — Frontend bez mocków w przeglądarce
- Decyzja [D-021](https://github.com/__REPO__/blob/main/docs/decisions.md#d-021--rozszerzenie-odpowiedzi-api-względem-specyfikacji) — Rozszerzenie odpowiedzi API względem specyfikacji
- Decyzja [D-022](https://github.com/__REPO__/blob/main/docs/decisions.md#d-022--demo-bez-bundla-działa-w-trybie-mock) — Demo bez bundla działa w trybie mock
- Decyzja [D-026](https://github.com/__REPO__/blob/main/docs/decisions.md#d-026--tryby-cardioai_predictor-auto-real-mock) — Tryby `CARDIOAI_PREDICTOR`: `auto`, `real`, `mock`
- Decyzja [D-028](https://github.com/__REPO__/blob/main/docs/decisions.md#d-028--rekordy-demo-jako-int16-w-µv) — Rekordy demo jako `int16` w µV
- Decyzja [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) — Drobne odstępstwa od specyfikacji
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Wszystkie endpointy z §6 odpowiadają zgodnie ze schematami; `/v1/health` zwraca `predictor_mode: "mock"`.
- [ ] Odpowiedzi `/v1/analyze` i `/v1/demo/records/{id}/analyze` przechodzą walidację modeli Pydantic dla statusów `OK`, `ABSTAIN`, `REJECTED`.
- [ ] Każdy błąd (także 422 z FastAPI) ma kopertę z §8 i `request_id`.
- [ ] Upload > `max_upload_mb` → 413 `FILE_TOO_LARGE`.
- [ ] `api/openapi.json` aktualny (test porównuje z wygenerowanym schematem).
- [ ] `lint-imports`: `cardioai_api` importuje tylko `cardioai.inference` i `cardioai.constants`.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T604 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T001}} — Szkielet repozytorium, pyproject i narzędzia jakości (tydzień 1, właściciel C)
- {{T102}} — Syntetyczny mini-PTB-XL jako fixture testów (tydzień 1, właściciel A)

**Odblokowuje:**

- {{T602}} — Parsowanie i walidacja wejścia (WFDB, NPZ, CSV) (tydzień 8, właściciel A)
- {{T605}} — Integracja API z prawdziwym Predictorem i rekordami demo (tydzień 12, właściciel C)
- {{T606}} — Frontend — szkielet, klient API z OpenAPI, strony i tryb demo (tydzień 4, właściciel C)

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T604` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t604-api-mock`; status karty `in_progress` (`python3 scripts/tasks.py set-status T604 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(inference): <description> [T604]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T604`.

W Claude Code zadanie realizuje komenda `/task T604`.
__ISSUE_BODY_EOF__
}

body_T602() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T602-input-parsing-validation.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Dowolny dopuszczalny plik od użytkownika zamienia się w sygnał zgodny z kontraktem modelu — albo w jednoznaczny błąd z kodem, który UI potrafi wyjaśnić.

| Pole | Wartość |
|---|---|
| Zadanie | **T602** — Parsowanie i walidacja wejścia (WFDB, NPZ, CSV) |
| Epik | Produkt (API/UI) (`product`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 8 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | — |
| Właściciel | A (Data & Signal ML) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§3](https://github.com/__REPO__/blob/main/docs/inference_api.md#3-predictor) (`RawECG`, `ValidatedECG`, `InputValidationError`), [§4](https://github.com/__REPO__/blob/main/docs/inference_api.md#4-formaty-wejścia) (formaty), [§5](https://github.com/__REPO__/blob/main/docs/inference_api.md#5-walidacja-wejścia--kody) (kody błędów i ostrzeżeń), [§11](https://github.com/__REPO__/blob/main/docs/inference_api.md#11-prywatność-i-limity) (limity)
- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§7](https://github.com/__REPO__/blob/main/docs/data_contract.md#7-sygnał-odczyt-jednostki-kolejność-odprowadzeń) (kolejność odprowadzeń), [§15](https://github.com/__REPO__/blob/main/docs/data_contract.md#15-liczby-kontrolne-i-wyniki-eda) (percentyle amplitud z EDA)

## 🛠️ Szczegóły techniczne

### Zakres

- `parse_upload` dla WFDB (para `.hea` + `.dat` zapisana w katalogu tymczasowym), NPZ i CSV (separator `,` lub `;`).
- `validate_ecg`: liczba i nazwy odprowadzeń (bez rozróżniania wielkości liter, duplikaty), `fs` w [100, 1000] z resamplingiem do `fs` modelu,
  długość (≥ 10 s, dłuższy → pierwsze 10 s), NaN/Inf, jednostki (`UNITS_SUSPECT`), amplitudy (`AMPLITUDE_HIGH`), kolejność `LEADS`.
- Walidacja metadanych (zakresy z §5).
- Wszystkie kody z §5 jako stałe; komunikaty po polsku.
- Progi amplitud z percentyli EDA ({{T110}}) — zmiana względem dokumentacji wymaga wpisu w `docs/decisions.md`.

### Poza zakresem (wiążące)

- Reguły twarde jakości (płaskie odprowadzenia, saturacja — {{T304}}), HTTP ({{T605}}).

### Pliki

- `src/cardioai/inference/input_io.py`, `src/cardioai/inference/validation.py` — nowe
- `tests/unit/inference/test_input_io.py`, `test_validation.py` — nowe
- `tests/fixtures/inputs/` — małe pliki wejściowe generowane w testach (bez binariów w gicie)

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
@dataclass
class UploadedFile:
    filename: str
    content: bytes

def parse_upload(files: Sequence[UploadedFile], *, fs_hint: int | None = None) -> RawECG: ...
def validate_ecg(raw: RawECG, *, target_fs: int, n_seconds: int = 10) -> ValidatedECG: ...
def validate_metadata(meta: Mapping[str, Any]) -> dict[str, float]: ...
ERROR_CODES: Final[Mapping[str, int]]      # kod -> status HTTP (docs/inference_api.md §5)
WARNING_CODES: Final[frozenset[str]]
```

### Testy do napisania

- `test_input_io.py`: trzy formaty, błędne kombinacje plików, uszkodzone pliki.
- `test_validation.py`: wszystkie kody błędów i ostrzeżeń, resampling, przycinanie, metadane.

### Weryfikacja

```bash
uv run pytest tests/unit/inference/test_input_io.py tests/unit/inference/test_validation.py -q
uv run lint-imports
```

### Wskazówki i pułapki

- `wfdb.rdsamp` wymaga ścieżki bez rozszerzenia i obu plików w jednym katalogu — zapisz je w `TemporaryDirectory` pod wspólną nazwą bazową z `.hea`.
- CSV z Excela w polskim locale ma przecinek dziesiętny — zwróć `CORRUPTED_FILE` z podpowiedzią zamiast zgadywać.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T602-input-parsing-validation.md`](https://github.com/__REPO__/blob/main/tasks/T602-input-parsing-validation.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Każdy kod błędu z §5 ma test wywołujący go i sprawdzający status HTTP z `ERROR_CODES`.
- [ ] WFDB z kanałami w innej kolejności → sygnał w kolejności `LEADS`; `AVR` rozpoznane jako `aVR`.
- [ ] Wejście 500 Hz dla modelu 100 Hz → `[12, 1000]` + ostrzeżenie `RESAMPLED`; 12 s → pierwsze 10 s + `SIGNAL_TRUNCATED`.
- [ ] Rekord z PTB-XL (fixture) przechodzi walidację bez ostrzeżeń.
- [ ] Pliki tymczasowe WFDB są usuwane po parsowaniu (test).
- [ ] Moduł nie importuje `training` ani `tracking`.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T602 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T105}} — Odczyt WFDB, PTBXLDataset, DataLoadery i blokada testu (tydzień 2, właściciel A)
- {{T108}} — Pipeline preprocessingu, filtry zerofazowe i resampling (tydzień 4, właściciel A)
- {{T604}} — FastAPI v1 z MockPredictorem i typami inferencji (kontrakt-first) (tydzień 3, właściciel C)

**Odblokowuje:**

- {{T603}} — Predictor — pipeline inferencji z bundla (tydzień 9, właściciel C)

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T602` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t602-input-parsing-validation`; status karty `in_progress` (`python3 scripts/tasks.py set-status T602 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(inference): <description> [T602]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T602`.

W Claude Code zadanie realizuje komenda `/task T602`.
__ISSUE_BODY_EOF__
}

body_T603() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T603-predictor.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

`Predictor.from_bundle(...)` daje wynik identyczny z ewaluacją offline tego samego modelu — to dowód, że API używa zamrożonego preprocessingu (bramka G5).

| Pole | Wartość |
|---|---|
| Zadanie | **T603** — Predictor — pipeline inferencji z bundla |
| Epik | Produkt (API/UI) (`product`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 9 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§1](https://github.com/__REPO__/blob/main/docs/inference_api.md#1-zasady), [§3](https://github.com/__REPO__/blob/main/docs/inference_api.md#3-predictor) (`PredictorProtocol`, `PredictionResult`), [§7](https://github.com/__REPO__/blob/main/docs/inference_api.md#7-odpowiedź-v1analyze) (pola odpowiedzi)
- [`docs/architecture.md`](https://github.com/__REPO__/blob/main/docs/architecture.md) [§6](https://github.com/__REPO__/blob/main/docs/architecture.md#6-przepływ-inferencji) (kroki inferencji), [§7](https://github.com/__REPO__/blob/main/docs/architecture.md#7-statusy-i-semantyka-odpowiedzi) (statusy)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§2](https://github.com/__REPO__/blob/main/AGENTS.md#2-zasady-nienaruszalne) pkt 7 (jedna implementacja preprocessingu)

## 🛠️ Szczegóły techniczne

### Zakres

- Ładowanie bundla: `BundleSpec`, budowa modelu z rejestru, wagi (`weights_only=True`), pipeline `build_pipeline(train=False)` ze statystykami z bundla.
- `validate` (deleguje do `validate_ecg` z `fs` modelu) i `predict`: preprocessing → forward → sigmoid → progi → `PredictionResult` z czasami (`timing_ms`).
- Kroki niezawodności (gate, kalibracja, abstention, XAI) jako komponenty opcjonalne — tu w postaci wyłączonej/identycznościowej; pełna integracja w {{T610}}.
- `ModelInfo` (`predictor_mode: "real"`).

### Poza zakresem (wiążące)

- HTTP ({{T605}}), integracja komponentów niezawodności ({{T610}}), backend ONNX ({{T703}}).

### Pliki

- `src/cardioai/inference/predictor.py` — nowy
- `tests/unit/inference/test_predictor.py` — nowy
- `tests/integration/test_predictor_parity.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```python
class Predictor:                                     # implementuje PredictorProtocol
    @classmethod
    def from_bundle(cls, bundle_dir: Path, *, device: str = "cpu") -> "Predictor": ...
    @property
    def info(self) -> ModelInfo: ...
    def validate(self, raw: RawECG) -> ValidatedECG: ...
    def predict(self, ecg: ValidatedECG, *, metadata: Mapping[str, float] | None = None,
                explain: Literal["auto", "always", "never"] = "auto",
                explain_class: str | None = None) -> PredictionResult: ...
```

### Testy do napisania

- `test_predictor.py`: ładowanie bundla z losowymi wagami (tworzony w teście), kształt wyniku, ostrzeżenia, `explain="never"`.
- `test_predictor_parity.py`: zgodność z `evaluate.py` na fixture.

### Weryfikacja

```bash
uv run pytest tests/unit/inference/test_predictor.py tests/integration/test_predictor_parity.py -q
uv run lint-imports
```

### Wskazówki i pułapki

- Model ustaw w `eval()` i licz w `torch.inference_mode()` (poza XAI, które potrzebuje gradientów).
- Kolejność klas i odprowadzeń bierz z `BundleSpec` i sprawdzaj zgodność z `cardioai.constants` przy ładowaniu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T603-predictor.md`](https://github.com/__REPO__/blob/main/tasks/T603-predictor.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Parzystość: dla 5 rekordów fixture'a prawdopodobieństwa z `Predictor` = prawdopodobieństwa z `scripts/evaluate.py` dla tego samego checkpointu (tolerancja 1e-5).
- [ ] `PredictionResult` kompletny dla statusu `OK` (pola z §3); `signal` zawiera sygnał po walidacji w mV.
- [ ] Bundle z metadanymi: `predict` bez metadanych działa (maski 0); bundle bez metadanych + metadane → ostrzeżenie `METADATA_IGNORED`.
- [ ] Moduł nie importuje `training`, `tracking`, `mlflow` (`lint-imports`).
- [ ] Inicjalizacja z bundla < 3 s na CPU; predykcja bez XAI < 100 ms dla 100 Hz (pomiar w PR).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T603 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T601}} — Format bundla inferencyjnego i eksport z checkpointu (tydzień 6, właściciel B)
- {{T602}} — Parsowanie i walidacja wejścia (WFDB, NPZ, CSV) (tydzień 8, właściciel A)

**Odblokowuje:**

- {{T605}} — Integracja API z prawdziwym Predictorem i rekordami demo (tydzień 12, właściciel C)
- {{T610}} — Integracja quality gate, kalibracji, abstention i XAI w Predictorze (tydzień 12, właściciel C)
- {{T704}} — Benchmark wydajności inferencji (E11) (tydzień 13, właściciel A)

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T603` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t603-predictor`; status karty `in_progress` (`python3 scripts/tasks.py set-status T603 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(inference): <description> [T603]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T603`.

W Claude Code zadanie realizuje komenda `/task T603`.
__ISSUE_BODY_EOF__
}

body_T605() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T605-api-real-predictor.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

API serwuje prawdziwy model z bundla, przyjmuje pliki użytkownika z pełną walidacją i pokazuje rekordy demo z PTB-XL — bez zmiany kontraktu z {{T604}}.

| Pole | Wartość |
|---|---|
| Zadanie | **T605** — Integracja API z prawdziwym Predictorem i rekordami demo |
| Epik | Produkt (API/UI) (`product`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 12 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§5](https://github.com/__REPO__/blob/main/docs/inference_api.md#5-walidacja-wejścia--kody) (kody), [§6–§9](https://github.com/__REPO__/blob/main/docs/inference_api.md#6-endpointy-api), [§11](https://github.com/__REPO__/blob/main/docs/inference_api.md#11-prywatność-i-limity) (prywatność i limity)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-017](https://github.com/__REPO__/blob/main/docs/decisions.md#d-017--rekordy-demo-z-foldu-9) (demo z foldu 9), [D-022](https://github.com/__REPO__/blob/main/docs/decisions.md#d-022--demo-bez-bundla-działa-w-trybie-mock), [D-026](https://github.com/__REPO__/blob/main/docs/decisions.md#d-026--tryby-cardioai_predictor-auto-real-mock), [D-028](https://github.com/__REPO__/blob/main/docs/decisions.md#d-028--rekordy-demo-jako-int16-w-µv) (format rekordów demo)
- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§1](https://github.com/__REPO__/blob/main/docs/data_contract.md#1-źródło-i-licencja) (licencja i przypisanie)

## 🛠️ Szczegóły techniczne

### Zakres

- Tryby `auto` i `real`: ładowanie `Predictor.from_bundle(CARDIOAI_BUNDLE_PATH)` w `lifespan`; `auto` + brak bundla → mock z ostrzeżeniem w logu (D-022, D-026);
  `CARDIOAI_PREDICTOR=real` i brak bundla → `MODEL_NOT_LOADED` (503) na `/v1/analyze`.
- `/v1/analyze`: zapis uploadu do `TemporaryDirectory`, `parse_upload` → `validate` → `predict` w `run_in_threadpool` z limitem czasu (`TIMEOUT`), mapowanie wyniku i błędów.
- `scripts/make_demo_records.py`: do 50 rekordów z foldu 9 (seed, warstwowo po klasach, nie według trafności), 100 Hz, zapis jako `int16` w µV (`np.savez_compressed`);
  gdy plik przekracza 1 MB, skrypt zmniejsza liczbę rekordów (minimum 20); `api/demo/` + plik z przypisaniem PTB-XL (CC BY 4.0).
- Logi strukturalne bez sygnału i metadanych (`request_id`, format, status, czasy).

### Poza zakresem (wiążące)

- Komponenty niezawodności w `Predictor` ({{T610}}), Docker ({{T701}}).

### Pliki

- `api/cardioai_api/main.py`, `routes/analyze.py`, `routes/demo.py` — zmiana
- `scripts/make_demo_records.py` — nowy
- `api/demo/demo_records.npz`, `api/demo/demo_records.json`, `api/demo/ATTRIBUTION.md` — nowe (prawdziwe rekordy demo)
- `tests/api/test_real_mode.py` — nowy

### Testy do napisania

- `test_real_mode.py`: tryb real z bundlem testowym, limit czasu (monkeypatch spowolnienia), sprzątanie plików, logi, 503 bez bundla przy `CARDIOAI_PREDICTOR=real`, mock z ostrzeżeniem przy `auto`.

### Weryfikacja

```bash
uv run pytest tests/api -q
uv run python scripts/make_demo_records.py --n 50 --seed 0
CARDIOAI_BUNDLE_PATH=models/bundles/<wersja> uv run uvicorn cardioai_api.main:app
```

### Wskazówki i pułapki

- `make_demo_records.py` czyta dane przez `cardioai.data` — wywołuj go jako skrypt, nie z kodu API.
- Limit czasu przez `anyio.fail_after` wokół wywołania w puli wątków; sam wątek nie zostanie przerwany — loguj przekroczenie.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T605-api-real-predictor.md`](https://github.com/__REPO__/blob/main/tasks/T605-api-real-predictor.md)
- Decyzja [D-017](https://github.com/__REPO__/blob/main/docs/decisions.md#d-017--rekordy-demo-z-foldu-9) — Rekordy demo z foldu 9
- Decyzja [D-022](https://github.com/__REPO__/blob/main/docs/decisions.md#d-022--demo-bez-bundla-działa-w-trybie-mock) — Demo bez bundla działa w trybie mock
- Decyzja [D-026](https://github.com/__REPO__/blob/main/docs/decisions.md#d-026--tryby-cardioai_predictor-auto-real-mock) — Tryby `CARDIOAI_PREDICTOR`: `auto`, `real`, `mock`
- Decyzja [D-028](https://github.com/__REPO__/blob/main/docs/decisions.md#d-028--rekordy-demo-jako-int16-w-µv) — Rekordy demo jako `int16` w µV
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Test e2e z bundlem o losowych wagach (tworzony w teście): WFDB, NPZ, CSV → 200 i poprawny schemat; błędne pliki → kody z §5.
- [ ] Pliki tymczasowe usunięte po każdym żądaniu, także przy wyjątku (test).
- [ ] Logi nie zawierają wartości sygnału ani metadanych (test na przechwyconych logach).
- [ ] Rekordy demo wyłącznie z foldu 9; wybór deterministyczny (seed w `demo_records.json`); `ATTRIBUTION.md` z cytowaniem z `docs/data_contract.md` §1.
- [ ] Rozmiar plików demo < 1 MB (przy przekroczeniu mniej rekordów, ale ≥ 20); rekordy w `.npz` jako `int16` w µV, API zwraca je jako `float32` w mV (test round-trip).
- [ ] Kontrakt bez zmian: `api/openapi.json` identyczny z wersją z {{T604}} (albo zmiana opisana w `docs/decisions.md`).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T605 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T603}} — Predictor — pipeline inferencji z bundla (tydzień 9, właściciel C)
- {{T604}} — FastAPI v1 z MockPredictorem i typami inferencji (kontrakt-first) (tydzień 3, właściciel C)

**Odblokowuje:**

- {{T701}} — Obrazy Docker, docker compose i reverse proxy (tydzień 13, właściciel C)

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T605` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t605-api-real-predictor`; status karty `in_progress` (`python3 scripts/tasks.py set-status T605 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(api): <description> [T605]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T605`.

W Claude Code zadanie realizuje komenda `/task T605`.
__ISSUE_BODY_EOF__
}

body_T606() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T606-frontend-scaffold.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Działająca aplikacja webowa rozmawiająca z API w trybie mock: upload pliku, lista rekordów demo, strona „O systemie” i stałe zastrzeżenie — szkielet pod komponenty z {{T607}}–{{T609}}.

| Pole | Wartość |
|---|---|
| Zadanie | **T606** — Frontend — szkielet, klient API z OpenAPI, strony i tryb demo |
| Epik | Produkt (API/UI) (`product`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 4 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/frontend.md`](https://github.com/__REPO__/blob/main/docs/frontend.md) [§1–§4](https://github.com/__REPO__/blob/main/docs/frontend.md#1-cel-i-zasady) (zasady, stack, struktura, strony), [§6](https://github.com/__REPO__/blob/main/docs/frontend.md#6-komunikacja-z-api) (komunikacja z API), [§7](https://github.com/__REPO__/blob/main/docs/frontend.md#7-teksty-i-zastrzeżenia) (teksty), [§8](https://github.com/__REPO__/blob/main/docs/frontend.md#8-testy-i-jakość) (testy)
- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§6](https://github.com/__REPO__/blob/main/docs/inference_api.md#6-endpointy-api), [§10](https://github.com/__REPO__/blob/main/docs/inference_api.md#10-openapi-i-wersjonowanie)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-018](https://github.com/__REPO__/blob/main/docs/decisions.md#d-018--frontend-bez-mocków-w-przeglądarce)

## 🛠️ Szczegóły techniczne

### Zakres

- Vite + React + TypeScript (`strict`), ESLint, Prettier, Vitest + Testing Library, React Router, TanStack Query.
- `npm run gen:api` (`openapi-typescript` z `../api/openapi.json` → `src/api/schema.d.ts`) i klient `openapi-fetch` z bazą `/api`.
- Proxy Vite `/api` → `http://localhost:8000` (z usunięciem prefiksu `/api`).
- Strony: Analiza (formularz uploadu z walidacją po stronie klienta: para `.hea`+`.dat`, `.npz`, `.csv` + `sampling_rate`), Demo (lista rekordów),
  O systemie (`ModelInfo`, wersje, przypisanie PTB-XL, zastrzeżenie); `Disclaimer` i baner trybu mock na każdej stronie.
- Teksty w `src/i18n/pl.ts`; mapowanie kodów błędów API na komunikaty.
- Wynik analizy wyświetlany na razie jako sformatowany JSON (komponenty w {{T607}}–{{T609}}).

### Poza zakresem (wiążące)

- Wizualizacja sygnału ({{T607}}), panele wyników ({{T608}}), XAI ({{T609}}), obraz Docker ({{T701}}).

### Pliki

- `web/` — nowy projekt (`package.json`, `vite.config.ts`, `tsconfig.json`, `src/main.tsx`, `src/pages/*`, `src/api/*`, `src/i18n/pl.ts`, `src/components/Disclaimer.tsx`, `src/components/ErrorAlert.tsx`)
- `web/src/fixtures/` — przykładowe odpowiedzi API (kopie przykładów z `docs/inference_api.md` §7)
- `web/tests/` — testy stron

### Testy do napisania

- Testy Vitest: renderowanie stron, zastrzeżenie, obsługa błędów (fetch mockowany w teście jednostkowym — to nie jest mock API w aplikacji).

### Weryfikacja

```bash
cd web && npm ci && npm run gen:api && npm run lint && npm run typecheck && npm test && npm run build
CARDIOAI_PREDICTOR=mock uv run uvicorn cardioai_api.main:app --reload   # w drugim terminalu: cd web && npm run dev
```

### Wskazówki i pułapki

- Node.js w wersji LTS; zablokuj wersje przez `package-lock.json` (commitowany).
- Upload pary WFDB: oba pliki w jednym polu `files` (multiple) — sprawdź, czy `.hea` i `.dat` mają tę samą nazwę bazową przed wysłaniem.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T606-frontend-scaffold.md`](https://github.com/__REPO__/blob/main/tasks/T606-frontend-scaffold.md)
- Decyzja [D-018](https://github.com/__REPO__/blob/main/docs/decisions.md#d-018--frontend-bez-mocków-w-przeglądarce) — Frontend bez mocków w przeglądarce
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] `npm run lint`, `npm run typecheck`, `npm test`, `npm run build` przechodzą.
- [ ] Z backendem w trybie mock: upload pliku NPZ zwraca wynik; lista demo ładuje rekordy; strona „O systemie” pokazuje `model_version` i `predictor_mode`.
- [ ] Zastrzeżenie z `docs/frontend.md` §7 widoczne na każdej stronie (test); baner mock przy `predictor_mode: "mock"`.
- [ ] Błędy API wyświetlane przez `ErrorAlert` z komunikatem z `pl.ts` (test dla 413 i 422).
- [ ] `src/api/schema.d.ts` wygenerowany, nie edytowany ręcznie (nagłówek „generated”).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Frontend: `cd web && npm run lint && npm run typecheck && npm test` bez błędów.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T606 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T604}} — FastAPI v1 z MockPredictorem i typami inferencji (kontrakt-first) (tydzień 3, właściciel C)

**Odblokowuje:**

- {{T607}} — Przeglądarka 12 odprowadzeń (EcgViewer) (tydzień 5, właściciel C)
- {{T702}} — CI/CD pełne — frontend, obrazy, wydania i promocja modelu (tydzień 13, właściciel C)

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T606` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t606-frontend-scaffold`; status karty `in_progress` (`python3 scripts/tasks.py set-status T606 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(web): <description> [T606]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T606`.

W Claude Code zadanie realizuje komenda `/task T606`.
__ISSUE_BODY_EOF__
}

body_T607() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T607-ecg-viewer.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Czytelny, szybki podgląd 12 odprowadzeń z synchronizowanym powiększaniem — podstawa widoku wyniku i nakładki XAI.

| Pole | Wartość |
|---|---|
| Zadanie | **T607** — Przeglądarka 12 odprowadzeń (EcgViewer) |
| Epik | Produkt (API/UI) (`product`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 5 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/frontend.md`](https://github.com/__REPO__/blob/main/docs/frontend.md) [§5](https://github.com/__REPO__/blob/main/docs/frontend.md#5-komponenty) (wymagania `EcgViewer`), [§8](https://github.com/__REPO__/blob/main/docs/frontend.md#8-testy-i-jakość)
- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§7](https://github.com/__REPO__/blob/main/docs/inference_api.md#7-odpowiedź-v1analyze) (pole `signal`)
- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§7](https://github.com/__REPO__/blob/main/docs/data_contract.md#7-sygnał-odczyt-jednostki-kolejność-odprowadzeń) (kolejność `LEADS`, jednostki)

## 🛠️ Szczegóły techniczne

### Zakres

- Komponent `EcgViewer` (Plotly przez `react-plotly.js` + `plotly.js-dist-min`): układy `grid12` (3×4 + opcjonalnie pasek rytmu II) i `stack`,
  wspólna oś czasu w sekundach z synchronizowanym zoom/pan, oś Y w mV, opcjonalna siatka papieru EKG (0,2 s / 0,5 mV), `scattergl` przy 500 Hz.
- Obsługa prop `overlay` (dane atrybucji) jako punkt zaczepienia dla {{T609}} (bez rysowania).
- Podłączenie do strony wyniku (Analiza i Demo).

### Poza zakresem (wiążące)

- Rysowanie atrybucji ({{T609}}), panele wyników ({{T608}}).

### Pliki

- `web/src/components/EcgViewer.tsx` — nowy
- `web/src/components/plotly.ts` — nowy (fabryka komponentu Plotly)
- `web/tests/EcgViewer.test.tsx` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

```typescript
type SignalPayload = components["schemas"]["SignalPayload"];   // z wygenerowanego schema.d.ts
interface EcgViewerProps {
  signal: SignalPayload;
  layout?: "grid12" | "stack";
  showGrid?: boolean;
  overlay?: { fs: number; values: number[][] } | null;          // [12][T'], skala [-1, 1]
  height?: number;
}
export function EcgViewer(props: EcgViewerProps): JSX.Element;
```

### Testy do napisania

- `EcgViewer.test.tsx` (Plotly mockowany): liczba śladów, kolejność i podpisy, przeliczenie osi czasu z `fs`.

### Weryfikacja

```bash
cd web && npm run lint && npm run typecheck && npm test
```

### Wskazówki i pułapki

- Pełny pakiet Plotly ma kilka MB — importuj `plotly.js-dist-min` przez `createPlotlyComponent`.
- Synchronizację osi uzyskasz jednym wykresem z `subplots` i `matches: "x"` — prościej niż 12 osobnych wykresów.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T607-ecg-viewer.md`](https://github.com/__REPO__/blob/main/tasks/T607-ecg-viewer.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Odprowadzenia renderowane i podpisane w kolejności `I, II, III, aVR, aVL, aVF, V1–V6` niezależnie od kolejności w danych (mapowanie po `leads`).
- [ ] Zoom/pan na jednym wykresie przenosi się na pozostałe (wspólna oś X).
- [ ] Render 12×1000 punktów < 500 ms na laptopie zespołu (pomiar w PR); 12×5000 działa płynnie z `scattergl`.
- [ ] Oś Y opisana w mV, oś X w s.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Frontend: `cd web && npm run lint && npm run typecheck && npm test` bez błędów.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T607 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T606}} — Frontend — szkielet, klient API z OpenAPI, strony i tryb demo (tydzień 4, właściciel C)

**Odblokowuje:**

- {{T608}} — Panele wyniku — predykcje, jakość, status, informacje o modelu (tydzień 6, właściciel C)

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T607` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t607-ecg-viewer`; status karty `in_progress` (`python3 scripts/tasks.py set-status T607 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(web): <description> [T607]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T607`.

W Claude Code zadanie realizuje komenda `/task T607`.
__ISSUE_BODY_EOF__
}

body_T608() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T608-result-panels.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Użytkownik rozumie wynik: które klasy są powyżej progów, jak pewny jest model, czy sygnał jest dobrej jakości i kiedy system odmawia odpowiedzi.

| Pole | Wartość |
|---|---|
| Zadanie | **T608** — Panele wyniku — predykcje, jakość, status, informacje o modelu |
| Epik | Produkt (API/UI) (`product`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 6 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/frontend.md`](https://github.com/__REPO__/blob/main/docs/frontend.md) [§5](https://github.com/__REPO__/blob/main/docs/frontend.md#5-komponenty) (komponenty), [§7](https://github.com/__REPO__/blob/main/docs/frontend.md#7-teksty-i-zastrzeżenia) (teksty i zastrzeżenia — wiążące)
- [`docs/architecture.md`](https://github.com/__REPO__/blob/main/docs/architecture.md) [§7](https://github.com/__REPO__/blob/main/docs/architecture.md#7-statusy-i-semantyka-odpowiedzi) (semantyka statusów)
- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§7](https://github.com/__REPO__/blob/main/docs/inference_api.md#7-odpowiedź-v1analyze) (pola odpowiedzi)

## 🛠️ Szczegóły techniczne

### Zakres

- `StatusBanner` (`OK` / `ABSTAIN` / `REJECTED`, tekst + ikona), `PredictionTable` (pasek prawdopodobieństwa, znacznik progu, decyzja, informacja o kalibracji),
  `QualityPanel` (status, wynik, prawdopodobieństwa artefaktów, powody, ostrzeżenia), `ModelInfoPanel` (wersje, `fs`, `timing_ms`, tryb).
- Prezentacja `ABSTAIN`: prawdopodobieństwa wyszarzone z adnotacją; `REJECTED`: brak tabeli predykcji, powody z `signal_quality.reasons`.
- Słownictwo z §7 (żadnego „diagnoza”, „pacjent ma”).
- Dostępność: status nie tylko kolorem, kontrast WCAG AA.

### Poza zakresem (wiążące)

- XAI ({{T609}}).

### Pliki

- `web/src/components/StatusBanner.tsx`, `PredictionTable.tsx`, `QualityPanel.tsx`, `ModelInfoPanel.tsx` — nowe
- `web/src/pages/ResultView.tsx` — nowy lub zmiana
- `web/tests/ResultView.test.tsx` — nowy

### Testy do napisania

- `ResultView.test.tsx`: trzy statusy, ostrzeżenia, brak predykcji przy `REJECTED`, tryb mock.

### Weryfikacja

```bash
cd web && npm run lint && npm run typecheck && npm test
```

### Wskazówki i pułapki

- Typy pól bierz z `schema.d.ts`; nie twórz ręcznych duplikatów interfejsów odpowiedzi.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T608-result-panels.md`](https://github.com/__REPO__/blob/main/tasks/T608-result-panels.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Fixture'y odpowiedzi dla `OK`, `ABSTAIN`, `REJECTED` renderują się zgodnie z `docs/frontend.md` §7 (testy snapshot lub asercje tekstów).
- [ ] W tekstach UI brak słów „diagnoza”/„diagnozuje” (test przeszukujący `pl.ts`).
- [ ] Znacznik progu w `PredictionTable` odpowiada wartości z `thresholds`.
- [ ] Ostrzeżenia z `warnings[]` widoczne z czytelnym komunikatem.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Frontend: `cd web && npm run lint && npm run typecheck && npm test` bez błędów.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T608 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T607}} — Przeglądarka 12 odprowadzeń (EcgViewer) (tydzień 5, właściciel C)

**Odblokowuje:**

- {{T609}} — Nakładka XAI na sygnał i ranking odprowadzeń (tydzień 11, właściciel C)
- {{T701}} — Obrazy Docker, docker compose i reverse proxy (tydzień 13, właściciel C)

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T608` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t608-result-panels`; status karty `in_progress` (`python3 scripts/tasks.py set-status T608 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(web): <description> [T608]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T608`.

W Claude Code zadanie realizuje komenda `/task T608`.
__ISSUE_BODY_EOF__
}

body_T609() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T609-xai-overlay.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Atrybucja jest widoczna w aplikacji dla wybranego rekordu (wymóg Definition of Done), z jasnym zastrzeżeniem, że to wrażliwość modelu, nie przyczyna kliniczna.

| Pole | Wartość |
|---|---|
| Zadanie | **T609** — Nakładka XAI na sygnał i ranking odprowadzeń |
| Epik | Produkt (API/UI) (`product`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 11 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G5 — Product |
| Eksperyment | E11 |
| Właściciel | C (Reliability & Product) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/frontend.md`](https://github.com/__REPO__/blob/main/docs/frontend.md) [§5](https://github.com/__REPO__/blob/main/docs/frontend.md#5-komponenty) (`XaiOverlay`, `LeadImportanceChart`, `ClassSelector`), [§7](https://github.com/__REPO__/blob/main/docs/frontend.md#7-teksty-i-zastrzeżenia) (podpis XAI)
- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§6](https://github.com/__REPO__/blob/main/docs/inference_api.md#6-endpointy-api) (`explain`, `explain_class`), [§7](https://github.com/__REPO__/blob/main/docs/inference_api.md#7-odpowiedź-v1analyze) (pole `explanation`)
- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§7](https://github.com/__REPO__/blob/main/docs/reliability.md#7-xai)

## 🛠️ Szczegóły techniczne

### Zakres

- `XaiOverlay`: atrybucja per odprowadzenie jako tło pod przebiegiem (heatmapa lub kolorowe segmenty) z przełącznikiem i legendą skali `[-1, 1]`.
- `LeadImportanceChart`: ranking 12 odprowadzeń malejąco.
- `ClassSelector`: zmiana klasy → ponowne żądanie z `explain_class` (dla uploadu i demo); stan ładowania.
- Podpis z `docs/frontend.md` §7 zawsze przy nakładce.
- Działa w trybie mock (dane z `MockPredictor`); weryfikacja na prawdziwym modelu po {{T610}}.

### Poza zakresem (wiążące)

- Obliczanie atrybucji ({{T503}}, {{T610}}).

### Pliki

- `web/src/components/XaiOverlay.tsx`, `LeadImportanceChart.tsx`, `ClassSelector.tsx` — nowe
- `web/src/components/EcgViewer.tsx` — zmiana (rysowanie `overlay`)
- `web/tests/Xai.test.tsx` — nowy

### Testy do napisania

- `Xai.test.tsx`: renderowanie z fixture'ą, brak `explanation`, przełącznik, wybór klasy.

### Weryfikacja

```bash
cd web && npm run lint && npm run typecheck && npm test
```

### Wskazówki i pułapki

- Atrybucja ma `attribution_fs ≤ 100`, a sygnał może mieć 500 Hz — mapuj indeksy przez czas w sekundach, nie przez indeks próbki.

## 🧪 Eksperyment E11 — XAI i benchmark wdrożeniowy

**Cel decyzyjny:** gotowość systemowa · zadania: {{T503}}, {{T703}}, {{T704}} · właściciel eksperymentu: C/B/A · tydzień: 11–13

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Zakres:** testy poprawności XAI (kompletność, randomizacja), przykłady atrybucji dla rekordów val,
  opóźnienie p50/p95, przepustowość, pamięć, rozmiar artefaktu dla PyTorch CPU/CUDA/MPS i ONNX (opcjonalnie INT8).
- **Reguła:** kwantyzację INT8 przyjmujemy, gdy spadek macro AUROC ≤ 0,005, a opóźnienie CPU maleje ≥ 30%.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T609-xai-overlay.md`](https://github.com/__REPO__/blob/main/tasks/T609-xai-overlay.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] Nakładka i ranking wyświetlane, gdy `explanation` nie jest `null`; przy `null` — informacja „atrybucja niedostępna dla tego wyniku”.
- [ ] Zmiana klasy wysyła żądanie z `explain_class` i aktualizuje nakładkę.
- [ ] Podpis XAI widoczny zawsze, gdy nakładka jest włączona (test).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Frontend: `cd web && npm run lint && npm run typecheck && npm test` bez błędów.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T609 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T608}} — Panele wyniku — predykcje, jakość, status, informacje o modelu (tydzień 6, właściciel C)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T609` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t609-xai-overlay`; status karty `in_progress` (`python3 scripts/tasks.py set-status T609 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(web): <description> [T609]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T609`.

W Claude Code zadanie realizuje komenda `/task T609`.
__ISSUE_BODY_EOF__
}

body_T610() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T610-predictor-reliability-integration.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Pełny pipeline inferencji z bundla: odrzucanie złej jakości, skalibrowane prawdopodobieństwa, jawne „nie wiem” i atrybucja — dokładnie te komponenty, które dopasowano offline.

| Pole | Wartość |
|---|---|
| Zadanie | **T610** — Integracja quality gate, kalibracji, abstention i XAI w Predictorze |
| Epik | Produkt (API/UI) (`product`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 12 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/architecture.md`](https://github.com/__REPO__/blob/main/docs/architecture.md) [§6](https://github.com/__REPO__/blob/main/docs/architecture.md#6-przepływ-inferencji) (kroki 4–8), [§7](https://github.com/__REPO__/blob/main/docs/architecture.md#7-statusy-i-semantyka-odpowiedzi) (statusy)
- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§4–§7](https://github.com/__REPO__/blob/main/docs/reliability.md#4-quality-gate)
- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§2](https://github.com/__REPO__/blob/main/docs/inference_api.md#2-bundle-inferencyjny) (sekcje bundla), [§7](https://github.com/__REPO__/blob/main/docs/inference_api.md#7-odpowiedź-v1analyze) (pola odpowiedzi)

## 🛠️ Szczegóły techniczne

### Zakres

- Odtworzenie z `BundleSpec`: `QualityGate.from_dict`, `calibrator_from_dict`, progi, `AbstentionPolicy.from_dict`, ustawienia XAI.
- `Predictor.predict`: reguły twarde + głowa jakości → status gate; `REJECT` → `REJECTED` (bez predykcji); kalibracja → progi → niepewność → `ABSTAIN`;
  XAI dla `OK` (lub `explain="always"`), ostrzeżenie `EXPLANATION_SKIPPED` w pozostałych przypadkach; ostrzeżenia `QUALITY_WARN`, `FLAT_LEAD`, `SATURATION`.
- Eksport bundla kandydata z kompletem komponentów (`scripts/export_model.py`) i sprawdzenie w UI (zrzut ekranu XAI do PR).

### Poza zakresem (wiążące)

- Zmiany kontraktu API (jeśli konieczne — zatrzymaj się i zapytaj).

### Pliki

- `src/cardioai/inference/predictor.py` — zmiana
- `tests/unit/inference/test_predictor_reliability.py` — nowy
- `tests/integration/test_predictor_parity.py` — zmiana (parzystość z kalibracją)

### Testy do napisania

- `test_predictor_reliability.py`: trzy statusy, ostrzeżenia, kalibracja, XAI zależne od statusu, komponenty wyłączone.

### Weryfikacja

```bash
uv run pytest tests/unit/inference tests/integration/test_predictor_parity.py -q
uv run python scripts/export_model.py --checkpoint <best.pt> --version 1.0.0 --calibration <...> --thresholds <...> --quality-gate <...> --abstention <...>
```

### Wskazówki i pułapki

- Kolejność jest wiążąca: gate → kalibracja → progi → abstention → XAI. Zmiana kolejności zmienia semantykę statusów.
- XAI liczy gradienty — wykonuj je poza `inference_mode()` i tylko dla jednego rekordu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

6. **Stałe tylko z `cardioai.constants`** (`SUPERCLASSES`, `LEADS`, `QUALITY_LABELS`, `SPLIT_FOLDS`) — nigdy literały ani indeksy kanałów „z głowy”.
7. **Jedna implementacja preprocessingu** (`cardioai.data.preprocessing`) w treningu i inferencji; API nie ma własnej kopii.
8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T610-predictor-reliability-integration.md`](https://github.com/__REPO__/blob/main/tasks/T610-predictor-reliability-integration.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Sygnał z 3 płaskimi odprowadzeniami → `REJECTED`, `predictions = None`, powód `FLAT_LEAD`.
- [ ] Wymuszona wysoka niepewność (model-atrapa zwracający logity ≈ 0) → `ABSTAIN` z `abstain_reasons`.
- [ ] Prawdopodobieństwa skalibrowane zgodne z `scripts/calibrate.py` dla tych samych logitów (tolerancja 1e-6).
- [ ] `explanation` obecne dla `OK`, nieobecne dla `ABSTAIN` przy `explain="auto"`, obecne przy `explain="always"`.
- [ ] Bundle z wyłączonymi komponentami nadal działa (zachowanie z {{T603}}).
- [ ] Zrzut ekranu UI z nakładką XAI dla rekordu demo dołączony do PR.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T610 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T304}} — Quality gate ACCEPT/WARN/REJECT z regułami twardymi i progami z val (tydzień 6, właściciel A)
- {{T501}} — Kalibracja prawdopodobieństw i diagramy niezawodności (E09) (tydzień 10, właściciel C)
- {{T502}} — Abstention i krzywe risk–coverage (E09, H4) (tydzień 10, właściciel C)
- {{T503}} — XAI — Integrated Gradients, saliency i agregacje (E11) (tydzień 8, właściciel C)
- {{T603}} — Predictor — pipeline inferencji z bundla (tydzień 9, właściciel C)

**Odblokowuje:**

- {{T704}} — Benchmark wydajności inferencji (E11) (tydzień 13, właściciel A)
- {{T801}} — Zamrożenie konfiguracji i jednorazowa ewaluacja na foldzie 10 (G6) (tydzień 14, właściciel B)

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T610` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t610-predictor-reliability-integration`; status karty `in_progress` (`python3 scripts/tasks.py set-status T610 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(inference): <description> [T610]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T610`.

W Claude Code zadanie realizuje komenda `/task T610`.
__ISSUE_BODY_EOF__
}

body_T701() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T701-docker-compose.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Demo uruchamiane jedną komendą z czystego checkoutu: frontend i API za reverse proxy, z prawdziwym modelem, gdy bundle jest dostępny, i z wyraźnym trybem mock, gdy go nie ma.

| Pole | Wartość |
|---|---|
| Zadanie | **T701** — Obrazy Docker, docker compose i reverse proxy |
| Epik | Wdrożenie (`deploy`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 13 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§7](https://github.com/__REPO__/blob/main/docs/mlops.md#7-docker-i-compose) (usługi, bundle, tryb mock), [§8](https://github.com/__REPO__/blob/main/docs/mlops.md#8-wydania) (wydania, `fetch_bundle.py`)
- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§9](https://github.com/__REPO__/blob/main/docs/inference_api.md#9-tryb-mock-i-demo), [§11](https://github.com/__REPO__/blob/main/docs/inference_api.md#11-prywatność-i-limity)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-022](https://github.com/__REPO__/blob/main/docs/decisions.md#d-022--demo-bez-bundla-działa-w-trybie-mock), [D-026](https://github.com/__REPO__/blob/main/docs/decisions.md#d-026--tryby-cardioai_predictor-auto-real-mock), [D-033](https://github.com/__REPO__/blob/main/docs/decisions.md#d-033--mlflow-w-extra-tracking), [D-034](https://github.com/__REPO__/blob/main/docs/decisions.md#d-034--modelsbundlescurrent-jako-katalog)
- Specyfikacja §9.3 i Definition of Done („API i UI przez jedno `docker compose up`”)

## 🛠️ Szczegóły techniczne

### Zakres

- `docker/api.Dockerfile`: Python slim, `uv sync --locked --extra cpu --extra api --extra xai --no-dev` (bez extra `tracking` — obraz API nie zawiera MLflow; D-033), użytkownik bez root, `HEALTHCHECK` na `/v1/health`, bez kodu treningowego w warstwie wykonawczej (tylko pakiety potrzebne do inferencji — sprawdź `lint-imports` i rozmiar).
- `docker/web.Dockerfile`: build Node (`npm ci`, `npm run build`) → Caddy z plikami statycznymi; `docker/Caddyfile`: `/api/*` → `api:8000` z usunięciem prefiksu, reszta → SPA.
- `compose.yaml` w katalogu głównym: usługi `api` i `web` (port 8080), bundle `./models/bundles/current:/bundle:ro`; profil `tracking` z MLflow.
- `scripts/fetch_bundle.py --version TAG` (pobiera asset wydania przez `gh release download` lub HTTPS, rozpakowuje do `models/bundles/<model_version>/` i kopiuje do `models/bundles/current/` — zwykły katalog, nie dowiązanie symboliczne; D-034).
- `scripts/smoke_e2e.py`: sprawdza `http://localhost:8080/api/v1/health`, listę demo i analizę jednego rekordu demo.
- `.dockerignore` (bez `data/`, `outputs/`, `mlruns/`, `node_modules/`).

### Poza zakresem (wiążące)

- Publikacja obrazów w GHCR i workflow wydania ({{T702}}).

### Pliki

- `docker/api.Dockerfile`, `docker/web.Dockerfile`, `docker/Caddyfile`, `compose.yaml`, `.dockerignore` — nowe
- `scripts/fetch_bundle.py`, `scripts/smoke_e2e.py` — nowe
- `README.md` — zmiana (sekcja „Demo”)

### Testy do napisania

- `scripts/smoke_e2e.py` jako test ręczny/CI ({{T702}} uruchamia go po zbudowaniu obrazów).

### Weryfikacja

```bash
docker compose up --build -d
uv run python scripts/smoke_e2e.py --base-url http://localhost:8080
docker compose down
```

### Wskazówki i pułapki

- Na macOS z Apple Silicon obrazy budują się dla `linux/arm64` — PyTorch CPU ma wheels dla obu architektur; nie wymuszaj `platform`.
- Nie kopiuj `models/bundles/` do obrazu w trybie dev — tylko montowanie; zapieczenie bundla w obrazie wydania to decyzja {{T702}}.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T701-docker-compose.md`](https://github.com/__REPO__/blob/main/tasks/T701-docker-compose.md)
- Decyzja [D-022](https://github.com/__REPO__/blob/main/docs/decisions.md#d-022--demo-bez-bundla-działa-w-trybie-mock) — Demo bez bundla działa w trybie mock
- Decyzja [D-026](https://github.com/__REPO__/blob/main/docs/decisions.md#d-026--tryby-cardioai_predictor-auto-real-mock) — Tryby `CARDIOAI_PREDICTOR`: `auto`, `real`, `mock`
- Decyzja [D-033](https://github.com/__REPO__/blob/main/docs/decisions.md#d-033--mlflow-w-extra-tracking) — `mlflow` w extra `tracking`
- Decyzja [D-034](https://github.com/__REPO__/blob/main/docs/decisions.md#d-034--modelsbundlescurrent-jako-katalog) — `models/bundles/current` jako katalog
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Z czystego checkoutu bez bundla (domyślne `CARDIOAI_PREDICTOR=auto`): `docker compose up --build` → UI na `http://localhost:8080` w trybie mock z banerem; `smoke_e2e.py` przechodzi.
- [ ] Z bundlem w `models/bundles/current`: `predictor_mode: "real"`, analiza rekordu demo zwraca wynik z XAI; `smoke_e2e.py` przechodzi.
- [ ] Obraz API działa jako użytkownik bez root; rozmiary obrazów podane w PR.
- [ ] Healthcheck API zielony; `web` startuje po zdrowym `api` (`depends_on: condition: service_healthy`).
- [ ] Działa na Windows (Docker Desktop + WSL2) i macOS (potwierdzenie z dwóch maszyn).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T701 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T605}} — Integracja API z prawdziwym Predictorem i rekordami demo (tydzień 12, właściciel C)
- {{T608}} — Panele wyniku — predykcje, jakość, status, informacje o modelu (tydzień 6, właściciel C)

**Odblokowuje:**

- {{T702}} — CI/CD pełne — frontend, obrazy, wydania i promocja modelu (tydzień 13, właściciel C)
- {{T801}} — Zamrożenie konfiguracji i jednorazowa ewaluacja na foldzie 10 (G6) (tydzień 14, właściciel B)

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T701` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t701-docker-compose`; status karty `in_progress` (`python3 scripts/tasks.py set-status T701 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(deploy): <description> [T701]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T701`.

W Claude Code zadanie realizuje komenda `/task T701`.
__ISSUE_BODY_EOF__
}

body_T702() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T702-cicd-release.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Każdy PR sprawdza cały system (Python i frontend), `main` buduje obrazy, a tag `v*` publikuje wersjonowane obrazy i wydanie z bundlem i kartą modelu.

| Pole | Wartość |
|---|---|
| Zadanie | **T702** — CI/CD pełne — frontend, obrazy, wydania i promocja modelu |
| Epik | Wdrożenie (`deploy`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 13 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G5 — Product |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§4](https://github.com/__REPO__/blob/main/docs/mlops.md#4-rejestr-modeli-i-promocja) (rejestr, aliasy, promocja), [§6](https://github.com/__REPO__/blob/main/docs/mlops.md#6-cicd) (pipeline'y), [§8](https://github.com/__REPO__/blob/main/docs/mlops.md#8-wydania) (wydania)
- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§10](https://github.com/__REPO__/blob/main/docs/inference_api.md#10-openapi-i-wersjonowanie) (aktualność `api/openapi.json`)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-022](https://github.com/__REPO__/blob/main/docs/decisions.md#d-022--demo-bez-bundla-działa-w-trybie-mock)

## 🛠️ Szczegóły techniczne

### Zakres

- `ci.yml`: job `web` (`npm ci`, `gen:api` + kontrola różnic, lint, typecheck, test, build); kontrola `api/openapi.json` (`export_openapi.py` + `git diff --exit-code`);
  `mypy` blokujący; na `main` — budowa obrazów bez publikacji i `smoke_e2e.py` w trybie mock.
- `release.yml` (tag `v*`): budowa i publikacja obrazów `api` i `web` w GHCR z tagiem wersji, wydanie GitHub z bundlem (`.zip`), `model_card.md` i skrótem metryk.
- `scripts/promote_model.py --model-version X --alias champion`: rejestracja bundla jako modelu pyfunc `cardioai-diagnosis` w MLflow (wrapper ładujący `Predictor`) i ustawienie aliasu po ręcznej akceptacji.
- Opis procesu promocji w `docs/mlops.md` §4 (aktualizacja, jeśli różni się od planu).

### Poza zakresem (wiążące)

- Wdrożenie na serwer publiczny.

### Pliki

- `.github/workflows/ci.yml` — zmiana; `.github/workflows/release.yml` — nowy
- `scripts/promote_model.py` — nowy
- `src/cardioai/tracking/pyfunc.py` — nowy (wrapper MLflow ładujący `Predictor`; `tracking` może importować `inference`, odwrotnie nie — `AGENTS.md` §3)
- `docs/mlops.md`, `docs/decisions.md` — aktualizacja

### Testy do napisania

- Przebiegi workflow na PR testowym i tagu testowym; test jednostkowy wrappera pyfunc (ładowanie bundla testowego, `predict` na ramce z sygnałem).

### Weryfikacja

```bash
uv run python scripts/export_openapi.py && git diff --exit-code api/openapi.json
uv run python scripts/promote_model.py --model-version resnet1d-1.0.0 --alias candidate
```

### Wskazówki i pułapki

- Publikacja w GHCR wymaga `permissions: packages: write` w workflow.
- Wrapper pyfunc mieszka w `cardioai.tracking`, więc `cardioai.inference` i API nadal nie zależą od `mlflow`.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T702-cicd-release.md`](https://github.com/__REPO__/blob/main/tasks/T702-cicd-release.md)
- Decyzja [D-022](https://github.com/__REPO__/blob/main/docs/decisions.md#d-022--demo-bez-bundla-działa-w-trybie-mock) — Demo bez bundla działa w trybie mock
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] PR ze zmianą frontendu lub API bez regeneracji `openapi.json`/`schema.d.ts` → czerwone CI.
- [ ] Na `main` obrazy budują się, a `smoke_e2e.py` (mock) przechodzi w CI.
- [ ] Tag testowy (np. `v0.9.0-rc1`) publikuje obrazy w GHCR i tworzy wydanie z bundlem i kartą modelu.
- [ ] `promote_model.py` rejestruje wersję w MLflow i ustawia alias `champion` (zrzut z UI MLflow w PR).
- [ ] Czas PR-CI ≤ 15 min.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T702 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T005}} — CI v1 — lint, granice modułów i testy na każdym PR (tydzień 1, właściciel B)
- {{T606}} — Frontend — szkielet, klient API z OpenAPI, strony i tryb demo (tydzień 4, właściciel C)
- {{T701}} — Obrazy Docker, docker compose i reverse proxy (tydzień 13, właściciel C)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T702` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t702-cicd-release`; status karty `in_progress` (`python3 scripts/tasks.py set-status T702 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(tracking): <description> [T702]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T702`.

W Claude Code zadanie realizuje komenda `/task T702`.
__ISSUE_BODY_EOF__
}

body_T703() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T703-onnx-quantization.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Sprawdzić, czy ResNet1D w ONNX Runtime (FP32 i INT8) daje tę samą jakość przy niższym opóźnieniu na CPU — i jeśli tak, udostępnić ten backend w bundlu.

| Pole | Wartość |
|---|---|
| Zadanie | **T703** — Eksport ONNX i kwantyzacja INT8 (opcjonalne, E11) |
| Epik | Wdrożenie (`deploy`) |
| Poziom | Extended (po ustabilizowaniu Core) |
| Planowany tydzień | 13 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | none |
| Eksperyment | E11 |
| Właściciel | B (Model & Experiments) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/inference_api.md`](https://github.com/__REPO__/blob/main/docs/inference_api.md) [§2](https://github.com/__REPO__/blob/main/docs/inference_api.md#2-bundle-inferencyjny) (`model.backend`, `model.onnx` w bundlu)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E11 — reguła akceptacji kwantyzacji)
- Specyfikacja §9.4 (static quantization zalecana dla CNN)

## 🛠️ Szczegóły techniczne

### Zakres

- `scripts/export_onnx.py`: wrapper zwracający `(logits, quality_logits)`, eksport z dynamiczną osią batcha (opset ≥ 17), walidacja `onnx.checker`.
- Test parzystości PyTorch vs ONNX Runtime FP32 (max |Δ logitów| ≤ 1e-4).
- Statyczna kwantyzacja INT8 (format QDQ) z czytnikiem kalibracyjnym na 200 rekordach train; porównanie macro AUROC val i opóźnienia.
- Opcjonalny backend `onnx` w `Predictor` (`model.backend: "onnx"` w bundlu), gdy reguła E11 jest spełniona.

### Poza zakresem (wiążące)

- Kwantyzacja Transformera, eksport mobilny (ExecuTorch).

### Pliki

- `scripts/export_onnx.py` — nowy
- `src/cardioai/inference/onnx_backend.py` — nowy
- `src/cardioai/inference/predictor.py` — zmiana (wybór backendu `onnx`)
- `tests/unit/inference/test_onnx_parity.py` — nowy

### Testy do napisania

- `test_onnx_parity.py` (pomijany bez extra `onnx`): eksport małego modelu, parzystość, dynamiczny batch.

### Weryfikacja

```bash
uv run pytest tests/unit/inference/test_onnx_parity.py -q
uv run python scripts/export_onnx.py --bundle models/bundles/<wersja> --quantize int8
```

### Wskazówki i pułapki

- Eksport w trybie `eval()`; BatchNorm jest wtedy foldowalny i kwantyzacja działa lepiej.
- Kalibracja kwantyzacji wyłącznie na rekordach train — nie val (który służy do oceny).

## 🧪 Eksperyment E11 — XAI i benchmark wdrożeniowy

**Cel decyzyjny:** gotowość systemowa · zadania: {{T503}}, T703, {{T704}} · właściciel eksperymentu: C/B/A · tydzień: 11–13

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Zakres:** testy poprawności XAI (kompletność, randomizacja), przykłady atrybucji dla rekordów val,
  opóźnienie p50/p95, przepustowość, pamięć, rozmiar artefaktu dla PyTorch CPU/CUDA/MPS i ONNX (opcjonalnie INT8).
- **Reguła:** kwantyzację INT8 przyjmujemy, gdy spadek macro AUROC ≤ 0,005, a opóźnienie CPU maleje ≥ 30%.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T703-onnx-quantization.md`](https://github.com/__REPO__/blob/main/tasks/T703-onnx-quantization.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Parzystość FP32 na 20 rekordach fixture'a: max |Δ| ≤ 1e-4.
- [ ] Tabela E11: macro AUROC val (PyTorch FP32, ORT FP32, ORT INT8), opóźnienie p50/p95, rozmiar pliku.
- [ ] Decyzja według reguły E11 zapisana w `docs/experiments.md`.
- [ ] Bundle z `backend: "onnx"` ładuje się w `Predictor`; bez `onnxruntime` w środowisku — czytelny błąd.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T703 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T601}} — Format bundla inferencyjnego i eksport z checkpointu (tydzień 6, właściciel B)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka:** zadanie nie należy do żadnej bramki jakościowej.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T703` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t703-onnx-quantization`; status karty `in_progress` (`python3 scripts/tasks.py set-status T703 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(inference): <description> [T703]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T703`.

W Claude Code zadanie realizuje komenda `/task T703`.
__ISSUE_BODY_EOF__
}

body_T704() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T704-runtime-benchmark.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Liczby wydajności do raportu i karty modelu, zmierzone powtarzalnie na każdym urządzeniu zespołu.

| Pole | Wartość |
|---|---|
| Zadanie | **T704** — Benchmark wydajności inferencji (E11) |
| Epik | Wdrożenie (`deploy`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 13 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G5 — Product |
| Eksperyment | E11 |
| Właściciel | A (Data & Signal ML) |
| Recenzent | B (Model & Experiments) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- Specyfikacja §7.3 (metryki runtime: latency p50/p95, throughput, RAM/VRAM, rozmiar artefaktu)
- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§4](https://github.com/__REPO__/blob/main/docs/experiments.md#4-karty-eksperymentów) (E11)
- [`docs/environment.md`](https://github.com/__REPO__/blob/main/docs/environment.md) [§1](https://github.com/__REPO__/blob/main/docs/environment.md#1-sprzęt-zespołu-i-podział-pracy) (sprzęt)

## 🛠️ Szczegóły techniczne

### Zakres

- `scripts/benchmark_runtime.py --bundle PATH --device {cpu,cuda,mps} [--backend torch|onnx]`:
  rozgrzewka 20 przebiegów, 200 pomiarów batch=1 (p50, p95), przepustowość dla batch=32, szczytowa pamięć (RAM — `psutil`; VRAM — `torch.cuda.max_memory_allocated`),
  rozmiar bundla, czas `Predictor.predict` z XAI i bez.
- Wynik: CSV + tabela Markdown; log do MLflow (`exp_id=E11`); tabela w `docs/experiments.md` (E11).
- Pomiary na: laptopie A (CPU, CUDA), Macu (CPU, MPS).

### Poza zakresem (wiążące)

- Optymalizacje modelu ({{T703}}).

### Pliki

- `scripts/benchmark_runtime.py` — nowy
- `docs/experiments.md` — aktualizacja (E11)

### Testy do napisania

- Smoke na fixture z bundlem testowym (`--n-runs 5`) — kończy się bez błędu i zapisuje CSV.

### Weryfikacja

```bash
uv run python scripts/benchmark_runtime.py --bundle models/bundles/<wersja> --device cpu
```

### Wskazówki i pułapki

- Na CUDA mierz z `torch.cuda.synchronize()` przed odczytem czasu.
- Laptopy: zasilacz podłączony, tryb wysokiej wydajności, zamknięte inne programy — zapisz to w opisie wyników.

## 🧪 Eksperyment E11 — XAI i benchmark wdrożeniowy

**Cel decyzyjny:** gotowość systemowa · zadania: {{T503}}, {{T703}}, T704 · właściciel eksperymentu: C/B/A · tydzień: 11–13

Karta eksperymentu z `docs/experiments.md` §4 (reguła decyzyjna jest ustalona **przed** uruchomieniem):

- **Zakres:** testy poprawności XAI (kompletność, randomizacja), przykłady atrybucji dla rekordów val,
  opóźnienie p50/p95, przepustowość, pamięć, rozmiar artefaktu dla PyTorch CPU/CUDA/MPS i ONNX (opcjonalnie INT8).
- **Reguła:** kwantyzację INT8 przyjmujemy, gdy spadek macro AUROC ≤ 0,005, a opóźnienie CPU maleje ≥ 30%.

Liczby do raportu pochodzą z MLflow przez `scripts/summarize_runs.py` (tabele między znacznikami `BEGIN/END` w `docs/experiments.md`) — nie wpisuj ich ręcznie (`AGENTS.md` §10). Wniosek zapisz w sekcji „Wniosek” eksperymentu.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

8. **Dane i artefakty poza gitem** (`data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/`, `*.pt`, `*.onnx`, `*.npy`); jedyny wyjątek to małe rekordy demo w `api/demo/`.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
12. **Prywatność w API:** pliki użytkownika tylko w katalogu tymczasowym na czas żądania; nie logujemy sygnałów ani metadanych pacjenta.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T704-runtime-benchmark.md`](https://github.com/__REPO__/blob/main/tasks/T704-runtime-benchmark.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] Tabela E11 z wynikami z co najmniej dwóch urządzeń i dwóch backendów (CPU + GPU/MPS).
- [ ] Pomiary powtarzalne: dwa uruchomienia różnią się w p50 o < 10% (w przeciwnym razie opis przyczyny).
- [ ] Wersje bibliotek i urządzenie zapisane obok wyników (`collect_env_info`).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T704 review`); PR zatwierdzony przez recenzenta (B); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T603}} — Predictor — pipeline inferencji z bundla (tydzień 9, właściciel C)
- {{T610}} — Integracja quality gate, kalibracji, abstention i XAI w Predictorze (tydzień 12, właściciel C)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka G5 — Product** (tydzień 13): API/UI używają zamrożonego preprocessingu z bundla; test end-to-end działa.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T503}}, {{T601}}, {{T602}}, {{T603}}, {{T604}}, {{T605}}, {{T606}}, {{T607}}, {{T608}}, {{T609}}, {{T610}}, {{T701}}, {{T702}}, {{T704}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T704` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t704-runtime-benchmark`; status karty `in_progress` (`python3 scripts/tasks.py set-status T704 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(docs): <description> [T704]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T704`.

W Claude Code zadanie realizuje komenda `/task T704`.
__ISSUE_BODY_EOF__
}

body_T801() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T801-freeze-final-test.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Wiarygodny wynik końcowy: test użyty dokładnie raz, po formalnym zamrożeniu modeli, progów i kalibracji, z przedziałami ufności i pełnym śladem audytowym.

| Pole | Wartość |
|---|---|
| Zadanie | **T801** — Zamrożenie konfiguracji i jednorazowa ewaluacja na foldzie 10 (G6) |
| Epik | Finalizacja (`final`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 14 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G6 — Final |
| Eksperyment | — |
| Właściciel | B (Model & Experiments) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/evaluation.md`](https://github.com/__REPO__/blob/main/docs/evaluation.md) [§7](https://github.com/__REPO__/blob/main/docs/evaluation.md#7-blokada-testu-i-protokół-finalny) (blokada testu, checklista), [§8](https://github.com/__REPO__/blob/main/docs/evaluation.md#8-przedziały-ufności-bootstrap) (bootstrap pacjentów)
- [`docs/reliability.md`](https://github.com/__REPO__/blob/main/docs/reliability.md) [§8](https://github.com/__REPO__/blob/main/docs/reliability.md#8-robustness-suite) (robustness na teście — tylko tutaj)
- [`AGENTS.md`](https://github.com/__REPO__/blob/main/AGENTS.md) [§2](https://github.com/__REPO__/blob/main/AGENTS.md#2-zasady-nienaruszalne) pkt 2
- Specyfikacja, Załącznik B (checklista przed finalnym testem)

## 🛠️ Szczegóły techniczne

### Zakres

- `scripts/final_checklist.py`: automatyczne sprawdzenie punktów z `docs/evaluation.md` §7 (niezmienniki indeksu, źródło statystyk, `fitted_on: "val"`,
  kompletne `provenance` bundli, czyste drzewo git, ≥ 3 seedy rodziny finalnej, brak wpisów w `release/final_test_log.jsonl`), lista modeli do oceny,
  akceptacja A/B/C (pola w pliku) → `release/final_freeze.json` (commitowany).
- Przedziały ufności z `cardioai.evaluation.bootstrap` (bootstrap pacjentów, B = 1000, seed 0, wariant sparowany) — moduł powstaje w {{T209}}, tu tylko z niego korzystamy.
- `scripts/final_test.py`: wymaga `CARDIOAI_ALLOW_TEST=1` i pliku zamrożenia; dla każdego zamrożonego bundla jednorazowo: predykcje i metryki testu,
  przedziały ufności, robustness suite na teście, tag `stage=final`, wpis w `release/final_test_log.jsonl`; kolejne uruchomienie dla tego samego bundla → odmowa.
- Tabela wyników testu w `docs/experiments.md` §5 i w `docs/model_card.md` ({{T802}} korzysta).

### Poza zakresem (wiążące)

- Jakiekolwiek zmiany modeli po zamrożeniu — wymagają nowego wydania i opisu w raporcie jako ograniczenie.

### Pliki

- `scripts/final_checklist.py`, `scripts/final_test.py` — nowe
- `src/cardioai/data/test_lock.py` — zmiana (walidacja treści `final_freeze.json`)
- `release/final_freeze.json`, `release/final_test_log.jsonl` — nowe (commitowane)
- `tests/unit/data/test_test_lock_final.py` — nowy

### Interfejs (wiążący — implementuj dokładnie: nazwy, sygnatury, kształty)

Funkcje `patient_bootstrap` i `paired_patient_bootstrap` (`cardioai.evaluation.bootstrap`) są zdefiniowane w {{T209}}; T801 ich używa bez zmian sygnatur.

### Testy do napisania

- `test_test_lock_final.py`: odmowa bez pliku, bez zmiennej, przy niepoprawnej treści pliku, przy powtórnej ocenie tego samego bundla.

### Weryfikacja

```bash
uv run pytest tests/unit/data/test_test_lock_final.py -q
uv run python scripts/final_checklist.py
CARDIOAI_ALLOW_TEST=1 uv run python scripts/final_test.py --freeze release/final_freeze.json
```

### Wskazówki i pułapki

- Uruchom na urządzeniu kanonicznym (laptop A, D-019) z czystym drzewem git.
- Zanim ustawisz `CARDIOAI_ALLOW_TEST=1`, zrób przegląd zamrożenia z całym zespołem — to jednorazowa operacja.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T801-freeze-final-test.md`](https://github.com/__REPO__/blob/main/tasks/T801-freeze-final-test.md)
- Decyzja [D-019](https://github.com/__REPO__/blob/main/docs/decisions.md#d-019--kanoniczne-urządzenie-dla-wyników-finalnych) — Kanoniczne urządzenie dla wyników finalnych
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] `final_checklist.py` przechodzi bez wyjątków; każdy punkt checklisty ma wynik OK/FAIL w raporcie.
- [ ] `final_freeze.json` zawiera wersje bundli, `config_hash`, git SHA, datę i akceptacje A, B, C.
- [ ] Test oceniony dokładnie raz na bundel (log + tag MLflow `stage=final`); drugie uruchomienie → odmowa.
- [ ] Tabela: macro/micro AUROC, macro F1, AP, per klasa, 95% CI z bootstrapu pacjentów (moduł z {{T209}}), ECE i coverage przy `τ`.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T801 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T209}} — Uruchamianie wielu seedów i tabele wyników z MLflow (bramka G3) (tydzień 5, właściciel B)
- {{T306}} — Eksperyment lead dropout i odporność kanałowa (E06, H3) (tydzień 7, właściciel B)
- {{T504}} — Raport niezawodności i przegląd bramki G4 (tydzień 11, właściciel C)
- {{T610}} — Integracja quality gate, kalibracji, abstention i XAI w Predictorze (tydzień 12, właściciel C)
- {{T701}} — Obrazy Docker, docker compose i reverse proxy (tydzień 13, właściciel C)

**Odblokowuje:**

- {{T802}} — Karta modelu, README i instrukcja reprodukcji (tydzień 14, właściciel C)
- {{T803}} — Artefakty raportu końcowego — tabele i wykresy (tydzień 14, właściciel A)

**Bramka G6 — Final** (tydzień 14): konfiguracja zamrożona przed foldem 10; karta modelu i wyniki reprodukowalne.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T801}}, {{T802}}, {{T803}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T801` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t801-freeze-final-test`; status karty `in_progress` (`python3 scripts/tasks.py set-status T801 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(data): <description> [T801]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T801`.

W Claude Code zadanie realizuje komenda `/task T801`.
__ISSUE_BODY_EOF__
}

body_T802() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T802-model-card-readme.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Ktoś spoza zespołu (prowadzący) uruchamia demo i odtwarza wyniki z README, a karta modelu uczciwie opisuje przeznaczenie, wyniki i ograniczenia.

| Pole | Wartość |
|---|---|
| Zadanie | **T802** — Karta modelu, README i instrukcja reprodukcji |
| Epik | Finalizacja (`final`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 14 z 14 |
| Rozmiar | S (do pół dnia, ok. 0,5 osobodnia) |
| Bramka | G6 — Final |
| Eksperyment | — |
| Właściciel | C (Reliability & Product) |
| Recenzent | A (Data & Signal ML) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/model_card.md`](https://github.com/__REPO__/blob/main/docs/model_card.md) (szablon)
- [`docs/data_contract.md`](https://github.com/__REPO__/blob/main/docs/data_contract.md) [§1](https://github.com/__REPO__/blob/main/docs/data_contract.md#1-źródło-i-licencja) (cytowanie i licencja)
- [`docs/environment.md`](https://github.com/__REPO__/blob/main/docs/environment.md) [§2](https://github.com/__REPO__/blob/main/docs/environment.md#2-instalacja-wszystkie-systemy), [§5](https://github.com/__REPO__/blob/main/docs/environment.md#5-dane-na-każdej-maszynie); [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§8](https://github.com/__REPO__/blob/main/docs/mlops.md#8-wydania)
- [`docs/decisions.md`](https://github.com/__REPO__/blob/main/docs/decisions.md): [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) (karta modelu w tygodniu 14)
- Specyfikacja §13.2 (Definition of Done: README, model card, ograniczenia, reprodukcja)

## 🛠️ Szczegóły techniczne

### Zakres

- Wypełnienie `docs/model_card.md` danymi z `release/final_test_log.jsonl`, `metrics_test.json`, raportu niezawodności i robustness (liczby z plików, bez przepisywania „z pamięci”).
- README: opis i zastrzeżenie, architektura (link do `docs/architecture.md`), szybki start (demo przez `docker compose`), dane, reprodukcja wyników
  (komendy z seedami i configami finalnymi), struktura repo, zespół, cytowanie PTB-XL i licencja.
- Test reprodukcji: osoba, która nie pisała README, wykonuje je na świeżym klonie (inna maszyna) i zgłasza problemy.
- Model card dołączona do wydania ({{T702}}).

### Poza zakresem (wiążące)

- Raport końcowy przedmiotu (tekst) — korzysta z {{T803}}.

### Pliki

- `docs/model_card.md`, `README.md` — aktualizacja

### Testy do napisania

- Brak testów automatycznych; weryfikacja przez test reprodukcji.

### Weryfikacja

```bash
git clone <repo> cardioai-fresh && cd cardioai-fresh
# kroki z README: instalacja, demo, reprodukcja jednego wyniku z tabeli
```

### Wskazówki i pułapki

- Liczby do karty kopiuj skryptem z plików JSON (np. mały helper w `scripts/make_report_assets.py`), żeby uniknąć literówek.

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T802-model-card-readme.md`](https://github.com/__REPO__/blob/main/tasks/T802-model-card-readme.md)
- Decyzja [D-015](https://github.com/__REPO__/blob/main/docs/decisions.md#d-015--wielokrotne-użycie-foldu-9) — Wielokrotne użycie foldu 9
- Decyzja [D-035](https://github.com/__REPO__/blob/main/docs/decisions.md#d-035--drobne-odstępstwa-od-specyfikacji) — Drobne odstępstwa od specyfikacji
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** S (do pół dnia, ok. 0,5 osobodnia)

## ✅ Kryteria akceptacji

- [ ] Wszystkie pola `<…>` w karcie modelu wypełnione; sekcja ograniczeń zawiera D-015 i brak walidacji zewnętrznej.
- [ ] Zastrzeżenie „nie jest wyrobem medycznym” w README, karcie i UI.
- [ ] Cytowanie PTB-XL i informacja o licencji CC BY 4.0 w README i karcie.
- [ ] Test reprodukcji na świeżym klonie zaliczony (notatka w PR: kto, na jakiej maszynie, ile trwało).

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T802 review`); PR zatwierdzony przez recenzenta (A); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T801}} — Zamrożenie konfiguracji i jednorazowa ewaluacja na foldzie 10 (G6) (tydzień 14, właściciel B)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka G6 — Final** (tydzień 14): konfiguracja zamrożona przed foldem 10; karta modelu i wyniki reprodukowalne.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T801}}, {{T802}}, {{T803}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T802` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t802-model-card-readme`; status karty `in_progress` (`python3 scripts/tasks.py set-status T802 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(docs): <description> [T802]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T802`.

W Claude Code zadanie realizuje komenda `/task T802`.
__ISSUE_BODY_EOF__
}

body_T803() { cat <<'__ISSUE_BODY_EOF__'
> Karta zadania w repozytorium (`tasks/T803-final-report-assets.md`) jest źródłem prawdy; ten issue służy do dyskusji i przypisań (`tasks/README.md` §8). Zmiany zakresu wprowadzaj w karcie, nie tylko w issue.

## 🎯 Cel

Wszystkie tabele i wykresy do raportu i prezentacji generowane jednym skryptem z MLflow i plików wydania — spójne, w jednym stylu, odtwarzalne.

| Pole | Wartość |
|---|---|
| Zadanie | **T803** — Artefakty raportu końcowego — tabele i wykresy |
| Epik | Finalizacja (`final`) |
| Poziom | Core (obowiązkowe) |
| Planowany tydzień | 14 z 14 |
| Rozmiar | M (1–2 osobodni) |
| Bramka | G6 — Final |
| Eksperyment | — |
| Właściciel | A (Data & Signal ML) |
| Recenzent | C (Reliability & Product) |

## 📚 Kontekst — przeczytaj przed rozpoczęciem

Najpierw `AGENTS.md` w całości, potem dokumenty i sekcje poniżej (numery `§` odsyłają do sekcji w dokumencie).

- [`docs/experiments.md`](https://github.com/__REPO__/blob/main/docs/experiments.md) [§3–§5](https://github.com/__REPO__/blob/main/docs/experiments.md#3-rejestr-eksperymentów) (eksperymenty i tabela zbiorcza)
- [`docs/evaluation.md`](https://github.com/__REPO__/blob/main/docs/evaluation.md) [§6](https://github.com/__REPO__/blob/main/docs/evaluation.md#6-wiele-seedów-i-raportowanie) (format tabel)
- [`docs/mlops.md`](https://github.com/__REPO__/blob/main/docs/mlops.md) [§3](https://github.com/__REPO__/blob/main/docs/mlops.md#3-parametry-metryki-artefakty) (artefakty runów)

## 🛠️ Szczegóły techniczne

### Zakres

- `scripts/make_report_assets.py` → `reports/final/` (commitowany, tylko małe PNG/SVG/MD):
  tabela zbiorcza (E01–E10), tabele per klasa (val i test), krzywe ROC/PR per klasa (test), reliability diagrams przed/po, krzywe risk–coverage,
  krzywe degradacji i mapa Δ per odprowadzenie, przykłady XAI (rekordy val), tabela wydajności (E11), wybrane wykresy EDA.
- Jednolity styl wykresów (jeden moduł stylu), podpisy po polsku, rozdzielczość do druku.
- Lista „figura → źródło danych (run_id/plik)” w `reports/final/SOURCES.md`.

### Poza zakresem (wiążące)

- Pisanie tekstu raportu i slajdów.

### Pliki

- `scripts/make_report_assets.py` — nowy
- `src/cardioai/evaluation/plots.py` — nowy (wspólny styl i funkcje wykresów)
- `reports/final/` — nowy (wygenerowane pliki + `SOURCES.md`)

### Testy do napisania

- Smoke na sztucznych danych (`tmp_path`): skrypt tworzy oczekiwane pliki.

### Weryfikacja

```bash
uv run python scripts/make_report_assets.py --out reports/final
```

### Wskazówki i pułapki

- `matplotlib` z backendem `Agg`; ustaw stałe ziarno tam, gdzie wykres losuje (np. przykłady rekordów).

## ⚖️ Reguły z `AGENTS.md` §2 szczególnie istotne w tym zadaniu

Złamanie którejkolwiek z 12 reguł nienaruszalnych oznacza PR do poprawy. Dla tego epiku najczęściej dotyczą:

2. **Fold 10 (test) jest zablokowany:** sygnał i predykcje dla foldu 10 tylko przez `cardioai.data.test_lock` (odblokowanie wyłącznie w T801). Wybór modelu, progi, kalibracja i robustness w trakcie prac — tylko val.
10. **Kontrakty zmieniamy świadomie:** zmiana schematu danych, configu, checkpointu, bundla lub API = aktualizacja `docs/` + wpis w `docs/decisions.md` + informacja w opisie PR. Jeśli karta tego nie przewiduje — zatrzymaj się i zapytaj.
11. **Brak twierdzeń klinicznych:** XAI to atrybucja (wrażliwość modelu), nie wyjaśnienie przyczynowe; UI zawsze pokazuje zastrzeżenie o braku statusu wyrobu medycznego.

## 🔎 Źródła i decyzje

- Karta zadania: [`tasks/T803-final-report-assets.md`](https://github.com/__REPO__/blob/main/tasks/T803-final-report-assets.md)
- Plan i zależności całego projektu: [`tasks/BACKLOG.md`](https://github.com/__REPO__/blob/main/tasks/BACKLOG.md)
- Specyfikacja źródłowa: `docs/spec/CardioAI_PTBXL_specyfikacja.pdf`

📏 **Szacowany rozmiar:** M (1–2 osobodni)

## ✅ Kryteria akceptacji

- [ ] Jedno polecenie generuje komplet; ponowne uruchomienie daje identyczne pliki (bez znaczników czasu w treści).
- [ ] Każda figura ma wpis w `SOURCES.md` z run_id lub ścieżką pliku źródłowego.
- [ ] Wykresy XAI tylko dla rekordów val; wyniki testu tylko z `stage=final`.
- [ ] Łączny rozmiar `reports/final/` < 10 MB.

**Definition of Done (`AGENTS.md` §7)** — odhacz tam, gdzie dotyczy:

- [ ] Wszystkie kryteria akceptacji z karty są spełnione (odhaczone w opisie PR).
- [ ] `uv run ruff check .` i `uv run ruff format --check .` bez błędów.
- [ ] `uv run lint-imports` bez naruszeń.
- [ ] `uv run mypy src` — zalecane, nieblokujące do T702.
- [ ] `uv run pytest -m "not requires_data and not slow and not gpu"` zielone; nowe testy dodane.
- [ ] Kod działa na `device=cpu`; brak `.cuda()` i `float64` w tensorach.
- [ ] Publiczne funkcje i klasy mają typy oraz docstringi (po angielsku).
- [ ] Brak danych, checkpointów i sekretów w diffie.
- [ ] Dokumentacja zaktualizowana; przy zmianie kontraktu wpis w `docs/decisions.md` i informacja w opisie PR.
- [ ] Status karty ustawiony na `review` (`python scripts/tasks.py set-status T803 review`); PR zatwierdzony przez recenzenta (C); CI zielone.

## 🔗 Zależności

**Blokowane przez** (wszystkie muszą mieć status `done`, inaczej zgłoś to zamiast implementować „na zapas”):

- {{T801}} — Zamrożenie konfiguracji i jednorazowa ewaluacja na foldzie 10 (G6) (tydzień 14, właściciel B)

**Odblokowuje:** brak bezpośrednich zależnych kart.

**Bramka G6 — Final** (tydzień 14): konfiguracja zamrożona przed foldem 10; karta modelu i wyniki reprodukowalne.

Bramka jest zaliczona, gdy wszystkie jej zadania mają status `done` **i** spełniony jest powyższy warunek (przegląd całego zespołu, 15 minut, notatka w PR zamykającym bramkę — `tasks/README.md` §5). Zadania bramki: {{T801}}, {{T802}}, {{T803}}.

## 🧭 Jak zacząć

1. `python3 scripts/tasks.py show T803` — sprawdź, czy zależności mają status `done`.
2. Przeczytaj `AGENTS.md` w całości, kartę oraz sekcje z „Kontekst”.
3. Wypisz krótki plan (pliki, publiczne interfejsy, testy).
4. Gałąź: `t803-final-report-assets`; status karty `in_progress` (`python3 scripts/tasks.py set-status T803 in_progress`).
5. Implementuj **tylko zakres karty**; sekcja „Poza zakresem” jest wiążąca. Jeśli potrzebna jest zmiana kontraktu z `docs/` poza kartą — zatrzymaj się i zapytaj.
6. Dodaj testy, uruchom komendy z „Weryfikacja” i bramkę z Definition of Done.
7. Commit w stylu Conventional Commits po angielsku z ID zadania, np. `feat(evaluation): <description> [T803]`.
8. PR według `.github/pull_request_template.md` (jedno zadanie = jeden PR), status karty `review`; recenzent może użyć `/review-task T803`.

W Claude Code zadanie realizuje komenda `/task T803`.
__ISSUE_BODY_EOF__
}

# --- wykonanie ---------------------------------------------------------------------------------------------------
write_labels
write_table

TOTAL="$(wc -l < "$TABLE" | tr -d ' ')"
echo "Repozytorium: $REPO · zadań w pliku: $TOTAL · tryb: $([ "$APPLY" = 1 ] && echo APPLY || echo 'dry-run')"

if [ "$APPLY" = 1 ]; then
  if [ "$ASSUME_YES" != 1 ]; then
    printf 'Utworzyć etykiety i issues w %s? [y/N] ' "$REPO"
    read -r answer
    case "$answer" in y|Y|yes|YES) ;; *) echo "Przerwano."; exit 0 ;; esac
  fi
  gh issue list --repo "$REPO" --state all --limit 1000 --json number,title \
    --jq '.[] | select(.title | test("^\\[T[0-9]{3}\\] ")) | "\(.title | .[1:5]) \(.number)"' >> "$MAP" </dev/null
  echo "Istniejące issues z tytułem [T###]: $(wc -l < "$MAP" | tr -d ' ')"
fi

# 1) etykiety
while IFS='|' read -r name color desc; do
  if [ "$APPLY" = 1 ]; then
    gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force </dev/null >/dev/null
  else
    echo "[dry-run] gh label create \"$name\" --repo $REPO --color $color --description \"$desc\" --force"
  fi
done < "$WORK/labels.txt"

# 2) issues w kolejności zależności
[ -z "$DUMP_DIR" ] || mkdir -p "$DUMP_DIR"
while IFS='|' read -r id title labels owner; do
  selected "$id" || continue
  full_title="[$id] $title"
  if [ -n "$(issue_no "$id")" ]; then
    echo "pomijam $id — już istnieje jako #$(issue_no "$id")"
    continue
  fi
  body="$WORK/$id.md"
  render "$id" > "$body"
  [ -z "$DUMP_DIR" ] || cp "$body" "$DUMP_DIR/$id.md"
  assignee="$(assignee_for "$owner")"
  args=(--repo "$REPO" --title "$full_title" --label "$labels" --body-file "$body")
  [ -z "$assignee" ] || args+=(--assignee "$assignee")
  if [ "$APPLY" = 1 ]; then
    url="$(gh issue create "${args[@]}" </dev/null)"
    num="${url##*/}"
    echo "$id $num" >> "$MAP"
    echo "$id $num" >> "$CREATED"
    echo "utworzono $id → $url"
    sleep "$SLEEP_S"
  else
    echo "[dry-run] gh issue create --repo $REPO --title \"$full_title\" --label \"$labels\"${assignee:+ --assignee $assignee} --body-file <$(wc -l < "$body" | tr -d ' ') linii>"
  fi
done < "$TABLE"

# 3) odświeżenie treści: nowe issues dostają linki #N także w sekcji „Odblokowuje”
if [ "$APPLY" = 1 ]; then
  if [ "$REFRESH" = 1 ]; then cp "$MAP" "$WORK/refresh.txt"; else cp "$CREATED" "$WORK/refresh.txt"; fi
  while read -r id num; do
    [ -n "${id:-}" ] || continue
    selected "$id" || continue
    render "$id" > "$WORK/$id.refresh.md"
    gh issue edit "$num" --repo "$REPO" --body-file "$WORK/$id.refresh.md" </dev/null >/dev/null
    echo "odświeżono $id (#$num)"
    sleep "$SLEEP_S"
  done < "$WORK/refresh.txt"
fi

echo "Gotowe."
