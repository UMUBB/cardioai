---
id: T304
title: Quality gate ACCEPT/WARN/REJECT z regułami twardymi i progami z val
epic: quality
owner: A
reviewer: C
week: 6
size: M
level: Core
gate: G4
experiment: E05
depends_on: [T303]
status: todo
---

# T304 — Quality gate ACCEPT / WARN / REJECT

## Kontekst

- `docs/reliability.md` §4 (reguły, wynik, dobór progów, format JSON, wiążące API)
- `docs/architecture.md` §7 (statusy)
- `docs/inference_api.md` §5 (ostrzeżenia `FLAT_LEAD`, `SATURATION`, `QUALITY_WARN`)

## Cel

System potrafi jawnie odmówić klasyfikacji słabego sygnału, a koszt tej decyzji (ile rekordów odrzuca, jak zmienia się jakość na pozostałych) jest zmierzony.

## Zakres

- `HardRules` (płaskie odprowadzenia, saturacja) działające na sygnale w mV.
- `QualityGate.decide` łączący reguły i wynik modelu (`quality_score = 1 − max sigmoid`), status = najgorszy z obu.
- `fit_gate_thresholds` według kryteriów §4 i `gate_tradeoff_table` (siatka progów: odsetek odrzuceń, FRR na czystym val,
  wykrywalność korupcji, macro AUROC na zaakceptowanych).
- `scripts/fit_quality_gate.py`: wejście `predictions_val.parquet` + `predictions_val_qsynth.parquet` → `quality_gate.json`, tabela, wykres; log do MLflow (`quality_gate/`).

## Poza zakresem

- Integracja z `Predictor` (T610).

## Pliki

- `src/cardioai/reliability/__init__.py`, `src/cardioai/reliability/quality_gate.py` — nowe
- `scripts/fit_quality_gate.py` — nowy
- `tests/unit/reliability/test_quality_gate.py` — nowy

## Interfejs (wiążący)

```python
@dataclass
class QualityDecision:
    status: Literal["ACCEPT", "WARN", "REJECT"]
    score: float | None
    artifacts: dict[str, float]
    reasons: list[str]

class HardRules:
    def __init__(self, *, flat_std_mv: float = 0.01, flat_reject_min_leads: int = 3,
                 saturation_fraction: float = 0.02) -> None: ...
    def check(self, signal_mv: np.ndarray) -> tuple[str, list[str]]: ...

class QualityGate:
    def __init__(self, *, t_warn: float, t_reject: float, rules: HardRules, enabled: bool = True) -> None: ...
    def decide(self, quality_probs: np.ndarray | None, signal_mv: np.ndarray) -> QualityDecision: ...
    def to_dict(self) -> dict[str, Any]: ...
    @classmethod
    def from_dict(cls, d: Mapping[str, Any]) -> "QualityGate": ...

def fit_gate_thresholds(scores_clean: np.ndarray, *, max_false_reject: float = 0.02,
                        max_warn: float = 0.10) -> tuple[float, float]: ...   # (t_warn, t_reject)
def gate_tradeoff_table(scores: np.ndarray, *, is_clean: np.ndarray, is_corrupted: np.ndarray,
                        y_true: np.ndarray, y_prob: np.ndarray, grid: Sequence[float]) -> pd.DataFrame: ...
```

## Kryteria akceptacji

- [ ] FRR na czystym val ≤ 2% przy dobranym `t_reject`; `WARN` na czystym val ≤ 10% przy `t_warn`.
- [ ] Tabela trade-off i wykres w MLflow; wybrane progi w `quality_gate.json` zgodnym z `docs/reliability.md` §4.
- [ ] Reguły twarde: 1–2 płaskie odprowadzenia → `WARN` z powodem `FLAT_LEAD`, ≥ 3 → `REJECT`; saturacja → `WARN` (`SATURATION`).
- [ ] `quality_probs=None` (model bez głowy jakości) → decyzja tylko z reguł, `score=None`.
- [ ] `to_dict` → `from_dict` daje identyczne decyzje.

## Testy

- `test_quality_gate.py`: reguły na syntetycznych sygnałach, łączenie statusów, dobór progów na rozkładach znanych z góry, round-trip JSON.

## Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_quality_gate.py -q
uv run python scripts/fit_quality_gate.py --predictions <eval/val/predictions_val.parquet> --synthetic <eval/val/predictions_val_qsynth.parquet>
```

## Wskazówki i pułapki

- „Czysty val” = rekordy bez słabych flag jakości i bez korupcji; to przybliżenie — zaznacz to w raporcie.
- Saturację wykrywaj jako plateau (wiele kolejnych próbek na tej samej wartości ekstremalnej), nie jako samą wysoką amplitudę.
