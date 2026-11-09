---
id: T403
title: Głowy pomocnicze rhythm/form (opcjonalne, E05)
epic: extended
owner: A
reviewer: B
week: 9
size: M
level: Extended
gate: none
experiment: E05
depends_on: [T207]
status: todo
---

# T403 — Głowy pomocnicze rhythm/form (opcjonalne, E05)

## Kontekst

- `docs/data_contract.md` §4 (kody rytmu i formy), §6 (`scp_codes_json`)
- `docs/modeling.md` §4 (głowy aux), §5 (`lambda_aux`)
- `docs/experiments.md` §4 (E05)

## Cel

Sprawdzić, czy dodatkowe zadania (stwierdzenia rytmu i formy z PTB-XL) poprawiają reprezentację i wynik na 5 superklasach.

## Zakres

- Wyznaczenie zestawów etykiet: kody z `scp_statements.csv` z `rhythm == 1` oraz `form == 1`, z ≥ 200 pozytywami w train (lista zapisana w JSON).
- `AuxLabelProvider` (`FieldProvider`) zwracający `aux: {"rhythm": [R], "form": [F]}`; rozmiary przekazywane do `build_model(aux_sizes=...)`.
- Zapis list etykiet aux w checkpoincie (w configu modelu), metryki `val/aux_<nazwa>_macro_auroc` dostarczane przez hook `MetricHook` z T204 (`training/hooks_aux.py`, bez zmian w `trainer.py`).
- Config `e05e_aux.yaml` (`heads.aux: ["rhythm", "form"]`, `lambda_aux ∈ {0.3, 1.0}`); wniosek w E05.

## Poza zakresem

- Serwowanie wyników aux w API (bundle może zawierać głowy, ale API zwraca tylko 5 superklas).

## Pliki

- `src/cardioai/data/aux_labels.py` — nowy
- `src/cardioai/training/hooks_aux.py` — nowy (hook metryk aux dla `Trainer.metric_hooks`, T204)
- `scripts/train.py` — zmiana (podpięcie hooka aux, gdy `model.heads.aux` jest niepuste)
- `configs/experiment/e05e_aux.yaml` — nowy
- `tests/unit/data/test_aux_labels.py` — nowy

## Interfejs (wiążący)

```python
def select_aux_labels(index: pd.DataFrame, statements: pd.DataFrame, *, kind: Literal["rhythm", "form"],
                      min_positives: int = 200) -> list[str]: ...      # tylko na train
class AuxLabelProvider:                                                 # FieldProvider
    def __init__(self, labels: Mapping[str, Sequence[str]]) -> None: ...
```

## Kryteria akceptacji

- [ ] Listy etykiet wyznaczane wyłącznie z train; zapisane w checkpoincie i odtwarzane przy ewaluacji.
- [ ] Run E05e w MLflow; porównanie macro AUROC superklas z wariantem bez głów aux (te same seedy).
- [ ] Wniosek (włączyć / nie włączać) w `docs/experiments.md` (E05).

## Testy

- `test_aux_labels.py`: wybór kodów na fixture, `min_positives`, kształty pól `aux`.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_aux_labels.py -q
uv run python scripts/train.py --config configs/experiment/e05e_aux.yaml
```

## Wskazówki i pułapki

- Niektóre kody są jednocześnie rytmem i formą — dopuszczalne, ale nie licz ich podwójnie w jednej głowie.
- Zadanie jest opcjonalne: realizuj po ustabilizowaniu Core (bramka G4 w toku nie może na nim czekać).
