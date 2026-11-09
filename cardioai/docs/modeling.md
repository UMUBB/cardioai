# Modele i trening

Status: **wiążący** (§1, §2, §6). Kod: `src/cardioai/models/`, `src/cardioai/training/`. Właściciel: B.

## 1. Interfejs modelu

```python
@dataclass
class ModelOutput:
    logits: torch.Tensor                                   # [B, 5] diagnoza, kolejność SUPERCLASSES
    quality_logits: torch.Tensor | None = None             # [B, 4] kolejność QUALITY_LABELS
    aux_logits: dict[str, torch.Tensor] = field(default_factory=dict)   # np. {"rhythm": [B, R]}
    embedding: torch.Tensor | None = None                  # [B, D]

class Encoder(nn.Module):
    out_dim: int
    def forward(self, x: torch.Tensor) -> torch.Tensor: ...   # [B, 12, T] -> [B, D]

class ECGModel(nn.Module):
    def __init__(self, encoder: Encoder, heads: MultiTaskHeads,
                 metadata_branch: MetadataBranch | None = None, fusion: ConcatFusion | None = None): ...
    def forward(self, x: torch.Tensor, meta: torch.Tensor | None = None,
                meta_mask: torch.Tensor | None = None) -> ModelOutput: ...
```

- Wejście `x`: `[B, 12, T]` float32, po pipeline (`docs/data_contract.md` §8). Model nie normalizuje danych.
- Wyjście to **logity**; sigmoid, kalibracja i progi są poza modelem.
- Model z wyłączonymi metadanymi ignoruje `meta` (z ostrzeżeniem w logu, raz).
- Do XAI i eksportu ONNX służą cienkie wrappery zwracające tensor (`logits`) lub krotkę `(logits, quality_logits)`.

## 2. Rejestr i budowanie modelu

```python
@register_encoder("resnet1d", params=ResNet1DParams)
class ResNet1DEncoder(Encoder): ...

def build_model(model_cfg: ModelConfig, *, n_samples: int, n_leads: int = 12,
                aux_sizes: Mapping[str, int] | None = None, n_metadata: int = 0) -> ECGModel: ...
def list_encoders() -> list[str]: ...
def count_parameters(model: nn.Module, trainable_only: bool = True) -> int: ...
def estimate_flops(model: nn.Module, input_shape: tuple[int, int, int]) -> int: ...  # FlopCounterMode
```

`build_model` waliduje `model.params` klasą `Params` enkodera, buduje głowy według `model.heads`
i — jeśli `model.metadata.enabled` — gałąź metadanych z fuzją.

## 3. Architektury

### 3.1. `cnn_small` — płytki CNN 1D (baseline E02)

4 bloki `Conv1d(k=7) → BatchNorm → ReLU → MaxPool(2)`, szerokości `[32, 64, 128, 128]`, Global Average Pooling.
Cel: szybki sanity check całego pipeline'u, nie wynik.

### 3.2. `resnet1d` — model główny (E03)

| Element | Konfiguracja startowa (`ResNet1DParams`) |
|---|---|
| Stem | `Conv1d(12, 64, kernel=stem_kernel=15, stride=stem_stride=2)` → BN → aktywacja → `MaxPool1d(3, 2)` (`stem_pool=true`) |
| Etapy | `widths=[64, 128, 256, 512]`, `blocks=[2, 2, 2, 2]`, pierwszy blok etapów 2–4 ze `stride=2` |
| Blok | `BasicBlock1D`: conv(k) → BN → akt. → dropout(`block_dropout`) → conv(k) → BN; skrót: identyczność albo `Conv1d 1×1` + BN; suma → akt. |
| Jądro | `kernel_size=7` |
| Aktywacja | `activation="relu"` lub `"gelu"` |
| Pooling | `AdaptiveAvgPool1d(1)` → embedding 512-D |

Przy 100 Hz długość czasowa: 1000 → 500 (stem) → 250 (pool) → 250 → 125 → 63 → 32.
Wariant 500 Hz o zbliżonym koszcie (E10): `stem_kernel=75`, `stem_stride=10` — po stemie ta sama rozdzielczość co przy 100 Hz.

### 3.3. `transformer` — model porównawczy (E07)

| Element | Konfiguracja startowa |
|---|---|
| Patch embedding | `Conv1d(12, d_model, kernel=patch_size, stride=patch_size)`; `patch_size=25` przy 100 Hz → 40 tokenów; przy 500 Hz `patch_size=125` → 40 tokenów (przy `patch_size=25` byłoby 200) |
| Token klasy | uczony `[CLS]` + uczone kodowanie pozycji `[1, N+1, d_model]` |
| Enkoder | `nn.TransformerEncoder`: `d_model=256`, `depth=6`, `nhead=8`, `dim_feedforward=1024`, `dropout=0.1`, `norm_first=True`, `activation="gelu"`, `batch_first=True` |
| Pooling | `pooling="cls"` lub `"mean"` → LayerNorm → embedding `d_model` |

Liczba parametrów musi być w tym samym rzędzie wielkości co ResNet1D (§9).

## 4. Głowy i fuzja metadanych

- `MultiTaskHeads`: `diagnosis: Linear(D, 5)` (zawsze), `quality: Linear(D, 4)` (gdy `heads.quality`),
  `aux[name]: Linear(D, n_labels)` (gdy `heads.aux`). Przed głowami opcjonalny `Dropout(dropout_head)`.
- `MetadataBranch`: MLP `Linear(2M, hidden) → GELU → Linear(hidden, hidden)` na konkatenacji `[meta, meta_mask]`.
- `ConcatFusion`: `LayerNorm(concat(embedding_ecg, embedding_meta))`; głowy dostają wymiar `D + hidden`.

## 5. Funkcje straty

```text
L_total = lambda_diag · L_diag + lambda_quality · L_quality + lambda_aux · Σ L_aux
```

- `L_diag`: `BCEWithLogitsLoss` z opcjonalnym `pos_weight`:
  `train` → `N_neg / N_pos` per klasa, `sqrt_train` → pierwiastek z tej wartości; liczone **wyłącznie z train**.
- Wariant `focal`: `FL = (1 − p_t)^γ · BCE` liczone na logitach (`γ = focal_gamma`), bez współczynnika α w wersji bazowej.
- `L_quality`: `BCEWithLogitsLoss` na `y_quality` (słabe etykiety OR etykiety korupcji).
- `L_aux`: `BCEWithLogitsLoss` dla każdej głowy pomocniczej.
- Wagi `lambda_*` dobieramy na foldzie 9; logujemy każdą składową osobno (`train/loss_diag`, `train/loss_quality`, …).

## 6. Checkpoint — format

Plik `.pt` zapisany przez `torch.save` jako słownik zawierający **tylko tensory i typy proste**,
tak aby działało `torch.load(path, weights_only=True)`:

```python
{
  "format_version": 1,
  "model": {"name": "resnet1d", "params": {...}, "heads": {...}, "metadata": {...}, "dropout_head": 0.0},
  "state_dict": {...},                # model.state_dict()
  "optimizer": {...}, "scheduler": {...} | None, "scaler": {...} | None,
  "epoch": 17, "global_step": 2312,
  "monitor": "val/macro_auroc", "best_metric": 0.912,
  "config": {...},                    # rozwiązany config jako dict
  "config_hash": "a1b2c3d4e5f6",
  "class_names": ["NORM", "MI", "STTC", "CD", "HYP"],
  "quality_labels": ["static_noise", "burst_noise", "baseline_drift", "electrode_problem"],
  "sampling_rate": 100,
  "preprocessing": {"version": "1:none", "norm_stats": {...}},
  "git_sha": "…", "created_at": "2026-11-20T10:00:00Z",
  "mlflow_run_id": "…" | None
}
```

`best.pt` — najlepszy wynik `monitor`; `last.pt` — ostatnia epoka (do wznowienia, `--resume`).

## 7. Protokół treningu

| Parametr | Zasada |
|---|---|
| Optymalizator | AdamW, `lr=3e-4`, `weight_decay=1e-2`; sweep w ograniczonym zakresie |
| Scheduler | cosine z rozgrzewką (domyślnie) lub ReduceLROnPlateau |
| Batch | dobierany do urządzenia; przy małej VRAM `grad_accum_steps > 1` |
| Precyzja | float32 jako referencja; AMP fp16 tylko na CUDA, gdy stabilne |
| Early stopping | `val/macro_auroc`, `patience=10` |
| Checkpoint | najlepszy wynik val + stan optymalizatora + config |
| Seedy | min. 3 dla modeli finalnych (`scripts/run_seeds.py`) |
| Test | wyłącznie po zamrożeniu architektury, progów i kalibracji (T801) |
| Ewaluacja w treningu | co epokę pełny przebieg val; metryki z `cardioai.evaluation.metrics` |

## 8. AMP, urządzenia, determinizm

- `get_device("auto")`: CUDA → MPS → CPU. Wartość `training.device` jest rozstrzygana wcześniej przez loader configu
  (`--set` > `CARDIOAI_DEVICE` > YAML; `docs/config.md` §1 pkt 4), więc `get_device` dostaje ją już rozstrzygniętą.
- AMP: tylko CUDA, `torch.autocast("cuda", dtype=torch.float16)` + `GradScaler`. RTX 2060 (Turing, sm_75) nie ma natywnego bf16.
- MPS: float32, AMP wyłączone, `PYTORCH_ENABLE_MPS_FALLBACK=1` dla brakujących operacji. Wyniki MPS i CUDA nie są bitowo identyczne.
- `training.deterministic=true` włącza `torch.use_deterministic_algorithms(True)` tam, gdzie to możliwe (CUDA wymaga `CUBLAS_WORKSPACE_CONFIG=:4096:8`).
- Finalne, kanoniczne runy wykonujemy na jednej klasie urządzenia: laptop z RTX 2060 (`docs/decisions.md` D-019).

## 9. Porównywalność architektur

Dla każdego modelu w tabeli wyników raportujemy: liczbę parametrów, MFLOPs na rekord (`estimate_flops` dla `[1, 12, T]`),
czas epoki, opóźnienie inferencji na CPU (p50). Transformer i ResNet1D porównujemy przy stosunku liczby parametrów
w przedziale 0,5–2,0; jeśli to niemożliwe, raportujemy oba modele i wyjaśniamy różnicę.
