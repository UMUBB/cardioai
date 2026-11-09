---
id: T110
title: EDA i raport danych (E00)
epic: data
owner: A
reviewer: B
week: 3
size: M
level: MVP
gate: G1
experiment: E00
depends_on: [T103, T105, T106]
status: todo
---

# T110 — EDA i raport danych (E00)

## Kontekst

- `docs/data_contract.md` §3, §11, §12, §15 (tabela wyników EDA do uzupełnienia)
- `docs/experiments.md` §4 (E00)
- `docs/inference_api.md` §5 (progi amplitud do doprecyzowania)
- `docs/decisions.md`: D-035 (EDA w tygodniu 3)

## Cel

Potwierdzić liczebności, split i jakość danych oraz dostarczyć liczby, od których zależą dalsze decyzje
(rekordy bez etykiet, braki metadanych, częstość artefaktów, rozkład amplitud).

## Zakres

- Funkcje analityczne (czyste, zwracające ramki danych) i skrypt renderujący wykresy oraz `summary.md` + `summary.json`.
- Zawartość: liczności klas per split, kardynalność etykiet, macierz współwystępowania, rekordy bez superklasy per split,
  rozkład wieku i płci (weryfikacja kodowania płci), braki `height`/`weight`, częstość flag jakości per split i fold,
  `validated_by_human` per fold, percentyle 99 i 99,9 `|x|` per odprowadzenie (train), przykładowe 12-odprowadzeniowe wykresy po 2 rekordy na klasę (train).
- Uzupełnienie tabeli w `docs/data_contract.md` §15.

## Poza zakresem

- Oglądanie sygnałów z foldu 10 (test) — dla testu tylko liczności etykiet.
- Wnioski modelowe.

## Pliki

- `src/cardioai/data/eda.py` — nowy
- `scripts/eda.py` — nowy (wynik w `reports/eda/`, poza gitem)
- `docs/data_contract.md` — aktualizacja §15
- `tests/unit/data/test_eda.py` — nowy (smoke na fixture)

## Interfejs (wiążący)

```python
def class_counts(index: pd.DataFrame) -> pd.DataFrame: ...                 # split × klasa (+ n, n_unlabeled)
def cooccurrence(index: pd.DataFrame, split: str = "train") -> pd.DataFrame: ...
def missingness(index: pd.DataFrame) -> pd.DataFrame: ...
def quality_prevalence(index: pd.DataFrame) -> pd.DataFrame: ...
def amplitude_percentiles(dataset: PTBXLDataset, q: Sequence[float] = (99.0, 99.9)) -> pd.DataFrame: ...
```

## Kryteria akceptacji

- [ ] `scripts/eda.py` działa na prawdziwych danych (cache 100 Hz) w < 10 min i na fixture w < 30 s.
- [ ] Tabela w `docs/data_contract.md` §15 uzupełniona; liczby kontrolne zgodne albo różnice wyjaśnione.
- [ ] Kodowanie płci potwierdzone (udział `sex == 0` vs 52% mężczyzn z opisu zbioru) i zapisane w §15.
- [ ] Proponowane progi `AMPLITUDE_HIGH` i `UNITS_SUSPECT` wynikające z percentyli zapisane w PR (decyzję o progach podejmuje A w T602 po konsultacji z C).
- [ ] Brak wykresów sygnałów z foldu 10.

## Testy

- `test_eda.py`: funkcje analityczne na `mini_ptbxl_root` zgadzają się z `MINI_EXPECTED`; skrypt tworzy pliki wynikowe w `tmp_path`.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_eda.py -q
uv run python scripts/eda.py --config configs/base.yaml --out reports/eda
```

## Wskazówki i pułapki

- Funkcja `quality_prevalence` z tego zadania jest używana ponownie w T301 — nie duplikuj jej tam.
- Wykresy generuj z `matplotlib` bez interaktywnego backendu (`Agg`), żeby skrypt działał w CI i na serwerze.
