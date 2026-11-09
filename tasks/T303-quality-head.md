---
id: T303
title: Model jakości — głowa multitask i osobny QualityNet (E05)
epic: quality
owner: A
reviewer: B
week: 6
size: M
level: Core
gate: G4
experiment: E05
depends_on: [T206, T207, T301, T302]
status: todo
---

# T303 — Model jakości: głowa multitask i osobny QualityNet (E05)

## Kontekst

- `docs/reliability.md` §3 (warianty i ewaluacja), §2 (korupcje)
- `docs/modeling.md` §4 (głowy), §5 (`L_quality`, `lambda_quality`)
- `docs/experiments.md` §4 (E05 — reguła decyzyjna)
- `docs/mlops.md` §3 (metryki `val/quality_*`)
- `docs/decisions.md`: D-023, D-027, D-035 (parametr `lambda_diag`)

## Cel

Model ocenia jakość sygnału (4 typy artefaktów), a eksperyment E05 rozstrzyga, czy wspólny enkoder z głową jakości jest lepszy niż osobny QualityNet i czy nie szkodzi diagnozie (H6).

## Zakres

- Metryki jakości w walidacji `Trainer` (gdy `model.heads.quality`), dostarczane przez hook `MetricHook` z T204 (`training/hooks_quality.py`, bez zmian w `trainer.py`):
  AUROC per etykieta na słabych etykietach val i na deterministycznym syntetycznym val (każdy rekord val czysty + jedna korupcja z `corrupt_for_eval`).
- `SyntheticQualityDataset` — dataset val zwracający wersje czyste i skorumpowane z etykietą `corruption`; buduje własny dataset val z pipeline'em
  `build_pipeline(train=False, robustness_corruption=...)` zamiast opakowywać gotowy `PTBXLDataset` (D-023).
- `scripts/evaluate.py --quality-synthetic` → `predictions_val_qsynth.parquet` (z kolumnami `qlogit_*`, `yq_*`, `corruption`).
- Configi: `e05a_diag_only.yaml`, `e05b_quality_l05.yaml`, `e05c_quality_l10.yaml` (korupcje `p = 0.3`), `e05d_qualitynet.yaml` (`cnn_small`, `lambda_diag = 0`).
- Wniosek E05 według reguły decyzyjnej.

## Poza zakresem

- Progi quality gate (T304), krzywe odporności (T305).

## Pliki

- `src/cardioai/data/quality_eval.py` — nowy (`SyntheticQualityDataset`)
- `src/cardioai/training/hooks_quality.py` — nowy (hook metryk jakości dla `Trainer.metric_hooks`, T204)
- `scripts/train.py` — zmiana (podpięcie hooka jakości, gdy `model.heads.quality`)
- `scripts/evaluate.py` — zmiana (`--quality-synthetic`)
- `configs/experiment/e05a_diag_only.yaml`, `e05b_quality_l05.yaml`, `e05c_quality_l10.yaml`, `e05d_qualitynet.yaml` — nowe
- `tests/unit/data/test_quality_eval.py`, `tests/unit/training/test_quality_metrics.py` — nowe

## Interfejs (wiążący)

```python
class SyntheticQualityDataset(torch.utils.data.Dataset):
    def __init__(self, cfg: RunConfig, corruptions: Sequence[str], *, seed: int = 0,
                 severities: Mapping[str, float] | None = None) -> None: ...
    # wewnątrz: build_dataset(cfg, "val", pipeline=build_pipeline(..., train=False, robustness_corruption=...)) — jeden pipeline na korupcję + wersja czysta
    # próbka jak w PTBXLDataset + "corruption": str ("none" dla wersji czystej)
```

## Kryteria akceptacji

- [ ] Metryki `val/quality_auroc_<etykieta>` i `val/quality_auroc_synth_<etykieta>` w MLflow dla runów z głową jakości.
- [ ] `SyntheticQualityDataset` deterministyczny (dwa przebiegi → identyczne tensory) i niezależny od `num_workers`.
- [ ] Cztery warianty E05 zalogowane; tabela w `docs/experiments.md` (E05) wygenerowana przez `summarize_runs.py`.
- [ ] Wniosek E05: decyzja o włączeniu głowy jakości do modelu finalnego według reguły decyzyjnej E05 (D-027: spadek macro AUROC diagnozy na czystym val ≤ 0,005 i wzrost macro AUROC diagnozy
      na syntetycznym val, `predictions_val_qsynth.parquet`), z wartościami liczbowymi w tekście.
- [ ] `predictions_val_qsynth.parquet` gotowy dla T304.

## Testy

- `test_quality_eval.py`: liczba próbek (2× val), etykiety korupcji, determinizm.
- `test_quality_metrics.py`: metryki jakości liczone tylko przy włączonej głowie; brak wyjątków, gdy etykieta nie ma pozytywów.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_quality_eval.py tests/unit/training/test_quality_metrics.py -q
uv run python scripts/train.py --config configs/experiment/e05b_quality_l05.yaml
```

## Wskazówki i pułapki

- Rzadkie słabe etykiety (np. `burst_noise`) dają niestabilny AUROC na val — raportuj liczność pozytywów obok wyniku.
- Korupcje w treningu zmieniają rozkład wejścia — porównuj diagnozę zawsze na czystym val.
