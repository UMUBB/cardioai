---
id: T404
title: Porównanie 100 Hz vs 500 Hz — jakość a koszt (E10, H5)
epic: extended
owner: B
reviewer: C
week: 11
size: M
level: Extended
gate: none
experiment: E10
depends_on: [T106, T209]
status: todo
---

# T404 — Porównanie 100 Hz vs 500 Hz: jakość a koszt (E10, H5)

## Kontekst

- `docs/modeling.md` §3.2 (wariant 500 Hz o zbliżonym koszcie), §9
- `docs/data_contract.md` §9 (statystyki per `fs`), §10 (cache 500 Hz, memmap)
- `docs/experiments.md` §2 (H5), §4 (E10)
- `docs/decisions.md`: D-009

## Cel

Odpowiedzieć na H5 liczbami: ile kosztuje 500 Hz (czas, pamięć, opóźnienie) i ile daje (macro AUROC, szczególnie STTC).

## Zakres

- Cache 500 Hz i statystyki normalizacji 500 Hz (istniejące skrypty).
- Configi: `e10a_resnet_100hz.yaml` (referencja z E03), `e10b_resnet_500hz.yaml` (ta sama architektura), `e10c_resnet_500hz_stride10.yaml` (`stem_kernel=75`, `stem_stride=10`).
- 3 seedy dla każdego wariantu (o ile czas pozwoli; minimum 1 seed + uzasadnienie).
- Pomiar: czas epoki, szczytowa pamięć GPU (metryka `peak_memory_mb` logowana przez `Trainer` — T204), opóźnienie inferencji CPU p50 dla batcha 1.
- Tabela E10 i wniosek H5.

## Poza zakresem

- Transformer przy 500 Hz.

## Pliki

- `configs/experiment/e10a_resnet_100hz.yaml`, `e10b_resnet_500hz.yaml`, `e10c_resnet_500hz_stride10.yaml` — nowe
- `docs/experiments.md` — aktualizacja (E10)

## Kryteria akceptacji

- [ ] Trening 500 Hz na laptopie z RTX 2060 bez OOM (AMP, ewentualnie `grad_accum_steps`); RAM < 16 GB dzięki memmap.
- [ ] Tabela E10: macro AUROC (średnia ± std), AUROC STTC, czas epoki, pamięć, opóźnienie, MFLOPs.
- [ ] Wniosek H5 według reguły E10.

## Testy

- Brak nowych testów jednostkowych poza walidacją configów (test parametryzowany wszystkich `configs/experiment/*.yaml`).

## Weryfikacja

```bash
uv run python scripts/build_cache.py --sampling-rate 500
uv run python scripts/compute_norm_stats.py --config configs/experiment/e10b_resnet_500hz.yaml
uv run python scripts/run_seeds.py --config configs/experiment/e10b_resnet_500hz.yaml --seeds 0 1 2
```

## Wskazówki i pułapki

- Przy 500 Hz `num_workers` ogranicz do 2 na laptopach 16 GB; memmap otwierany leniwie (T106).
- Porównuj warianty przy tym samym budżecie epok i tej samej stracie.
