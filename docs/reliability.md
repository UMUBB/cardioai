# Niezawodność: jakość sygnału, kalibracja, abstention, XAI, robustness

Status: **wiążący** (§2, §4–§7: formaty plików i definicje). Kod: `src/cardioai/reliability/`, `src/cardioai/data/corruptions.py`.
Właściciele: A (§2–§4), C (§5–§7), B (§8).

## 1. Przegląd

| Komponent | Pytanie | Dopasowanie | Wynik w bundlu |
|---|---|---|---|
| Model jakości | czy sygnał ma artefakty? | trening (train) | wagi głowy jakości |
| Quality gate | czy w ogóle klasyfikować? | progi na val | `quality_gate` |
| Kalibracja | czy 0,8 znaczy 80%? | val | `calibration` |
| Progi | kiedy klasa jest „pozytywna”? | val (po kalibracji) | `thresholds` |
| Abstention | czy model ma prawo odpowiedzieć? | τ na val | `abstention` |
| XAI | które fragmenty sygnału wpływają na wynik? | — | `explanation` |
| Robustness | jak spada jakość przy zakłóceniach? | — (raport) | — |

Kolejność dopasowania na val: kalibracja → progi → quality gate → abstention. Wielokrotne użycie foldu 9 jest świadomym
ograniczeniem (`docs/decisions.md` D-015); do raportu metryki po kalibracji i abstention liczymy dodatkowo w schemacie
**cross-fitting**: val dzielimy patient-wise na dwie połowy, dopasowujemy na jednej, oceniamy na drugiej i odwrotnie.

## 2. Etykiety jakości i korupcje syntetyczne

Klasy jakości: `QUALITY_LABELS = ("static_noise", "burst_noise", "baseline_drift", "electrode_problem")`.
Słabe etykiety z PTB-XL: `docs/data_contract.md` §11. Korupcje działają w mV, w kroku 3 pipeline'u (`docs/data_contract.md` §8).

| Korupcja | Parametry (zakres do treningu jakości) | Etykieta |
|---|---|---|
| `gaussian_noise` | `snr_db ∈ [0, 15]` (moc liczona per odprowadzenie) | `static_noise` |
| `powerline` | `freq_hz = 50`, `amplitude_mv ∈ [0.05, 0.3]`; tylko gdy `fs > 100` | `static_noise` |
| `burst_noise` | 1–3 segmenty po 0,2–1,0 s, `snr_db ∈ [-5, 5]` w segmencie | `burst_noise` |
| `baseline_drift` | `amplitude_mv ∈ [0.3, 1.5]`, `freq_hz ∈ [0.05, 0.5]`, faza losowa | `baseline_drift` |
| `electrode_flat` | 1–3 odprowadzenia stałe 0 mV + szum 0,01 mV | `electrode_problem` |
| `electrode_pop` | 1–2 odprowadzenia: skok 0,5–2 mV z wykładniczym powrotem (τ 0,2–1 s) | `electrode_problem` |
| `saturation` | obcięcie do `±clip_mv`, `clip_mv ∈ [1.0, 2.5]` | brak (wykrywa reguła twarda, §4) |

Wiążące API:

```python
@dataclass
class CorruptionResult:
    x: np.ndarray               # [12, T] float32, mV
    quality: np.ndarray         # [4] int8, kolejność QUALITY_LABELS
    lead_mask: np.ndarray       # [12] bool
    params: dict[str, float | int | str]

def apply_corruption(name: str, x: np.ndarray, fs: int, rng: np.random.Generator, **params) -> CorruptionResult: ...
class CorruptionSampler:        # trening: z prawd. p losuje 1–2 korupcje z listy i zakresów powyżej
    def __call__(self, x: np.ndarray, fs: int, rng: np.random.Generator) -> CorruptionResult: ...
```

## 3. Model jakości (głowa / QualityNet)

- Wariant główny: głowa `quality` na wspólnym enkoderze ResNet1D (multitask, `lambda_quality > 0`).
- Wariant porównawczy: osobny mały QualityNet (`cnn_small`, `lambda_diag = 0`, `heads.quality = true`).
- Cel: `y_quality = słabe etykiety OR etykiety korupcji` (gdy korupcja zastosowana).
- Ewaluacja na val (deterministyczna):
  1. **zbiór syntetyczny** — każdy rekord val w wersji czystej i w jednej korupcji (RNG z `[seed, ecg_id, corruption_index]`, zgodnie z T302) → AUROC per etykieta;
  2. **słabe etykiety** — AUROC per etykieta na oryginalnym val (miara przybliżona);
  3. **false reject rate** na „czystym” val (brak flag jakości) przy progach gate'u.

## 4. Quality gate

Reguły twarde (przed modelem, na sygnale w mV po walidacji):

| Reguła | Warunek | Skutek |
|---|---|---|
| płaskie odprowadzenie | `std < 0.01 mV` na całym odprowadzeniu | 1–2 odprowadzenia → `WARN`, ≥ 3 → `REJECT`; powód `FLAT_LEAD` |
| saturacja | ≥ 2% próbek odprowadzenia na wartości ekstremalnej (plateau) | `WARN`; powód `SATURATION` |

Wynik modelu: `quality_score = 1 − max_k sigmoid(quality_logit_k)` (1 = czysty sygnał).

```text
ACCEPT  gdy quality_score ≥ t_warn
WARN    gdy t_reject ≤ quality_score < t_warn
REJECT  gdy quality_score < t_reject
status końcowy = najgorszy z (reguły twarde, model)
```

Dobór progów na val: `t_reject` — największa wartość, przy której false reject rate na czystym val ≤ 2%;
`t_warn` — tak, aby `WARN` na czystym val ≤ 10%. Obie granice to parametry skryptu. Raport trade-off: dla siatki progów
odsetek odrzuceń, FRR, wykrywalność korupcji i macro AUROC na zaakceptowanych.

```json
{"enabled": true, "t_warn": 0.80, "t_reject": 0.50, "fitted_on": "val",
 "rules": {"flat_std_mv": 0.01, "flat_reject_min_leads": 3, "saturation_fraction": 0.02},
 "criteria": {"max_false_reject_clean": 0.02, "max_warn_clean": 0.10}}
```

Wiążące API: `QualityGate.decide(quality_probs: np.ndarray | None, signal_mv: np.ndarray) -> QualityDecision`
(`status`, `score`, `artifacts: dict[str, float]`, `reasons: list[str]`). Bez głowy jakości działają same reguły twarde.

## 5. Kalibracja

Metody (`Calibrator`: `fit(logits, y)`, `predict_proba(logits)`, `to_dict()`, `from_dict()`):

- `temperature` — `p = sigmoid(logit / T)`; `T` globalne lub per klasa (`per_class=true`), optymalizacja log T
  minimalizująca BCE na val (L-BFGS); `T` ograniczone do `[0.05, 20]`.
- `isotonic` — per klasa `IsotonicRegression(out_of_bounds="clip")`; zapis jako listy punktów `(x, y)`, stosowanie przez `np.interp`
  (bez pickle w bundlu). Dostępny tylko wtedy, gdy **każda** klasa ma ≥ 200 pozytywów na val; jeśli którakolwiek ma mniej, metoda jest niedostępna
  dla całego modelu, a `fit` zgłasza `ValueError` z listą takich klas.
- `identity` — brak kalibracji.

```json
{"method": "temperature", "per_class": true, "fitted_on": "val",
 "temperature": [1.21, 1.08, 1.33, 0.97, 1.40], "source_run_id": "…"}
```

Raport: Brier i ECE per klasa przed i po kalibracji, reliability diagram per klasa (15 przedziałów + histogram liczności),
wynik cross-fitting (§1).

## 6. Abstention

Miary niepewności (na prawdopodobieństwach po kalibracji, `t_c` — progi z `thresholds.json`):

| Metoda | Definicja | Zakres |
|---|---|---|
| `max_entropy` | `u = max_c H2(p_c)`, `H2` — entropia binarna w bitach | [0, 1] |
| `min_margin` | `u = 1 − min_c ( \|p_c − t_c\| / max(t_c, 1 − t_c) )` | [0, 1] |
| `combined` | `u = max(u_max_entropy, 1 − quality_score)` | [0, 1] |

Polityka: `abstain = u > τ`. `τ` dobierane na val dla docelowego coverage (domyślnie 0,90).

Krzywa risk–coverage: sortujemy rekordy rosnąco po `u`; dla coverage `k/N` liczymy na zaakceptowanych:
selective risk = Hamming loss (miara główna), macro F1 i macro AUROC (gdy każda klasa ma oba warianty etykiet).
`AURC` — pole pod krzywą ryzyka (trapezy). Tabela raportu: coverage 1,00 / 0,95 / 0,90 / 0,80.

```json
{"enabled": true, "method": "max_entropy", "tau": 0.62, "target_coverage": 0.90, "fitted_on": "val",
 "val_coverage": 0.90, "val_selective_risk": 0.071, "aurc": 0.058}
```

## 7. XAI

- Metody: `integrated_gradients` (domyślna; `n_steps = 50`; baseline = zera w przestrzeni znormalizowanej,
  czyli „średni sygnał” z train; dla `normalization: per_record` i `none` baseline „zera” oznacza zera w przestrzeni wejścia modelu), `saliency`, `gradient_x_input`. Preferowany Captum; dopuszczalna własna implementacja IG
  z tym samym interfejsem i testem kompletności.
- Klasa docelowa: wskazana przez użytkownika (`explain_class`) albo pozytywna klasa o najwyższym prawdopodobieństwie,
  a gdy brak pozytywnych — klasa o najwyższym prawdopodobieństwie.

```python
@dataclass
class Attribution:
    method: str
    target_class: str
    values: np.ndarray          # [12, T] float32, ze znakiem
    lead_importance: np.ndarray # [12], Σ_t |A| / Σ |A|, suma = 1
    time_attribution: np.ndarray  # [T], Σ_l |A| wygładzone (średnia ruchoma 0,1 s), skala [0, 1]
    convergence_delta: float | None

def explain(model: nn.Module, x: torch.Tensor, target: int, *, method: str = "integrated_gradients",
            n_steps: int = 50, internal_batch_size: int = 16) -> Attribution: ...
```

- Do API: `values` uśrednione do maks. 100 Hz i przeskalowane przez `max |A|` do `[-1, 1]`.
- Testy poprawności: kompletność IG `|Σ A − (f(x) − f(x₀))| / |f(x) − f(x₀)| < 0.05`; jednorazowo w raporcie
  test randomizacji wag (mapy dla modelu z losowymi wagami muszą się różnić).
- Budżet: ≤ 1,5 s na rekord na CPU (100 Hz, ResNet1D).
- Stały komunikat w API i UI: „Mapa atrybucji pokazuje wrażliwość modelu na fragmenty sygnału, a nie przyczynę kliniczną.”

## 8. Robustness suite

Ewaluacja na val (w trakcie prac) z **zamrożonymi** progami z val; na teście tylko w T801. Konfiguracja: `configs/robustness/default.yaml`.

| Test | Procedura | Siatka | Raport |
|---|---|---|---|
| `missing_lead` | zero w przestrzeni znormalizowanej dla każdego z 12 odprowadzeń | 12 przebiegów | Δ macro AUROC i Δ macro F1 per odprowadzenie |
| `random_lead_dropout` | losowe k odprowadzeń | k ∈ {1, 2, 3}, 3 powtórzenia | średnia ± std w funkcji k |
| `gaussian_noise` | szum o zadanym SNR | {30, 20, 10, 5, 0} dB | krzywa degradacji |
| `baseline_drift` | sinus 0,3 Hz | {0.1, 0.25, 0.5, 1.0} mV | krzywa degradacji |
| `powerline` | 50 Hz (tylko 500 Hz) | {0.05, 0.1, 0.2} mV | krzywa degradacji |
| `electrode_flat` | k płaskich odprowadzeń w mV | k ∈ {1, 2, 3} | Δ + odsetek odrzuceń przez gate |
| `preprocessing_shift` | model z filtrem na danych bez filtra i odwrotnie | 2 warianty | Δ per klasa (szczególnie STTC) |
| `sampling_rate` | 500 Hz zresamplowane do 100 Hz vs natywne 100 Hz | 1 | Δ |

Wynik: plik `robustness.csv` w formacie „tidy”:
`test, param, value, repeat, metric, score, clean_score, delta, gate_reject_rate` + wykresy PNG, logowane do MLflow (`robustness/`).
