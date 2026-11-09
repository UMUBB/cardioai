---
id: T803
title: Artefakty raportu końcowego — tabele i wykresy
epic: final
owner: A
reviewer: C
week: 14
size: M
level: Core
gate: G6
experiment: none
depends_on: [T801]
status: todo
---

# T803 — Artefakty raportu końcowego: tabele i wykresy

## Kontekst

- `docs/experiments.md` §3–§5 (eksperymenty i tabela zbiorcza)
- `docs/evaluation.md` §6 (format tabel)
- `docs/mlops.md` §3 (artefakty runów)

## Cel

Wszystkie tabele i wykresy do raportu i prezentacji generowane jednym skryptem z MLflow i plików wydania — spójne, w jednym stylu, odtwarzalne.

## Zakres

- `scripts/make_report_assets.py` → `reports/final/` (commitowany, tylko małe PNG/SVG/MD):
  tabela zbiorcza (E01–E10), tabele per klasa (val i test), krzywe ROC/PR per klasa (test), reliability diagrams przed/po, krzywe risk–coverage,
  krzywe degradacji i mapa Δ per odprowadzenie, przykłady XAI (rekordy val), tabela wydajności (E11), wybrane wykresy EDA.
- Jednolity styl wykresów (jeden moduł stylu), podpisy po polsku, rozdzielczość do druku.
- Lista „figura → źródło danych (run_id/plik)” w `reports/final/SOURCES.md`.

## Poza zakresem

- Pisanie tekstu raportu i slajdów.

## Pliki

- `scripts/make_report_assets.py` — nowy
- `src/cardioai/evaluation/plots.py` — nowy (wspólny styl i funkcje wykresów)
- `reports/final/` — nowy (wygenerowane pliki + `SOURCES.md`)

## Kryteria akceptacji

- [ ] Jedno polecenie generuje komplet; ponowne uruchomienie daje identyczne pliki (bez znaczników czasu w treści).
- [ ] Każda figura ma wpis w `SOURCES.md` z run_id lub ścieżką pliku źródłowego.
- [ ] Wykresy XAI tylko dla rekordów val; wyniki testu tylko z `stage=final`.
- [ ] Łączny rozmiar `reports/final/` < 10 MB.

## Testy

- Smoke na sztucznych danych (`tmp_path`): skrypt tworzy oczekiwane pliki.

## Weryfikacja

```bash
uv run python scripts/make_report_assets.py --out reports/final
```

## Wskazówki i pułapki

- `matplotlib` z backendem `Agg`; ustaw stałe ziarno tam, gdzie wykres losuje (np. przykłady rekordów).
