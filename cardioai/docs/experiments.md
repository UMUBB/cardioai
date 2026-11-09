# Eksperymenty i hipotezy

Właściciel: B (wszyscy wnoszą wyniki). Wyniki liczbowe wstawia `scripts/summarize_runs.py` między znaczniki
`<!-- BEGIN:Exx -->` i `<!-- END:Exx -->` — nie edytuj ich ręcznie.

## 1. Zasady

1. Każdy eksperyment ma pytanie, warianty, elementy stałe, metryki i **regułę decyzyjną ustaloną przed uruchomieniem**.
2. Porównujemy warianty w tym samym protokole: te same foldy, ten sam preprocessing (o ile nie jest przedmiotem badania), te same seedy.
3. Decyzje zapadają na val (fold 9). Test (fold 10) — tylko E-final w T801.
4. Warianty, które przechodzą do modelu finalnego, uruchamiamy dla 3 seedów (0, 1, 2).
5. Wniosek z każdego eksperymentu zapisujemy w sekcji „Wniosek” jednym akapitem i — jeśli zmienia projekt — w `docs/decisions.md`.

## 2. Hipotezy

| ID | Hipoteza | Eksperymenty |
|---|---|---|
| H1 | Residual 1D (ResNet1D) osiągnie wyższą jakość i stabilność niż płytki CNN przy akceptowalnym koszcie inferencji. | E02, E03, E07 |
| H2 | Fuzja metadanych może poprawić kalibrację i część klas, ale wymaga kontroli shortcut learning. | E08 |
| H3 | Lead dropout w treningu zwiększy odporność na brak odprowadzeń bez istotnego spadku na pełnym 12-lead. | E06 |
| H4 | Kalibracja post-hoc i abstention zwiększą wiarygodność kosztem coverage. | E09 |
| H5 | 500 Hz nie poprawi jakości proporcjonalnie do 5× większego kosztu. | E10 |
| H6 | Model wielozadaniowy z zadaniem jakości sygnału jest odporniejszy na artefakty. | E05, E06 |

## 3. Rejestr eksperymentów

| ID | Eksperyment | Zadania | Właściciel | Tydzień | Cel decyzyjny |
|---|---|---|---|---|---|
| E00 | EDA i sanity checks | T104, T110 | A | 2–3 | liczebności, split, brak przecieku |
| E01 | Baseline klasyczny | T203 | C | 3 | weryfikacja etykiet i metryk |
| E02 | Mały CNN 1D | T205 | B | 3 | pierwszy end-to-end deep baseline |
| E03 | ResNet1D | T207, T209 | B | 4–5 | model referencyjny |
| E04 | Imbalance: wagi, focal, progi | T208 | B | 5 | wybór funkcji straty i metody progów |
| E05 | Multitask z jakością sygnału (+ głowy pomocnicze) | T303, T403 | A | 6, 9 | czy włączyć głowę jakości / głowy aux |
| E06 | Lead dropout i robustness | T305, T306 | B | 7 | odporność kanałowa i na zakłócenia |
| E07 | Transformer | T401 | B | 8 | porównanie biasów indukcyjnych |
| E08 | Fuzja metadanych | T402 | B | 9 | wartość danych pozasygnałowych |
| E09 | Kalibracja i abstention | T501, T502, T504 | C | 10–11 | wiarygodność predykcji |
| E10 | 100 vs 500 Hz | T404 | B | 11 | koszt vs jakość |
| E11 | XAI i benchmark wdrożeniowy | T503, T703, T704 | C/B/A | 11–13 | gotowość systemowa |

## 4. Karty eksperymentów

### E00 — EDA i sanity checks

- **Pytanie:** czy indeks odtwarza liczby z PhysioNet i czy split jest wolny od przecieku?
- **Wynik:** `reports/eda/` + uzupełnienie `docs/data_contract.md` §15.
- **Reguła:** wszystkie testy kontraktu danych (T104) zielone; różnice liczebności wyjaśnione.

### E01 — Baseline klasyczny

- **Warianty:** cechy statystyczne i widmowe + regresja logistyczna (one-vs-rest); opcjonalnie LightGBM.
- **Stałe:** 100 Hz, val = fold 9.
- **Reguła:** macro AUROC val > 0,70 (sanity); niższy wynik → przegląd etykiet i splitu przed dalszą pracą.

<!-- BEGIN:E01 -->
_Brak wyników — uzupełni `scripts/summarize_runs.py`._
<!-- END:E01 -->

### E02 — Mały CNN 1D

- **Warianty:** `cnn_small`, 1 seed (3 seedy do tabeli H1).
- **Reguła:** macro AUROC val ≥ 0,80 i pipeline MLflow kompletny → bramka G2.

<!-- BEGIN:E02 -->
_Brak wyników._
<!-- END:E02 -->

### E03 — ResNet1D

- **Warianty:** `resnet1d` z configu startowego; ewentualny mały sweep `lr ∈ {1e-3, 3e-4, 1e-4}` i `kernel_size ∈ {5, 7, 9}`.
- **Stałe:** 100 Hz, BCE bez wag (do E04), augmentacje bazowe.
- **Metryki:** macro/micro AUROC, AP, per klasa, parametry, MFLOPs, czas epoki.
- **Reguła:** ResNet1D stabilny na 3 seedach (std macro AUROC ≤ 0,01) → bramka G3; porównanie z E02 → H1.

<!-- BEGIN:E03 -->
_Brak wyników._
<!-- END:E03 -->

### E04 — Nierównowaga klas

- **Warianty:** `e04a_bce`, `e04b_posweight` (`pos_weight: train`), `e04c_focal` (`γ = 2`); progi `f1` vs `youden`.
- **Reguła:** wybieramy wariant z najwyższym macro F1 (progi z val), o ile macro AUROC nie spada o więcej niż 0,005 względem `e04a`.

<!-- BEGIN:E04 -->
_Brak wyników._
<!-- END:E04 -->

### E05 — Multitask z jakością sygnału

- **Warianty:** tylko diagnoza; diagnoza + jakość (`lambda_quality ∈ {0.5, 1.0}`, korupcje syntetyczne `p = 0.3`);
  osobny QualityNet; opcjonalnie głowy rhythm/form (T403).
- **Metryki:** macro AUROC diagnozy na czystym val, macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`, T303), AUROC jakości (syntetyczny val i słabe etykiety), FRR quality gate.
  Krzywe robustness z E06 są raportowane w T306 jako uzupełnienie, nie jako warunek decyzji.
- **Reguła (D-027, status: proponowana):** włączamy głowę jakości, jeśli spadek macro AUROC diagnozy na czystym val ≤ 0,005, a macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`) wzrasta. Głowy aux — analogicznie.

<!-- BEGIN:E05 -->
_Brak wyników._
<!-- END:E05 -->

### E06 — Lead dropout i robustness

- **Warianty:** `lead_dropout.p ∈ {0, 0.3, 0.5}`; pełna robustness suite (`docs/reliability.md` §8) dla każdego.
- **Reguła (H3):** wariant z lead dropout przyjmujemy, gdy średni spadek przy 1 brakującym odprowadzeniu maleje co najmniej o połowę,
  a macro AUROC na pełnym 12-lead spada ≤ 0,005.

<!-- BEGIN:E06 -->
_Brak wyników._
<!-- END:E06 -->

### E07 — Transformer

- **Warianty:** `transformer` (patch 25, `d_model 256`, 6 warstw) z liczbą parametrów w przedziale 0,5–2× ResNet1D; pooling `cls` vs `mean`.
- **Reguła:** raportujemy niezależnie od wyniku; Transformer zastępuje ResNet1D tylko przy przewadze ≥ 0,005 macro AUROC i nie gorszej kalibracji.

<!-- BEGIN:E07 -->
_Brak wyników._
<!-- END:E07 -->

### E08 — Fuzja metadanych

- **Warianty:** tylko EKG; EKG + metadane (`age`, `sex`, `height`, `weight` z maskami); tylko metadane (MLP — miara siły skrótu).
- **Analiza podgrup:** płeć, wiek (< 40, 40–60, 60–75, > 75) — macro AUROC i ECE per podgrupa.
- **Reguła:** metadane włączamy, gdy zysk ≥ 0,005 macro AUROC lub wyraźna poprawa ECE, bez pogłębienia różnic między podgrupami.
  Wynik „tylko EKG” zawsze w tabeli głównej.

<!-- BEGIN:E08 -->
_Brak wyników._
<!-- END:E08 -->

### E09 — Kalibracja i abstention

- **Warianty:** kalibracja `identity` / `temperature` (globalna, per klasa) / `isotonic`; abstention `max_entropy` / `min_margin` / `combined`.
- **Metryki:** Brier, ECE (przed/po, cross-fitting), AURC, selective risk przy coverage 0,95 / 0,90 / 0,80.
- **Reguła:** wybieramy kalibrator z najniższym ECE w cross-fittingu; metodę abstention z najniższym AURC; τ dla coverage 0,90.

<!-- BEGIN:E09 -->
_Brak wyników._
<!-- END:E09 -->

### E10 — 100 vs 500 Hz

- **Warianty:** ResNet1D 100 Hz; ResNet1D 500 Hz (ta sama architektura, ok. 5× koszt); ResNet1D 500 Hz z `stem_stride=10` (koszt zbliżony do 100 Hz).
- **Metryki:** macro AUROC (per klasa, szczególnie STTC), czas epoki, opóźnienie, pamięć.
- **Reguła (H5):** 500 Hz uzasadnione tylko przy zysku ≥ 0,005 macro AUROC na 3 seedach.

<!-- BEGIN:E10 -->
_Brak wyników._
<!-- END:E10 -->

### E11 — XAI i benchmark wdrożeniowy

- **Zakres:** testy poprawności XAI (kompletność, randomizacja), przykłady atrybucji dla rekordów val,
  opóźnienie p50/p95, przepustowość, pamięć, rozmiar artefaktu dla PyTorch CPU/CUDA/MPS i ONNX (opcjonalnie INT8).
- **Reguła:** kwantyzację INT8 przyjmujemy, gdy spadek macro AUROC ≤ 0,005, a opóźnienie CPU maleje ≥ 30%.

<!-- BEGIN:E11 -->
_Brak wyników._
<!-- END:E11 -->

## 5. Tabela zbiorcza

Generowana przez `scripts/summarize_runs.py --all` (kolumny: `docs/evaluation.md` §6). Wyniki testu dopisuje T801.

<!-- BEGIN:SUMMARY -->
_Brak wyników._
<!-- END:SUMMARY -->
