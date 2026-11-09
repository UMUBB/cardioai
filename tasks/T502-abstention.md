---
id: T502
title: Abstention i krzywe risk–coverage (E09, H4)
epic: reliability
owner: C
reviewer: B
week: 10
size: M
level: Core
gate: G4
experiment: E09
depends_on: [T304, T501]
status: todo
---

# T502 — Abstention i krzywe risk–coverage (E09, H4)

## Kontekst

- `docs/reliability.md` §1 (cross-fitting), §6 (miary niepewności, polityka, AURC, format JSON)
- `docs/experiments.md` §2 (H4), §4 (E09)
- `docs/architecture.md` §7 (status `ABSTAIN`)

## Cel

System ma jawne prawo do „nie wiem”, a cena tej decyzji (coverage) i zysk (niższe ryzyko na zaakceptowanych) są zmierzone dla kilku miar niepewności.

## Zakres

- Miary `max_entropy`, `min_margin`, `combined` (z `quality_score` z T304).
- `AbstentionPolicy` z doborem `τ` dla docelowego coverage; serializacja JSON.
- Krzywe risk–coverage (Hamming loss, macro F1, macro AUROC na zaakceptowanych), AURC, tabela przy coverage 1,00 / 0,95 / 0,90 / 0,80, wynik cross-fitting.
- `scripts/abstention_report.py`: wejście predykcje val + `calibration.json` + `thresholds.json` (+ opcjonalnie `quality_gate.json`) → `abstention.json`, wykresy, tabela, MLflow (`abstention/`)
  oraz metryki `val/aurc`, `val/selective_risk_cov095`, `val/selective_risk_cov090`, `val/selective_risk_cov080` (nazwy: `docs/mlops.md` §3, D-029).
- Wniosek H4 w E09.

## Poza zakresem

- Conformal prediction (rozszerzenie po przedmiocie), integracja z `Predictor` (T610).

## Pliki

- `src/cardioai/reliability/abstention.py` — nowy
- `scripts/abstention_report.py` — nowy
- `tests/unit/reliability/test_abstention.py` — nowy

## Interfejs (wiążący)

```python
def uncertainty_scores(probs: np.ndarray, *, method: Literal["max_entropy", "min_margin", "combined"],
                       thresholds: np.ndarray | None = None, quality_score: np.ndarray | None = None) -> np.ndarray: ...  # [N] w [0, 1]

@dataclass
class AbstentionPolicy:
    method: str
    tau: float
    target_coverage: float
    enabled: bool = True
    def should_abstain(self, u: float | np.ndarray) -> bool | np.ndarray: ...
    def to_dict(self) -> dict[str, Any]: ...
    @classmethod
    def from_dict(cls, d: Mapping[str, Any]) -> "AbstentionPolicy": ...

def fit_tau(u_val: np.ndarray, target_coverage: float) -> float: ...
def risk_coverage_curve(y_true: np.ndarray, y_pred: np.ndarray, y_prob: np.ndarray, u: np.ndarray) -> pd.DataFrame: ...
def aurc(curve: pd.DataFrame, risk_col: str = "hamming_loss") -> float: ...
```

## Kryteria akceptacji

- [ ] Miary w zakresie [0, 1]; `max_entropy` = 1 dla p = 0,5 i 0 dla p ∈ {0, 1}.
- [ ] `fit_tau` daje coverage na val równe docelowemu ±0,5 p.p.
- [ ] Na danych syntetycznych, gdzie błędy korelują z niepewnością, ryzyko maleje monotonicznie z malejącym coverage (test).
- [ ] Tabela E09 (abstention): AURC i selective risk dla 3 metod, także out-of-fold; wybór metody i `τ` według reguły E09.
- [ ] `abstention.json` zgodny z `docs/reliability.md` §6.

## Testy

- `test_abstention.py`: wartości graniczne miar, `fit_tau`, krzywa i AURC na przykładzie liczonym ręcznie, round-trip JSON.

## Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_abstention.py -q
uv run python scripts/abstention_report.py --predictions <predictions_val.parquet> --calibration <calibration.json> --thresholds <thresholds.json>
```

## Wskazówki i pułapki

- Niepewność licz na prawdopodobieństwach **po kalibracji** i z progami z `thresholds.json` (`on_calibrated: true`).
- Macro AUROC na małym zaakceptowanym podzbiorze bywa niezdefiniowany — raportuj `NaN` zamiast przerywać.
