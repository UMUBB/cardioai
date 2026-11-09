# Instrukcje dla GitHub Copilot — CardioAI

Pełne zasady projektu są w pliku `AGENTS.md` w katalogu głównym repozytorium. Przeczytaj go przed każdym zadaniem.
Zadania do realizacji są w `tasks/T###-*.md`, kontrakty techniczne w `docs/`.

Najważniejsze reguły (skrót z `AGENTS.md` §2):

1. Split tylko z `strat_fold`: train = 1–8, val = 9, test = 10. Fold 10 jest zablokowany: sygnał i predykcje tylko przez `cardioai.data.test_lock` (odblokowanie tylko w T801); liczności etykiet z indeksu są dozwolone.
2. Statystyki (normalizacja, `pos_weight`) tylko z train; progi i kalibracja tylko z val.
3. Urządzenie z `cardioai.utils.device.get_device()`; zakaz `.cuda()` i `torch.float64`.
4. Klasy, odprowadzenia i foldy tylko z `cardioai.constants`.
5. Jedna implementacja preprocessingu (`cardioai.data.preprocessing`) w treningu i inferencji.
6. Kod, docstringi i commity po angielsku; dokumentacja i UI po polsku.
7. Zmiana kontraktu z `docs/` wymaga wpisu w `docs/decisions.md` — w razie wątpliwości zapytaj.
