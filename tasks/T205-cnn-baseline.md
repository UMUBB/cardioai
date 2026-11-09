---
id: T205
title: Płytki CNN 1D i pierwszy run end-to-end (E02)
epic: training
owner: B
reviewer: A
week: 3
size: S
level: MVP
gate: G2
experiment: E02
depends_on: [T204]
status: todo
---

# T205 — Płytki CNN 1D i pierwszy run end-to-end (E02)

## Kontekst

- `docs/modeling.md` §3.1 (architektura `cnn_small`)
- `docs/experiments.md` §4 (E02)
- `tasks/README.md` §5 (bramka G2)

## Cel

Pierwszy model głęboki przechodzący cały pipeline na prawdziwych danych — dowód, że dane, trening, metryki i MLflow działają razem.

## Zakres

- Enkoder `cnn_small` zarejestrowany w rejestrze (4 bloki `Conv1d(k=7) → BN → ReLU → MaxPool(2)`, szerokości `[32, 64, 128, 128]`, GAP).
- `configs/model/cnn_small.yaml`, `configs/experiment/e02_cnn_small.yaml` (100 Hz, bez augmentacji, 30 epok).
- Trening na prawdziwych danych (seed 0) i zapis wyniku w PR.

## Poza zakresem

- Strojenie hiperparametrów; ResNet1D (T207).

## Pliki

- `src/cardioai/models/cnn.py` — nowy
- `configs/model/cnn_small.yaml`, `configs/experiment/e02_cnn_small.yaml` — nowe
- `tests/unit/models/test_cnn.py` — nowy

## Interfejs (wiążący)

```python
class CNNSmallParams(BaseModel):
    widths: list[int] = [32, 64, 128, 128]
    kernel_size: int = 7
    dropout: float = 0.1
@register_encoder("cnn_small", params=CNNSmallParams)
class CNNSmallEncoder(Encoder): ...
```

## Kryteria akceptacji

- [ ] Forward dla `[2, 12, 1000]` i `[2, 12, 5000]` działa; `out_dim = widths[-1]`.
- [ ] Run na prawdziwych danych w MLflow (`exp_id=E02`): macro AUROC val ≥ 0,80.
- [ ] Liczba parametrów i MFLOPs zalogowane jako parametry runu.
- [ ] Bramka G2 (wspólnie z T206): zespół potwierdza, że model uczy się sensownie (krzywe strat, AUROC per klasa > 0,5).

## Testy

- `test_cnn.py`: kształty, gradient dociera do pierwszej warstwy, deterministyczny forward w `eval()`.

## Weryfikacja

```bash
uv run pytest tests/unit/models/test_cnn.py -q
uv run python scripts/train.py --config configs/experiment/e02_cnn_small.yaml
```

## Wskazówki i pułapki

- Jeśli AUROC utknie na ~0,5: sprawdź kolejność etykiet, normalizację (statystyki z train) i czy `y` nie jest przesunięte względem `x`.
