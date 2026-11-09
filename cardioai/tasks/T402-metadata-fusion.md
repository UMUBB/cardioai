---
id: T402
title: Fuzja metadanych i analiza podgrup (E08, H2)
epic: extended
owner: B
reviewer: A
week: 9
size: M
level: Extended
gate: none
experiment: E08
depends_on: [T209]
status: todo
---

# T402 — Fuzja metadanych i analiza podgrup (E08, H2)

## Kontekst

- `docs/data_contract.md` §12 (kodowanie metadanych), §14 (braki wzrostu i wagi)
- `docs/modeling.md` §4 (`MetadataBranch`, `ConcatFusion`)
- `docs/decisions.md`: D-032
- `docs/experiments.md` §2 (H2), §4 (E08 — warianty i reguła)

## Cel

Zmierzyć wartość danych pozasygnałowych (wiek, płeć, wzrost, waga) i ryzyko uczenia się na skrótach — wynik „tylko EKG” zawsze pozostaje w tabeli głównej.

## Zakres

- `MetadataEncoder` (`FieldProvider`): dopasowanie standaryzacji na train, wartości + maski braków, zapis/odczyt JSON (`split: "train"`);
  domyślne cechy `["age", "age_90plus", "sex", "height", "weight"]` (`age_90plus` jako osobna cecha; D-032), a `n_metadata` (liczba cech `M`) trafia do `build_model`, checkpointu i bundla.
- `MetadataBranch` i `ConcatFusion` w `cardioai.models.fusion`; obsługa w `build_model` (`n_metadata`), w checkpoincie i w bundlu (`metadata_encoder`).
- Configi: `e08a_ecg_only.yaml`, `e08b_ecg_meta.yaml`, `e08c_meta_only.yaml` (MLP na metadanych — miara siły skrótu).
- Analiza podgrup na val: płeć, wiek (< 40, 40–60, 60–75, > 75) — macro AUROC i ECE per podgrupa; korzysta z `subgroup_metrics` z T206 (`cardioai.evaluation.subgroups`), tu powstaje tylko `scripts/subgroup_analysis.py`.
- Wniosek H2 i decyzja include/exclude.

## Poza zakresem

- Inne metadane (`device`, `site`) jako cechy — tylko w analizie podgrup, jeśli czas pozwoli.

## Pliki

- `src/cardioai/data/metadata.py` — nowy
- `src/cardioai/models/fusion.py` — nowy; `src/cardioai/models/registry.py` — zmiana
- `src/cardioai/training/trainer.py` — zmiana (przekazanie `meta` i `meta_mask` do modelu; jeśli T204 przewiduje do tego punkt rozszerzeń — użyj go)
- `src/cardioai/training/predict.py` — zmiana (`meta` i `meta_mask` w `predict_loader`)
- `src/cardioai/inference/bundle.py` — zmiana (sekcje `metadata` i `metadata_encoder` w `BundleSpec`)
- `src/cardioai/inference/predictor.py` — zmiana (metadane w `Predictor.predict`)
- `scripts/subgroup_analysis.py` — nowy
- `configs/experiment/e08a_ecg_only.yaml`, `e08b_ecg_meta.yaml`, `e08c_meta_only.yaml` — nowe
- `tests/unit/data/test_metadata.py`, `tests/unit/models/test_fusion.py` — nowe

## Interfejs (wiążący)

```python
class MetadataEncoder:                        # FieldProvider -> {"meta": [M], "meta_mask": [M]}
    def __init__(self, features: Sequence[str]) -> None: ...
    def fit(self, train_index: pd.DataFrame) -> "MetadataEncoder": ...   # ValueError, gdy wiersze spoza train
    def __call__(self, row: Mapping[str, Any]) -> dict[str, torch.Tensor]: ...
    def to_dict(self) -> dict[str, Any]: ...
    @classmethod
    def from_dict(cls, d: Mapping[str, Any]) -> "MetadataEncoder": ...

class MetadataBranch(nn.Module): ...          # Linear(2M, hidden) -> GELU -> Linear(hidden, hidden)
class ConcatFusion(nn.Module): ...            # LayerNorm(concat)

# subgroup_metrics(pred, groups, *, min_size=50) — zdefiniowane w T206 (cardioai.evaluation.subgroups)
```

## Kryteria akceptacji

- [ ] Statystyki metadanych tylko z train; braki kodowane maską (test: NaN → wartość 0, maska 0).
- [ ] Model z metadanymi zapisuje i odtwarza encoder z checkpointu; bundle zawiera `metadata_encoder`.
- [ ] Trzy warianty E08 (3 seedy dla `ecg_only` i `ecg_meta`) w MLflow; tabela E08 wygenerowana.
- [ ] Tabela podgrup (n, macro AUROC, ECE) dla wariantów `ecg_only` i `ecg_meta`; podgrupy < 50 rekordów oznaczone.
- [ ] Wniosek H2 i decyzja według reguły E08 z liczbami.

## Testy

- `test_metadata.py`: dopasowanie na train, maski, wiek 90+ (`age = 90` i osobna cecha `age_90plus = 1`), `M == len(features)`, round-trip JSON.
- `test_fusion.py`: kształty z metadanymi i bez, gradient przez gałąź metadanych.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_metadata.py tests/unit/models/test_fusion.py -q
uv run python scripts/run_seeds.py --config configs/experiment/e08b_ecg_meta.yaml --seeds 0 1 2
uv run python scripts/subgroup_analysis.py --predictions <predictions_val.parquet>
```

## Wskazówki i pułapki

- Wariant `meta_only` używa trywialnego enkodera sygnału (np. `debug_linear` z wyzerowanym wejściem) albo osobnego MLP — opisz wybór w PR.
- Wzrost i waga są w większości puste — model może nauczyć się „brak = coś”; maska jest jawna, ale sprawdź ten efekt w analizie podgrup.
