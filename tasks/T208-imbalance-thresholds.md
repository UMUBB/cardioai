---
id: T208
title: Nierównowaga klas — pos_weight, focal loss, progi (E04)
epic: training
owner: B
reviewer: C
week: 5
size: M
level: MVP
gate: G3
experiment: E04
depends_on: [T206, T207]
status: todo
---

# T208 — Nierównowaga klas: `pos_weight`, focal loss, progi (E04)

## Kontekst

- `docs/modeling.md` §5 (straty)
- `docs/evaluation.md` §3 (progi)
- `docs/experiments.md` §4 (E04 — reguła decyzyjna)
- `AGENTS.md` §2 pkt 3 (`pos_weight` tylko z train)
- `docs/decisions.md`: D-031

## Cel

Rozstrzygnąć na val, jak obsłużyć nierównowagę klas (HYP jest ok. 3,5× rzadsza niż NORM), i ustalić domyślną stratę oraz metodę progów dla dalszych eksperymentów.

## Zakres

- `compute_pos_weight` (`none`, `train`, `sqrt_train`) liczone wyłącznie z wierszy train indeksu.
- Strata `focal` (na logitach, `γ = focal_gamma`) jako wariant `training.loss.name`.
- Configi `e04a_bce.yaml`, `e04b_posweight.yaml`, `e04c_focal.yaml`, wszystkie z `experiment.name: e04_imbalance` (wariant tylko w `experiment.variant`, np. `bce`, `posweight`, `focal`; D-031); run seed 0 dla każdego wariantu (3 seedy dla zwycięzcy uruchamia T209).
- Porównanie progów `f1` vs `youden` na najlepszym wariancie.
- Wniosek w `docs/experiments.md` (E04) i — jeśli zmienia domyślną stratę w `configs/base.yaml` — wpis w `docs/decisions.md`.

## Poza zakresem

- Złożone funkcje kosztu (asymetryczne, z marginesem) — tylko jeśli E04 wykaże potrzebę, jako osobne zadanie.

## Pliki

- `src/cardioai/training/losses.py` — zmiana (focal, `pos_weight`)
- `src/cardioai/training/class_weights.py` — nowy
- `configs/experiment/e04a_bce.yaml`, `e04b_posweight.yaml`, `e04c_focal.yaml` — nowe
- `tests/unit/training/test_class_weights.py`, `tests/unit/training/test_focal.py` — nowe

## Interfejs (wiążący)

```python
def compute_pos_weight(index: pd.DataFrame, mode: Literal["none", "train", "sqrt_train"],
                       *, drop_unlabeled: bool = True) -> torch.Tensor | None: ...   # [5] float32, kolejność SUPERCLASSES
def focal_loss_with_logits(logits: torch.Tensor, targets: torch.Tensor, *, gamma: float = 2.0,
                           pos_weight: torch.Tensor | None = None, reduction: str = "mean") -> torch.Tensor: ...
```

## Kryteria akceptacji

- [ ] `compute_pos_weight` korzysta tylko z wierszy `split == "train"` (test: zmiana etykiet val/test nie zmienia wyniku).
- [ ] Focal z `γ = 0` daje wynik równy BCE (tolerancja 1e-6); dla `γ > 0` zgodność z referencją na wartościach testowych.
- [ ] Trzy warianty w MLflow (`exp_id=E04`), tabela w `docs/experiments.md` (E04) wygenerowana przez `summarize_runs.py` (T209) lub tymczasowo z MLflow z linkami do runów.
- [ ] Decyzja według reguły E04 zapisana w sekcji „Wniosek” eksperymentu.

## Testy

- `test_class_weights.py`: wartości dla znanego indeksu, tryby, wyłącznie train.
- `test_focal.py`: równoważność z BCE przy `γ = 0`, stabilność numeryczna przy dużych logitach (±50).

## Weryfikacja

```bash
uv run pytest tests/unit/training/test_class_weights.py tests/unit/training/test_focal.py -q
uv run python scripts/train.py --config configs/experiment/e04b_posweight.yaml
```

## Wskazówki i pułapki

- Focal licz przez `binary_cross_entropy_with_logits(reduction="none")` i `p_t = exp(-bce)` — bez jawnego `sigmoid` i `log`.
- Wysokie `pos_weight` psują kalibrację — patrz E09; zapisz ECE każdego wariantu.
