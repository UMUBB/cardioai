---
id: T207
title: ResNet1D — model główny (E03)
epic: training
owner: B
reviewer: A
week: 4
size: M
level: MVP
gate: G3
experiment: E03
depends_on: [T109, T205]
status: todo
---

# T207 — ResNet1D: model główny (E03)

## Kontekst

- `docs/modeling.md` §3.2 (architektura i parametry), §7 (protokół), §9 (porównywalność)
- `docs/experiments.md` §4 (E03)
- `docs/evaluation.md` §9 (punkt odniesienia z literatury)

## Cel

Residualny CNN 1D jako model referencyjny projektu, konfigurowalny dla 100 i 500 Hz, z pierwszym runem na prawdziwych danych.

## Zakres

- `ResNet1DEncoder` z `ResNet1DParams` dokładnie według `docs/modeling.md` §3.2 (`BasicBlock1D`, skróty 1×1, etapy ze `stride=2`).
- `configs/model/resnet1d.yaml`, `configs/experiment/e03_resnet1d.yaml` (100 Hz, BCE, augmentacje bazowe: `gaussian_noise` p=0,3, `amplitude_scale` p=0,3).
- Run seed 0 na laptopie A; opcjonalny mały sweep (`lr`, `kernel_size`) według E03.
- Liczba parametrów, MFLOPs dla `[1, 12, 1000]` i `[1, 12, 5000]`, czas epoki — w PR.

## Poza zakresem

- Warianty funkcji straty (T208), multi-seed (T209), 500 Hz (T404).

## Pliki

- `src/cardioai/models/resnet1d.py` — nowy
- `configs/model/resnet1d.yaml`, `configs/experiment/e03_resnet1d.yaml` — nowe
- `tests/unit/models/test_resnet1d.py` — nowy

## Interfejs (wiążący)

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

## Kryteria akceptacji

- [ ] Forward dla 100 Hz i 500 Hz (także z `stem_kernel=75, stem_stride=10`) daje embedding `[B, widths[-1]]`.
- [ ] `len(widths) != len(blocks)` → błąd walidacji `Params`.
- [ ] Run E03 (seed 0) w MLflow z macro AUROC val zapisanym w PR wraz z porównaniem do E02.
- [ ] Liczba parametrów i MFLOPs zalogowane; wartości wpisane w PR.
- [ ] Forward w `eval()` deterministyczny; gradient dociera do stemu.

## Testy

- `test_resnet1d.py`: kształty (100/500 Hz, różne `widths`/`blocks`), walidacja parametrów, przepływ gradientu, skrót przy zmianie wymiaru.

## Weryfikacja

```bash
uv run pytest tests/unit/models/test_resnet1d.py -q
uv run python scripts/train.py --config configs/experiment/e03_resnet1d.yaml
```

## Wskazówki i pułapki

- Padding `kernel_size // 2` przy nieparzystych jądrach zachowuje długość przed `stride`.
- Przy 6 GB VRAM i `batch_size=128` włącz `training.amp: true` na CUDA; bez AMP może być potrzebne `grad_accum_steps=2`.
