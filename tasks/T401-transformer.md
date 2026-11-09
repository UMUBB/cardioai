---
id: T401
title: Transformer czasowy jako model porównawczy (E07)
epic: extended
owner: B
reviewer: C
week: 8
size: M
level: Extended
gate: none
experiment: E07
depends_on: [T207]
status: todo
---

# T401 — Transformer czasowy jako model porównawczy (E07)

## Kontekst

- `docs/modeling.md` §3.3 (architektura), §9 (porównywalność parametrów i FLOPs)
- `docs/experiments.md` §4 (E07)
- Specyfikacja §5.3

## Cel

Sprawdzić, czy jawna uwaga długozasięgowa daje przewagę nad silną bazą konwolucyjną przy 10-sekundowym EKG — w uczciwym porównaniu kosztu.

## Zakres

- `ECGTransformerEncoder` według §3.3: patch embedding (`Conv1d` ze `stride = patch_size`), token `[CLS]`, uczone pozycje,
  `nn.TransformerEncoder` (`norm_first=True`, `batch_first=True`, GELU), pooling `cls` lub `mean`, LayerNorm.
- `configs/model/transformer.yaml`, `configs/experiment/e07_transformer.yaml` (wariant `cls` i `mean`).
- Dobór `d_model`/`depth` tak, by stosunek parametrów do ResNet1D był w przedziale 0,5–2,0; FLOPs w tabeli.
- Trening: seed 0 dla obu wariantów poolingu, 3 seedy dla lepszego; preferowane urządzenie: Mac (MPS) do eksploracji, laptop A do runów do tabeli.
- Wniosek E07.

## Poza zakresem

- Pretrening self-supervised, warianty efektywnej uwagi.

## Pliki

- `src/cardioai/models/transformer.py` — nowy
- `configs/model/transformer.yaml`, `configs/experiment/e07_transformer.yaml` — nowe
- `tests/unit/models/test_transformer.py` — nowy

## Interfejs (wiążący)

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

## Kryteria akceptacji

- [ ] `T % patch_size != 0` → błąd walidacji przy budowie modelu (z sugestią poprawnego `patch_size`).
- [ ] Forward działa na CPU, MPS (Mac) i CUDA; brak ostrzeżeń o nested tensors (`enable_nested_tensor=False`).
- [ ] Stosunek parametrów do ResNet1D w przedziale 0,5–2,0 (albo uzasadnienie w PR).
- [ ] Tabela E07 wygenerowana; wniosek według reguły E07.
- [ ] Jeśli Transformer nie zostanie ukończony, „3 rodziny modeli” z Definition of Done spełniają baseline klasyczny, CNN i ResNet1D — zaznacz to w raporcie (opcje i decyzja zespołu: D-030, status: proponowana).

## Testy

- `test_transformer.py`: kształty dla 100/500 Hz (`patch_size` 25/125), oba poolingi, walidacja `patch_size`, deterministyczny `eval()`.

## Weryfikacja

```bash
uv run pytest tests/unit/models/test_transformer.py -q
uv run python scripts/train.py --config configs/experiment/e07_transformer.yaml
```

## Wskazówki i pułapki

- Transformery są wrażliwe na `lr` i rozgrzewkę — zacznij od `lr = 1e-4`, `warmup_epochs = 5`.
- Na MPS sprawdź `PYTORCH_ENABLE_MPS_FALLBACK=1`, jeśli któraś operacja uwagi nie jest wspierana.
