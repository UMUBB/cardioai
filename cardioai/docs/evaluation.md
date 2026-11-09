# Ewaluacja i metryki

Status: **wiążący** (§2–§5, §7). Kod: `src/cardioai/evaluation/`. Właściciele: B (protokół), C (metryki).

## 1. Zasady ewaluacji

1. Wszystkie decyzje (architektura, hiperparametry, progi, kalibracja, quality gate, abstention) zapadają na **val (fold 9)**.
2. **Test (fold 10)** jest używany jednorazowo, po zamrożeniu konfiguracji (§7).
3. Metryki liczymy w NumPy (float64) na zebranych predykcjach całego splitu — nie uśredniamy metryk z batchy.
4. Referencją implementacji jest scikit-learn; własny kod musi zgadzać się z nim w testach (tolerancja 1e-9).
5. Raportujemy zawsze per klasa oraz uśrednienie macro; pojedynczy wynik AUROC nie jest wystarczający.

## 2. Metryki klasyfikacji — definicje

| Metryka | Definicja | Implementacja referencyjna |
|---|---|---|
| macro AUROC (główna) | średnia AUROC 5 klas | `roc_auc_score(y, p, average="macro")` |
| micro AUROC | AUROC po spłaszczeniu wszystkich par (rekord, klasa) | `average="micro"` |
| AUROC per klasa | — | `roc_auc_score(y[:, c], p[:, c])` |
| AP / PR-AUC per klasa i macro | average precision | `average_precision_score` |
| F1 per klasa i macro F1 | przy progach z §3 | `f1_score(..., zero_division=0)` |
| Czułość, swoistość | TP/(TP+FN), TN/(TN+FP) per klasa przy progach z §3 | macierz pomyłek per klasa |
| TP/FP/FN/TN | liczności per klasa | jw. |
| Brier | średnia `(p − y)^2` per klasa; `brier_macro` = średnia klas | `brier_score_loss` |
| ECE (klasowe) | 15 przedziałów równej szerokości na `p_c`; `Σ_b (n_b/N)·\|acc_b − conf_b\|`; `ece_macro` = średnia klas | własna (`expected_calibration_error`) |
| Hamming loss | odsetek błędnych decyzji (rekord, klasa) przy progach | `hamming_loss` |

Przypadki brzegowe: klasa bez przykładów pozytywnych lub negatywnych → metryka `NaN` z ostrzeżeniem; macro liczone z pominięciem `NaN`
i z jawną informacją w raporcie.

## 3. Progi decyzyjne

- Dobór na val, osobno dla każdej klasy (`evaluation.threshold_method`):
  - `f1` (domyślnie): maksimum F1 na siatce `0.01…0.99` co 0.01; remis → próg bliższy 0.5;
  - `youden`: maksimum `czułość + swoistość − 1` na tej samej siatce;
  - `fixed`: `evaluation.fixed_threshold` dla wszystkich klas.
- Gdy model jest kalibrowany, progi dobieramy **na prawdopodobieństwach po kalibracji** (`docs/reliability.md` §5).
- Plik `thresholds.json`:

```json
{"method": "f1", "fitted_on": "val", "on_calibrated": true,
 "values": {"NORM": 0.55, "MI": 0.41, "STTC": 0.38, "CD": 0.47, "HYP": 0.29},
 "source_run_id": "…", "created_at": "…"}
```

- Metryki progowe na val są optymistyczne (progi dobrane na tych samych danych) — w MLflow nazywamy je `val/macro_f1_tuned` i `val/f1_<KLASA>_tuned`
  (czułość i swoistość: `val/sensitivity_<KLASA>`, `val/specificity_<KLASA>`; Hamming loss: `val/hamming_loss`; nazwy w `docs/mlops.md` §3).

## 4. Plik predykcji

`predictions_<split>.parquet` (wynik `scripts/evaluate.py`, wejście kalibracji, progów i analiz):

| Kolumna | dtype | Opis |
|---|---|---|
| `ecg_id`, `patient_id`, `strat_fold` | int32 / int32 / int8 | identyfikacja |
| `y_<KLASA>` | int8 | etykiety (5 kolumn, kolejność `SUPERCLASSES`) |
| `logit_<KLASA>` | float32 | logity modelu |
| `prob_<KLASA>` | float32 | `sigmoid(logit)` przed kalibracją |
| `prob_cal_<KLASA>` | float32 | po kalibracji (gdy dostępna) |
| `qlogit_<ETYKIETA>` | float32 | logity jakości (gdy model ma głowę jakości) |
| `yq_<ETYKIETA>` | int8 | słabe etykiety jakości (gdy dostępne) |

Metadane pliku (schemat parquet): `run_id`, `checkpoint`, `config_hash`, `split`, `sampling_rate`, `preprocessing_version`.

## 5. Plik metryk

`metrics_<split>.json`:

```json
{
  "split": "val", "n_records": 2183, "run_id": "…", "checkpoint": "best.pt", "config_hash": "…",
  "macro_auroc": 0.921, "micro_auroc": 0.934, "macro_ap": 0.801,
  "macro_f1": 0.731, "hamming_loss": 0.101, "brier_macro": 0.083, "ece_macro": 0.031,
  "thresholds": {"method": "f1", "fitted_on": "val"},
  "per_class": {
    "NORM": {"auroc": 0.95, "ap": 0.93, "f1": 0.87, "sensitivity": 0.88, "specificity": 0.89,
             "threshold": 0.55, "support": 963, "tp": 0, "fp": 0, "fn": 0, "tn": 0,
             "brier": 0.08, "ece": 0.03}
  }
}
```

Liczby powyżej są ilustracyjne. Do MLflow trafiają te same wartości jako metryki `val/...` (`docs/mlops.md` §3).
Pole `macro_f1` z tego pliku to w MLflow `val/macro_f1_tuned` (progi dobrane na val, §3); `f1` per klasa to `val/f1_<KLASA>_tuned` (D-029).

## 6. Wiele seedów i raportowanie

- Modele finalne: min. 3 seedy (0, 1, 2) z identycznym `config_hash`.
- Tabela wyników: `średnia ± odchylenie standardowe` z seedów; generowana przez `scripts/summarize_runs.py` z MLflow.
- Kolumny tabeli porównawczej:
  `Model | Wariant | fs | Parametry (M) | MFLOPs | val macro-AUROC | val macro-AP | val macro-F1 | ECE | CPU p50 (ms) | n seedów`.
- Różnicę między wariantami uznajemy za istotną, gdy przedziały `średnia ± std` się nie nakładają albo sparowany bootstrap
  na val (§8) daje 95% przedział różnicy bez zera.

## 7. Blokada testu i protokół finalny

- `cardioai.data.test_lock`: każda próba zbudowania datasetu lub predykcji dla `split="test"` wymaga jednocześnie:
  zmiennej środowiskowej `CARDIOAI_ALLOW_TEST=1` oraz pliku `release/final_freeze.json` utworzonego przez
  `scripts/final_checklist.py`. W przeciwnym razie `LockedSplitError` (nazwa bez prefiksu `Test`, żeby pytest nie próbował jej zbierać jako klasy testowej).
- Każda ewaluacja testu dopisuje wpis do `release/final_test_log.jsonl` (czas, git SHA, wersja bundla, hash configu)
  i dostaje w MLflow tag `stage=final`.
- Checklista przed testem (automatyzuje T801, na podstawie Załącznika B specyfikacji):
  1. split pacjentów rozłączny i zgodny z foldami 1–8/9/10;
  2. statystyki normalizacji i metadanych pochodzą z train;
  3. fold 10 nie był użyty do wyboru architektury, progów ani augmentacji (log blokady pusty);
  4. wersja modelu, wersja preprocessingu i git SHA zapisane razem w bundlu;
  5. model finalny ma ≥ 3 seedy albo ograniczenie jest opisane;
  6. kalibrator dopasowany na val (`fitted_on: "val"`);
  7. XAI opisane jako atrybucja; karta modelu zawiera ograniczenia i zakaz zastosowań klinicznych;
  8. demo działa z czystego checkoutu zgodnie z README.

## 8. Przedziały ufności (bootstrap)

- Bootstrap **na poziomie pacjenta** (losujemy pacjentów ze zwracaniem, bierzemy wszystkie ich rekordy), `B = 1000`, seed 0.
- Przedział percentylowy 95% dla: macro AUROC, AUROC per klasa, macro F1.
- Wariant sparowany do porównań modeli: te same próbki bootstrapowe dla obu modeli, rozkład różnicy.

## 9. Punkt odniesienia z literatury

Benchmark PTB-XL (starsza rewizja zbioru, foldy 1–8/9/10) raportuje dla superklas diagnostycznych macro AUROC ok. 0,930
dla ResNet1D i ok. 0,928 dla XResNet1D. To **punkt orientacyjny**, nie cel do pobicia: różnią się wersja zbioru,
preprocessing i implementacja. Celem projektu jest zbliżenie się do tego poziomu przy poprawnym protokole
oraz dostarczenie elementów, których benchmark nie obejmuje (quality gate, kalibracja, abstention, robustness, deployment).
