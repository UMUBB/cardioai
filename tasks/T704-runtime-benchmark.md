---
id: T704
title: Benchmark wydajności inferencji (E11)
epic: deploy
owner: A
reviewer: B
week: 13
size: S
level: Core
gate: G5
experiment: E11
depends_on: [T603, T610]
status: todo
---

# T704 — Benchmark wydajności inferencji (E11)

## Kontekst

- Specyfikacja §7.3 (metryki runtime: latency p50/p95, throughput, RAM/VRAM, rozmiar artefaktu)
- `docs/experiments.md` §4 (E11)
- `docs/environment.md` §1 (sprzęt)

## Cel

Liczby wydajności do raportu i karty modelu, zmierzone powtarzalnie na każdym urządzeniu zespołu.

## Zakres

- `scripts/benchmark_runtime.py --bundle PATH --device {cpu,cuda,mps} [--backend torch|onnx]`:
  rozgrzewka 20 przebiegów, 200 pomiarów batch=1 (p50, p95), przepustowość dla batch=32, szczytowa pamięć (RAM — `psutil`; VRAM — `torch.cuda.max_memory_allocated`),
  rozmiar bundla, czas `Predictor.predict` z XAI i bez.
- Wynik: CSV + tabela Markdown; log do MLflow (`exp_id=E11`); tabela w `docs/experiments.md` (E11).
- Pomiary na: laptopie A (CPU, CUDA), Macu (CPU, MPS).

## Poza zakresem

- Optymalizacje modelu (T703).

## Pliki

- `scripts/benchmark_runtime.py` — nowy
- `docs/experiments.md` — aktualizacja (E11)

## Kryteria akceptacji

- [ ] Tabela E11 z wynikami z co najmniej dwóch urządzeń i dwóch backendów (CPU + GPU/MPS).
- [ ] Pomiary powtarzalne: dwa uruchomienia różnią się w p50 o < 10% (w przeciwnym razie opis przyczyny).
- [ ] Wersje bibliotek i urządzenie zapisane obok wyników (`collect_env_info`).

## Testy

- Smoke na fixture z bundlem testowym (`--n-runs 5`) — kończy się bez błędu i zapisuje CSV.

## Weryfikacja

```bash
uv run python scripts/benchmark_runtime.py --bundle models/bundles/<wersja> --device cpu
```

## Wskazówki i pułapki

- Na CUDA mierz z `torch.cuda.synchronize()` przed odczytem czasu.
- Laptopy: zasilacz podłączony, tryb wysokiej wydajności, zamknięte inne programy — zapisz to w opisie wyników.
