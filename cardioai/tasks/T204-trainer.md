---
id: T204
title: Pętla treningowa, straty, checkpointy i scripts/train.py
epic: training
owner: B
reviewer: C
week: 3
size: L
level: MVP
gate: G2
experiment: none
depends_on: [T004, T105, T107, T201, T202]
status: todo
---

# T204 — Pętla treningowa, straty, checkpointy i `scripts/train.py`

## Kontekst

- `docs/modeling.md` §5 (straty), §6 (checkpoint), §7 (protokół), §8 (AMP, urządzenia)
- `docs/config.md` §4 (`training`), §6 (nazwy runów, katalog lokalny)
- `docs/mlops.md` §2, §3 (tagi, metryki, artefakty)
- `docs/data_contract.md` §8 (próbka, `EpochAwareSampler`)

## Cel

Jedna pętla treningowa dla wszystkich architektur, uruchamiana z configu, odporna na różnice urządzeń, z checkpointami
i pełnym logowaniem do MLflow. Rozmiar L: **najpierw plan do akceptacji**.

## Zakres

- `MultiTaskLoss`: `L_diag` (BCE), `L_quality`, `L_aux` z wagami `lambda_*` i składowymi w logach. (`pos_weight` i focal — T208; tu przyjmij parametr `pos_weight=None`.)
- `build_optimizer` (AdamW, bez weight decay dla biasów i normalizacji), `build_scheduler` (cosine z rozgrzewką, plateau, brak).
- `predict_loader` (wspólna pętla predykcji dla walidacji, ewaluacji i robustness).
- `Trainer.fit`: AMP przez `autocast_context`, akumulacja gradientów, przycinanie normy, walidacja co epokę z metrykami T201,
  early stopping, `best.pt` i `last.pt`, wznawianie (`--resume`), `set_epoch` samplera, logowanie do MLflow (w tym `peak_memory_mb` — na CUDA z `torch.cuda.max_memory_allocated`, na pozostałych urządzeniach pomijane).
- Punkt rozszerzeń `metric_hooks: Sequence[MetricHook]` w konstruktorze `Trainer`: hooki wywoływane po walidacji każdej epoki, ich metryki trafiają do `history` i MLflow
  (korzystają z niego T303 — metryki jakości i T403 — metryki głów aux, bez zmian w `trainer.py`).
- `scripts/train.py`: `--config`, `--set`, `--resume`, `--output-dir`, `--no-tracking`; na końcu JSON z `best_metric`, ścieżką checkpointu i `run_id`.

## Poza zakresem

- `pos_weight`, focal (T208), metryki jakości (T303), multi-seed (T209), konkretne architektury (T205, T207).

## Pliki

- `src/cardioai/training/__init__.py`, `trainer.py`, `losses.py`, `optim.py`, `checkpoint.py`, `predict.py` — nowe
- `scripts/train.py` — nowy
- `tests/unit/training/test_losses.py`, `test_optim.py`, `test_checkpoint.py`, `test_trainer.py` — nowe
- `tests/integration/test_train_smoke.py` — nowy

## Interfejs (wiążący)

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

## Kryteria akceptacji

- [ ] Przeuczenie małego modelu na 16 próbkach: strata spada o ≥ 50% w 50 krokach (CPU).
- [ ] Checkpoint: zapis → `torch.load(weights_only=True)` → identyczne wyjścia modelu; zawiera wszystkie pola z `docs/modeling.md` §6 (w tym `preprocessing.version`, której źródłem jest `preprocessing_version` z T107).
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

## Testy

- `test_losses.py`: składowe i wagi, maskowanie brakujących głów.
- `test_optim.py`: grupy parametrów bez weight decay, harmonogram cosine z rozgrzewką.
- `test_checkpoint.py`: round-trip, `weights_only=True`, brak typów niedozwolonych.
- `test_trainer.py`: przeuczenie, early stopping (w tym monitor `NaN`), wznowienie, akumulacja, `metric_hooks` (hook-atrapa dodaje metrykę do `history`).
- `tests/integration/test_train_smoke.py`: fixture → indeks → statystyki → `train.py` (bez MLflow albo z tymczasowym URI).

## Weryfikacja

```bash
uv run pytest tests/unit/training tests/integration/test_train_smoke.py -q
uv run python scripts/train.py --config configs/experiment/e00_smoke.yaml --set data.root=<ścieżka do mini_ptbxl>
```

Uwaga: `--set data.root=...` ma pierwszeństwo nad `CARDIOAI_DATA_ROOT` (`docs/config.md` §1 pkt 4). Bez `--set` zmienna z `.env` wskazująca prawdziwy PTB-XL nadpisze `data.root`
z YAML — do testów na `mini_ptbxl_root` użyj `--set` albo ustaw `CARDIOAI_DATA_ROOT` na fixture.

## Wskazówki i pułapki

- Metryki walidacyjne licz na całym splicie po zebraniu predykcji, nie średnią z batchy.
- `GradScaler` + przycinanie normy: najpierw `scaler.unscale_(optimizer)`, potem `clip_grad_norm_`.
- Nie zapisuj w checkpoincie obiektów `Path`, dataclass ani tablic NumPy — konwertuj do typów prostych (D-013).
