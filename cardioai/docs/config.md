# Konfiguracja eksperymentów

Status: **wiążący**. Kod: `src/cardioai/config/schema.py`, `src/cardioai/config/loader.py` (T002). Właściciel: B.

## 1. Zasady

1. Żaden hiperparametr nie jest wpisany na stałe w kodzie — każdy run dostaje jawny plik YAML.
2. Config jest walidowany przez Pydantic z `extra="forbid"` — literówka w kluczu kończy run błędem.
3. Rozwiązany (scalony) config jest zapisywany jako artefakt MLflow i w katalogu runu (`config.resolved.yaml`).
4. Ścieżki w configu są względne do katalogu głównego repo. Pierwszeństwo źródeł wartości: `--set` > zmienna środowiskowa > plik YAML (po `extends`) > wartość domyślna.
   Mapowanie zmiennych z `docs/environment.md` §4 na klucze wykonuje loader configu (T002): `CARDIOAI_DATA_ROOT → data.root`, `CARDIOAI_DEVICE → training.device`;
   `get_device` dostaje wartość już rozstrzygniętą (D-025).
5. Configi bazowe zmieniamy ostrożnie — zmiana `base.yaml` zmienia `config_hash` wszystkich eksperymentów.

## 2. Struktura katalogu `configs/`

```text
configs/
├── base.yaml                 # pełne wartości domyślne
├── data/
│   ├── ptbxl_100.yaml
│   └── ptbxl_500.yaml
├── model/
│   ├── cnn_small.yaml
│   ├── resnet1d.yaml
│   └── transformer.yaml
├── experiment/
│   ├── e00_smoke.yaml        # mały config do testów (mini-PTB-XL, 1 epoka)
│   ├── e02_cnn_small.yaml
│   ├── e03_resnet1d.yaml
│   └── ...                   # nazwa: e<NN>[<wariant>]_<opis>.yaml
└── robustness/
    └── default.yaml          # siatka testów odporności (docs/reliability.md §8)
```

## 3. Ładowanie: `extends` i `--set`

```yaml
# configs/experiment/e03_resnet1d.yaml
extends:
  - ../base.yaml
  - ../data/ptbxl_100.yaml
  - ../model/resnet1d.yaml
experiment:
  id: E03
  name: e03_resnet1d
  variant: base
```

- `extends` to lista ścieżek względnych do bieżącego pliku, scalana po kolei; potem treść pliku, potem zmienne środowiskowe (§1 pkt 4), na końcu `--set`.
- Scalanie: słowniki rekurencyjnie, **listy są zastępowane w całości**, wartość `null` nadpisuje.
- `--set klucz.podklucz=wartość` (wielokrotnie); wartość parsowana przez `yaml.safe_load`,
  np. `--set training.optimizer.lr=1e-3`, `--set model.params.widths=[64,128,256,256]`, `--set data.cache_dir=null`.
- Cykle w `extends` → błąd. Klucz `extends` nie trafia do configu wynikowego.

Wiążące API:

```python
def load_config(path: str | Path, overrides: Sequence[str] = ()) -> RunConfig: ...
def config_hash(cfg: RunConfig) -> str: ...            # 12 znaków hex
def dump_resolved(cfg: RunConfig, path: Path) -> None: ...
def add_config_args(parser: argparse.ArgumentParser) -> None: ...   # --config, --set
```

## 4. Schemat (pełna lista kluczy)

```yaml
experiment:
  id: "E03"                 # E00..E11
  name: "e03_resnet1d"      # = nazwa eksperymentu MLflow
  variant: "base"           # krótki opis wariantu (część nazwy runu)
  owner: "B"                # A | B | C
  hypotheses: ["H1"]
  description: ""
seed: 0
data:
  dataset_version: "1.0.3"
  root: "data/raw/ptb-xl-1.0.3"            # nadpisywane przez CARDIOAI_DATA_ROOT; --set ma pierwszeństwo (§1 pkt 4)
  index_path: "data/interim/ptbxl_index_v1.0.3.parquet"
  cache_dir: "data/processed"              # null = czytaj WFDB bez cache
  sampling_rate: 100                       # 100 | 500
  task: "superclass"
  label_min_likelihood: 0.0
  drop_unlabeled: true
  num_workers: 4
  batch_size_eval: 256
preprocessing:
  normalization: "per_lead_train"          # per_lead_train | per_record | none
  norm_stats_path: null                    # null = ścieżka domyślna (docs/data_contract.md §9)
  bandpass: null                           # np. {low_hz: 0.5, high_hz: 40.0, order: 4}
  notch_hz: null                           # tylko gdy notch_hz < fs/2
augmentations: []                          # lista {name, p, ...parametry} (docs/data_contract.md §8)
quality:
  weak_labels: false                       # y_quality ze słabych etykiet PTB-XL
  synthetic:
    enabled: false
    p: 0.3
    corruptions: ["gaussian_noise", "powerline", "burst_noise", "baseline_drift", "electrode_flat", "electrode_pop"]
model:
  name: "resnet1d"                         # klucz w rejestrze modeli
  params: {}                               # walidowane przez Params danego modelu (§7)
  heads:
    quality: false
    aux: []                                # np. ["rhythm", "form"]
  metadata:
    enabled: false
    features: ["age", "age_90plus", "sex", "height", "weight"]   # age_90plus to osobna cecha (D-032)
    hidden_dim: 32
  dropout_head: 0.0
training:
  device: "auto"                           # auto | cpu | cuda | mps; nadpisywane przez CARDIOAI_DEVICE (§1 pkt 4)
  epochs: 50
  batch_size: 128
  grad_accum_steps: 1
  optimizer: {name: "adamw", lr: 3.0e-4, weight_decay: 1.0e-2, betas: [0.9, 0.999]}
  scheduler: {name: "cosine", warmup_epochs: 2, min_lr: 1.0e-6}   # cosine | plateau | none
  loss: {name: "bce", pos_weight: "none", focal_gamma: 2.0}       # bce | focal; pos_weight: none | train | sqrt_train
  lambda_diag: 1.0
  lambda_quality: 0.0
  lambda_aux: 0.0
  amp: false                               # tylko CUDA (fp16 + GradScaler)
  grad_clip_norm: 1.0                      # null = brak
  early_stopping: {monitor: "val/macro_auroc", mode: "max", patience: 10, min_delta: 0.0}
  deterministic: false
  log_every_n_steps: 50
evaluation:
  threshold_method: "f1"                   # f1 | youden | fixed
  fixed_threshold: 0.5
  ece_bins: 15
tracking:
  enabled: true
  experiment_name: null                    # null = experiment.name
  run_name: null                           # null = nazwa automatyczna (§6)
  tags: {}
  log_checkpoints: true
output_dir: "outputs"
```

## 5. Przykład configu eksperymentu

```yaml
# configs/experiment/e06b_leaddrop_p03.yaml
extends:
  - ../base.yaml
  - ../data/ptbxl_100.yaml
  - ../model/resnet1d.yaml
experiment:
  id: E06
  name: e06_lead_dropout
  variant: leaddrop-p03
  owner: B
  hypotheses: ["H3"]
augmentations:
  - {name: gaussian_noise, p: 0.3, snr_db: [20.0, 40.0]}
  - {name: lead_dropout, p: 0.3, max_leads: 2}
```

Warianty tego samego eksperymentu (`e06a_…`, `e06b_…`, `e06c_…`) mają wspólne `experiment.name` (`e06_lead_dropout`) i różnią się tylko `experiment.variant` (D-031).

Uruchomienie dla trzech seedów: `uv run python scripts/run_seeds.py --config configs/experiment/e06b_leaddrop_p03.yaml --seeds 0 1 2`.

## 6. Hash configu i nazwy runów

- `config_hash` = pierwsze 12 znaków SHA-256 z kanonicznego JSON-a configu (klucze posortowane), **bez** `seed`,
  `tracking.*`, `output_dir`, `data.root`, `data.num_workers`, `data.cache_dir`, `data.batch_size_eval`,
  `training.log_every_n_steps` i `training.device`. Dzięki temu runy różniące się
  tylko seedem lub maszyną mają ten sam hash i dają się grupować. `training.amp` zostaje w hashu, choć na CPU i MPS jest ignorowane (D-025).
- Nazwa runu (gdy `tracking.run_name` jest puste): `{model.name}-{sampling_rate}hz-{experiment.variant}-s{seed}`,
  np. `resnet1d-100hz-base-s0`.
- Katalog lokalny runu: `{output_dir}/{experiment.name}/{run_name}/` z `config.resolved.yaml`, `checkpoints/`, `eval/`.

## 7. Walidacja parametrów modeli i augmentacji

- Każdy model w rejestrze ma klasę `Params` (Pydantic, `extra="forbid"`); `build_model` waliduje `model.params` przez nią.
- Każda augmentacja i korupcja ma własną klasę parametrów w swoim rejestrze; nieznana nazwa → błąd z listą dostępnych.
- Dzięki temu `RunConfig` pozostaje ogólny, a błędy parametrów wychodzą przed startem treningu.
