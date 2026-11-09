---
id: T305
title: Robustness suite — testy odporności z raportem
epic: quality
owner: B
reviewer: A
week: 7
size: M
level: Core
gate: G4
experiment: E06
depends_on: [T206, T302, T304]
status: todo
---

# T305 — Robustness suite: testy odporności z raportem

## Kontekst

- `docs/reliability.md` §8 (lista testów, siatki, format CSV)
- `docs/data_contract.md` §8 (kroki 3 i 7–8), §13 (konwencja brakującego odprowadzenia)
- `docs/experiments.md` §4 (E06)
- `docs/decisions.md`: D-023

## Cel

Powtarzalny pomiar, jak spada jakość modelu przy brakujących odprowadzeniach, szumie, dryfcie i zmianie preprocessingu — dla każdego kandydata na model finalny.

## Zakres

- `RobustnessTest`, `run_robustness` z wstrzykiwaną funkcją predykcji (bez importu `cardioai.training`, zgodnie z granicami modułów).
- Testy: `missing_lead`, `random_lead_dropout`, `gaussian_noise`, `baseline_drift`, `powerline` (tylko `fs > 100`),
  `electrode_flat`, `preprocessing_shift`, `sampling_rate` — parametry z `configs/robustness/default.yaml`.
- Progi z val zamrożone (`thresholds.json`); opcjonalnie quality gate → kolumna `gate_reject_rate`.
- `scripts/robustness.py --checkpoint PATH --split val [--suite PATH] [--gate PATH]` → `robustness.csv` + wykresy (krzywe degradacji, mapa Δ per odprowadzenie), log do MLflow (`robustness/`).

## Poza zakresem

- Uruchamianie na teście (tylko T801), trening z lead dropout (T306).

## Pliki

- `src/cardioai/reliability/robustness.py` — nowy
- `scripts/robustness.py` — nowy
- `configs/robustness/default.yaml` — nowy
- `tests/unit/reliability/test_robustness.py` — nowy

## Interfejs (wiążący)

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

## Kryteria akceptacji

- [ ] Wszystkie testy z `docs/reliability.md` §8 zaimplementowane; `powerline` pomijany z informacją przy 100 Hz.
- [ ] `missing_lead` zeruje odprowadzenie **po** normalizacji (test: wartość 0.0 i `lead_mask=False` na wejściu modelu); korupcje w mV **przed** filtrem.
- [ ] CSV ma kolumny `test, param, value, repeat, metric, score, clean_score, delta, gate_reject_rate`.
- [ ] Wynik deterministyczny dla tego samego seeda.
- [ ] Pełna suite dla ResNet1D na val działa w < 30 min na laptopie z RTX (czas w PR).
- [ ] Odmowa uruchomienia na `test` bez odblokowania.

## Testy

- `test_robustness.py`: na fixture z funkcją predykcji-atrapą — kolejność kroków, format CSV, determinizm, pominięcie `powerline` przy 100 Hz.

## Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_robustness.py -q
uv run python scripts/robustness.py --checkpoint <best.pt> --split val
```

## Wskazówki i pułapki

- `make_loader` buduje dataset val przez `build_pipeline(train=False, robustness_corruption=...)` — korupcja testu trafia do kroku 3 (w mV, przed filtrem i normalizacją; D-023); nie mieszaj z augmentacjami.
- `preprocessing_shift` wymaga dwóch statystyk normalizacji (dla wariantu z filtrem i bez) — pliki z T107/T108.
