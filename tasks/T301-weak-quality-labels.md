---
id: T301
title: Słabe etykiety jakości w Dataset i analiza ich wiarygodności
epic: quality
owner: A
reviewer: B
week: 5
size: S
level: Core
gate: G4
experiment: E05
depends_on: [T105, T110]
status: todo
---

# T301 — Słabe etykiety jakości w Dataset i analiza ich wiarygodności

## Kontekst

- `docs/data_contract.md` §8 (`y_quality`), §11 (reguły słabych etykiet)
- `docs/reliability.md` §2, §3
- `docs/decisions.md`: D-012

## Cel

Dataset dostarcza wektor `y_quality` (słabe etykiety PTB-XL połączone z etykietami korupcji), a zespół zna ograniczenia tych etykiet, zanim zacznie na nich trenować.

## Zakres

- `weak_quality_matrix(index)` z kolumn `q_*` indeksu (kolejność `QUALITY_LABELS`).
- `PTBXLDataset(return_quality=True)`: `y_quality = weak OR SignalSample.quality` (korupcje z pipeline'u, T302).
- Analiza wiarygodności: przegląd wizualny 20 oznaczonych i 20 nieoznaczonych rekordów **z train** (wykresy w `reports/quality/`), krótki opis ograniczeń w `docs/reliability.md` §3.
- Częstość etykiet per split i fold — przez istniejącą funkcję `cardioai.data.eda.quality_prevalence` (T110), bez duplikowania.

## Poza zakresem

- Parsowanie per odprowadzenie (poza MVP), model jakości (T303).

## Pliki

- `src/cardioai/data/quality_labels.py` — nowy
- `src/cardioai/data/dataset.py` — zmiana (`return_quality`)
- `scripts/review_quality_labels.py` — nowy
- `docs/reliability.md` — aktualizacja §3 (ograniczenia)
- `tests/unit/data/test_quality_labels.py` — nowy

## Interfejs (wiążący)

```python
def weak_quality_matrix(index: pd.DataFrame) -> np.ndarray: ...   # [N, 4] int8, kolejność QUALITY_LABELS
def merge_quality(weak: np.ndarray, synthetic: np.ndarray) -> np.ndarray: ...   # OR, int8
```

## Kryteria akceptacji

- [ ] Próbka z `return_quality=True` ma `y_quality` `FloatTensor [4]` zgodny z indeksem (fixture).
- [ ] Gdy pipeline dodał korupcję, `y_quality` zawiera OR słabych i syntetycznych etykiet (test z transformem ustawiającym `quality`).
- [ ] Przegląd 40 rekordów wykonany; wnioski (np. odsetek oczywistych błędów etykiet) w `docs/reliability.md` §3.
- [ ] Brak wykresów rekordów z val i test.

## Testy

- `test_quality_labels.py`: macierz z fixture'a, scalanie OR, integracja z `PTBXLDataset`.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_quality_labels.py -q
uv run python scripts/review_quality_labels.py --n 20 --out reports/quality
```

## Wskazówki i pułapki

- Brak flagi nie znaczy „czysty sygnał” — nie używaj rekordów bez flag jako twardych negatywów w raportach bez zastrzeżenia.
