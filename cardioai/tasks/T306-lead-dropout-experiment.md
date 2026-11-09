---
id: T306
title: Eksperyment lead dropout i odporność kanałowa (E06, H3)
epic: quality
owner: B
reviewer: A
week: 7
size: S
level: Core
gate: G4
experiment: E06
depends_on: [T209, T305]
status: todo
---

# T306 — Eksperyment lead dropout i odporność kanałowa (E06, H3)

## Kontekst

- `docs/experiments.md` §2 (H3), §4 (E06 — reguła decyzyjna)
- `docs/reliability.md` §8
- `docs/config.md` §5 (przykład configu z `lead_dropout`)
- `docs/decisions.md`: D-027

## Cel

Odpowiedzieć na H3: czy `lead_dropout` w treningu zwiększa odporność na brak odprowadzeń bez istotnej straty na pełnym 12-lead.

## Zakres

- Configi `e06a_leaddrop_p0.yaml`, `e06b_leaddrop_p03.yaml`, `e06c_leaddrop_p05.yaml` (ResNet1D, strata wybrana w E04).
- Trening: seed 0 dla wszystkich wariantów, 3 seedy dla `p = 0` i najlepszego wariantu.
- Robustness suite (T305) dla każdego wariantu; tabela porównawcza i wykres Δ macro AUROC vs liczba brakujących odprowadzeń.
- Krzywe robustness (T305) także dla wariantów E05 (`e05a`–`e05d`), jako uzupełnienie wniosku E05 — raportowane, nie są warunkiem decyzji o głowie jakości (D-027).
- Wniosek H3 w `docs/experiments.md` (E06) i decyzja o domyślnej augmentacji w `configs/base.yaml` (wpis w `docs/decisions.md`, jeśli zmiana).

## Poza zakresem

- Nowe typy augmentacji.

## Pliki

- `configs/experiment/e06a_leaddrop_p0.yaml`, `e06b_leaddrop_p03.yaml`, `e06c_leaddrop_p05.yaml` — nowe
- `docs/experiments.md` — aktualizacja (E06)

## Kryteria akceptacji

- [ ] Wszystkie warianty zalogowane w MLflow z artefaktami robustness.
- [ ] Tabela E06 wygenerowana (`summarize_runs.py --write-docs E06`) + wykres w artefaktach.
- [ ] Wniosek H3 zgodny z regułą decyzyjną E06 (wartości liczbowe w tekście wniosku).

## Testy

- Brak nowych testów jednostkowych (zadanie eksperymentalne); configi walidowane przez `load_config` w teście parametryzowanym wszystkich plików `configs/experiment/*.yaml` (dodaj, jeśli nie istnieje).

## Weryfikacja

```bash
uv run python scripts/run_seeds.py --config configs/experiment/e06b_leaddrop_p03.yaml --seeds 0 1 2
uv run python scripts/robustness.py --checkpoint <best.pt> --split val
uv run python scripts/summarize_runs.py --experiment e06_lead_dropout --write-docs E06
```

## Wskazówki i pułapki

- Porównuj warianty na tym samym val i tych samych progach z ich własnego val — nie przenoś progów między modelami.
