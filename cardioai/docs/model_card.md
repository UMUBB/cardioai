# Karta modelu — CardioAI `<model_version>`

> Szablon. Wypełnia T802 na podstawie bundla finalnego, `release/final_test_log.jsonl` i raportów z MLflow.
> Liczby wklejamy z wygenerowanych plików, nie przepisujemy ręcznie.

## 1. Podstawowe informacje

| Pole | Wartość |
|---|---|
| Nazwa i wersja | `<model_version>` (bundle format 1) |
| Architektura | `<np. ResNet1D, 4 etapy 64→512, ~X M parametrów>` |
| Wejście | 12 odprowadzeń, 10 s, `<100>` Hz, mV |
| Wyjście | prawdopodobieństwa 5 superklas (NORM, MI, STTC, CD, HYP) po kalibracji, status jakości, flaga abstention |
| Data wydania | `<RRRR-MM-DD>` |
| Autorzy | zespół CardioAI (A, B, C), Uniwersytet Bielsko-Bialski |
| Pochodzenie | git SHA `<…>`, MLflow run `<…>`, `config_hash` `<…>` |
| Licencja danych | PTB-XL 1.0.3, CC BY 4.0 (cytowanie w §10) |

## 2. Przeznaczenie

- **Przeznaczenie:** prototyp badawczo-inżynierski do porównywania architektur, kalibracji i odporności modeli EKG; demonstracja dydaktyczna.
- **Poza zakresem:** jakiekolwiek zastosowanie kliniczne, diagnozowanie, triaż, monitorowanie pacjentów. Model **nie jest wyrobem medycznym**.
- **Użytkownicy:** studenci, prowadzący, osoby oceniające projekt.

## 3. Dane

- Trening: PTB-XL 1.0.3, foldy 1–8 (`<n>` rekordów po wykluczeniu rekordów bez superklasy).
- Walidacja i dopasowanie (progi, kalibracja, quality gate, abstention): fold 9 (`<n>` rekordów).
- Test (jednorazowo): fold 10 (`<n>` rekordów).
- Preprocessing: `<wersja>`; normalizacja per odprowadzenie ze statystyk train; filtracja: `<brak / opis>`.
- Znane ograniczenia danych: jeden ośrodek i producent aparatury (1989–1996), populacja niemiecka, słabe etykiety jakości, część etykiet z automatycznych raportów (foldy 1–8).

## 4. Wyniki — test (fold 10)

| Metryka | Wartość | 95% CI (bootstrap pacjentów) |
|---|---|---|
| macro AUROC | `<…>` | `<…>` |
| micro AUROC | `<…>` | — |
| macro F1 (progi z val) | `<…>` | `<…>` |
| macro AP | `<…>` | — |

Per klasa: `<tabela z metrics_test.json: AUROC, AP, F1, czułość, swoistość, próg, liczność>`.
Punkt odniesienia z literatury: macro AUROC ok. 0,93 (starsza rewizja zbioru, inny protokół) — `docs/evaluation.md` §9.

## 5. Kalibracja i niepewność

- Kalibrator: `<metoda>`; ECE macro przed/po: `<…>` / `<…>`; Brier macro przed/po: `<…>` / `<…>`.
- Abstention: `<metoda>`, τ = `<…>`, coverage na teście `<…>`, selective risk `<…>` (przy pełnym coverage: `<…>`).
- Quality gate: odsetek `WARN` / `REJECT` na teście `<…>` / `<…>`.

## 6. Odporność

`<Podsumowanie z robustness suite: spadek macro AUROC przy braku pojedynczego odprowadzenia (średni, najgorszy), przy SNR 10 dB, przy dryfcie 0,5 mV.>`

## 7. Analiza podgrup

| Podgrupa | n | macro AUROC | ECE |
|---|---|---|---|
| kobiety / mężczyźni | `<…>` | `<…>` | `<…>` |
| wiek < 40 / 40–60 / 60–75 / > 75 | `<…>` | `<…>` | `<…>` |

## 8. Wyjaśnialność

Atrybucja metodą `<Integrated Gradients>` (wrażliwość modelu na fragmenty sygnału). **Nie jest to wyjaśnienie przyczynowe ani kliniczne.**
Testy poprawności: kompletność `<…>`, test randomizacji wag `<wynik>`.

## 9. Ograniczenia i ryzyka

- Fold 9 użyty wielokrotnie (early stopping, progi, kalibracja, gate, abstention) — `docs/decisions.md` D-015.
- Brak walidacji zewnętrznej (inne ośrodki, aparatura, populacje) — możliwy spadek jakości przy przesunięciu domeny.
- Etykiety jakości sygnału są słabe; quality gate może przepuszczać nietypowe artefakty.
- `<Ryzyko shortcut learning przy metadanych — wynik E08.>`
- Wyniki MPS i CUDA nie są bitowo zgodne; wyniki finalne z `<urządzenie>`.

## 10. Reprodukcja i cytowanie

- Reprodukcja: README → sekcja „Reprodukcja wyników” (komendy, seedy, config, wersja danych).
- Wagner P., Strodthoff N., Bousseljot R., Samek W., Schaeffter T. *PTB-XL, a large publicly available electrocardiography dataset (version 1.0.3)*. PhysioNet, 2022. DOI: 10.13026/kfzx-aw45.
- Wagner P. i in. *PTB-XL, a large publicly available electrocardiography dataset*. Scientific Data 7, 154 (2020). DOI: 10.1038/s41597-020-0495-6.
- Goldberger A. i in. *PhysioBank, PhysioToolkit, and PhysioNet*. Circulation 101(23), 2000 (standardowe cytowanie PhysioNet — zweryfikuj aktualną formę na stronie PhysioNet).
