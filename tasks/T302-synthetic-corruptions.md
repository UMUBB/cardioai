---
id: T302
title: Biblioteka korupcji syntetycznych z etykietami jakości
epic: quality
owner: A
reviewer: B
week: 5
size: M
level: Core
gate: G4
experiment: E05
depends_on: [T109]
status: todo
---

# T302 — Biblioteka korupcji syntetycznych z etykietami jakości

## Kontekst

- `docs/reliability.md` §2 (katalog korupcji, wiążące API), §8 (siatki robustness)
- `docs/data_contract.md` §8 (krok 3), §13 (`electrode_flat` vs brakujące odprowadzenie)
- `docs/decisions.md`: D-010, D-012, D-023

## Cel

Kontrolowane artefakty o znanej etykiecie — do treningu modelu jakości (T303), doboru quality gate (T304) i testów odporności (T305).

## Zakres

- Korupcje z tabeli `docs/reliability.md` §2: `gaussian_noise`, `powerline`, `burst_noise`, `baseline_drift`, `electrode_flat`, `electrode_pop`, `saturation`.
- `apply_corruption` (parametry jawne) i `CorruptionSampler` (trening: z prawdopodobieństwem `p` 1–2 korupcje z zakresów).
- `CorruptionTransform` — Transform kroku 3 pipeline'u, ustawiający `SignalSample.quality`; przekazywany do `build_pipeline` jako `corruption` (trening, `train=True`)
  albo jako `robustness_corruption` (ewaluacja, stosowany tylko przy `train=False`; D-023).
- `corrupt_for_eval` — deterministyczna korupcja do ewaluacji (RNG z `[seed, ecg_id, id korupcji]`).
- Podłączenie `quality.synthetic` z configu do fabryki pipeline'u train.

## Poza zakresem

- Brakujące odprowadzenie jako maska po normalizacji — to `lead_dropout` (T109) i test robustness (T305).

## Pliki

- `src/cardioai/data/corruptions.py` — nowy
- `src/cardioai/data/datamodule.py` — zmiana (korupcje w fabryce train)
- `tests/unit/data/test_corruptions.py` — nowy

## Interfejs (wiążący)

```python
# docs/reliability.md §2: CorruptionResult, apply_corruption, CorruptionSampler
CORRUPTIONS: Mapping[str, Callable[..., CorruptionResult]]
class CorruptionTransform:                      # Transform
    def __init__(self, sampler: CorruptionSampler) -> None: ...
def corrupt_for_eval(x: np.ndarray, fs: int, *, ecg_id: int, name: str, severity: float | int,
                     seed: int = 0) -> CorruptionResult: ...
```

## Kryteria akceptacji

- [ ] Każda korupcja ustawia etykietę jakości zgodnie z tabelą (`saturation` — brak etykiety).
- [ ] `gaussian_noise` osiąga zadany SNR ±0,5 dB per odprowadzenie.
- [ ] `powerline` przy `fs ≤ 100` → `ValueError` z wyjaśnieniem (Nyquist); `CorruptionSampler` pomija ją przy 100 Hz.
- [ ] `electrode_flat` nie zmienia `lead_mask` (kanał istnieje, jest płaski).
- [ ] Determinizm: ten sam RNG → identyczny wynik; `corrupt_for_eval` niezależny od kolejności wywołań.
- [ ] Kształt `[12, T]` i float32 zachowane; brak NaN.
- [ ] Korupcja przekazana jako `corruption` nie jest aplikowana w pipeline'ie `train=False`; przekazana jako `robustness_corruption` jest aplikowana tylko tam (test).

## Testy

- `test_corruptions.py`: etykiety, SNR, zakresy parametrów, `powerline` przy 100/500 Hz, determinizm, sampler (rozkład liczby korupcji).

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_corruptions.py -q
```

## Wskazówki i pułapki

- Moc sygnału do SNR licz z wariancji odprowadzenia po odjęciu średniej; dla odprowadzenia płaskiego użyj dolnej granicy, żeby nie dzielić przez 0.
- Zakresy parametrów trzymaj w klasach parametrów (Pydantic), nie w kodzie funkcji — robustness nadpisuje je siatką.
