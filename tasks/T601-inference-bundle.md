---
id: T601
title: Format bundla inferencyjnego i eksport z checkpointu
epic: product
owner: B
reviewer: C
week: 6
size: M
level: Core
gate: G5
experiment: none
depends_on: [T108, T206]
status: todo
---

# T601 — Format bundla inferencyjnego i eksport z checkpointu

## Kontekst

- `docs/inference_api.md` §1, §2 (format, wersjonowanie, sekcje opcjonalne)
- `docs/modeling.md` §6 (checkpoint)
- `docs/decisions.md`: D-013, D-014, D-032
- `docs/mlops.md` §4, §8 (rejestr, wydania)

## Cel

Jeden samowystarczalny artefakt z modelem i wszystkimi parametrami potrzebnymi do inferencji — jedyny łącznik między treningiem a serwowaniem.

## Zakres

- `BundleSpec` (Pydantic) odwzorowujący `bundle.json` z §2 (w tym `model.aux_sizes` i `model.n_metadata`); walidacja `bundle_format`, wersji semver, spójności (`classes`, `leads`, `n_samples`, `n_metadata` zgodne z liczbą cech metadanych).
- `save_bundle` i `load_bundle_spec`; zapis `weights.pt` (sam `state_dict`) i wygenerowanego `README.md` bundla.
- `scripts/export_model.py --checkpoint PATH --version X.Y.Z [--calibration] [--thresholds] [--quality-gate] [--abstention] [--out DIR]`;
  sekcje niepodane → postać wyłączona (`identity`, `enabled: false`, progi 0,5 z ostrzeżeniem).
- Opcjonalnie `--log-mlflow`: bundle jako artefakt runu (`bundle/`).

## Poza zakresem

- Ładowanie i predykcja (`Predictor`, T603), rejestracja pyfunc i aliasy (T702), ONNX (T703).

## Pliki

- `src/cardioai/inference/__init__.py`, `src/cardioai/inference/bundle.py` — nowe
- `scripts/export_model.py` — nowy
- `tests/unit/inference/test_bundle.py` — nowy

## Interfejs (wiążący)

```python
BUNDLE_FORMAT: Final = 1
class BundleSpec(BaseModel): ...                         # pola jak bundle.json w docs/inference_api.md §2
def save_bundle(out_dir: Path, *, state_dict: Mapping[str, torch.Tensor], spec: BundleSpec) -> Path: ...
def load_bundle_spec(bundle_dir: Path) -> BundleSpec: ...  # BundleFormatError przy innym bundle_format
def spec_from_checkpoint(checkpoint: Mapping[str, Any], *, model_version: str,
                         calibration: Mapping[str, Any] | None = None, thresholds: Mapping[str, Any] | None = None,
                         quality_gate: Mapping[str, Any] | None = None,
                         abstention: Mapping[str, Any] | None = None) -> BundleSpec: ...
class BundleFormatError(ValueError): ...
```

## Kryteria akceptacji

- [ ] `bundle.json` przechodzi walidację `BundleSpec` i zawiera wszystkie sekcje z §2 (wyłączone jawnie, gdy brak danych); sekcja `model` ma `aux_sizes` i `n_metadata` (wyznaczone z checkpointu i configu treningu), wystarczające do wywołania `build_model`.
- [ ] `model_version` w formacie `{model}-MAJOR.MINOR.PATCH`; błędny format → błąd.
- [ ] Bundle nie zawiera plików pickle poza `weights.pt` ładowanym `weights_only=True`.
- [ ] `provenance` zawiera `mlflow_run_id`, `git_sha`, `config_hash`, `dataset_version`, foldy, `test_evaluated: false`, metryki val.
- [ ] Round-trip: `save_bundle` → `load_bundle_spec` → identyczny `BundleSpec`.

## Testy

- `test_bundle.py`: walidacja specyfikacji, wersje, sekcje wyłączone, round-trip, odrzucenie `bundle_format = 2`.

## Weryfikacja

```bash
uv run pytest tests/unit/inference/test_bundle.py -q
uv run python scripts/export_model.py --checkpoint <best.pt> --version 0.1.0 --out models/bundles/resnet1d-0.1.0
```

## Wskazówki i pułapki

- `inference` nie może importować `training` — odczyt checkpointu do eksportu robi skrypt (który może importować wszystko) i przekazuje słownik do `spec_from_checkpoint`.
- Statystyki normalizacji kopiuj do `bundle.json` (`preprocessing.norm_stats`), nie jako ścieżkę do pliku.
