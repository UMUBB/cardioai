---
id: T109
title: Augmentacje treningowe z rejestrem i walidacją parametrów
epic: data
owner: A
reviewer: B
week: 4
size: M
level: MVP
gate: G3
experiment: E06
depends_on: [T108]
status: todo
---

# T109 — Augmentacje treningowe

## Kontekst

- `docs/data_contract.md` §8 (kroki 5 i 7), §13 (brakujące odprowadzenia)
- `docs/config.md` §4 (`augmentations`), §7 (walidacja parametrów)
- Specyfikacja §4.5 (tabela augmentacji)

## Cel

Odtwarzalne augmentacje sygnału, włączane z configu i działające wyłącznie w treningu — w tym `lead_dropout`, kluczowy dla hipotezy H3.

## Zakres

| Nazwa | Przestrzeń | Parametry (domyślne) |
|---|---|---|
| `gaussian_noise` | mV | `p`, `snr_db: [20, 40]` |
| `baseline_wander` | mV | `p`, `amplitude_mv: [0.05, 0.3]`, `freq_hz: [0.05, 0.5]` |
| `amplitude_scale` | mV | `p`, `scale: [0.8, 1.2]` (wspólna dla odprowadzeń) |
| `time_shift` | mV | `p`, `max_shift_s: 0.5`, `mode: circular \| zero_pad` |
| `temporal_mask` | znorm. | `p`, `n_masks: [1, 2]`, `max_len_s: 0.5` |
| `lead_dropout` | znorm. | `p`, `min_leads: 1`, `max_leads: 2` — ustawia `lead_mask = False` |

- Rejestr z klasą parametrów Pydantic dla każdej augmentacji; `build_augmentations` dzieli je na fizyczne i znormalizowane.
- Podłączenie do domyślnej fabryki pipeline'u (`train=True`).

## Poza zakresem

- Korupcje z etykietami jakości (T302) — augmentacje nie zmieniają `SignalSample.quality`.

## Pliki

- `src/cardioai/data/augmentations.py` — nowy
- `src/cardioai/data/datamodule.py` — zmiana (augmentacje w fabryce train)
- `tests/unit/data/test_augmentations.py` — nowy

## Interfejs (wiążący)

```python
class Augmentation(Transform, Protocol):
    stage: Literal["physical", "normalized"]
AUGMENTATIONS: Mapping[str, type[Augmentation]]
def build_augmentations(specs: Sequence[AugmentationSpec]) -> tuple[list[Transform], list[Transform]]: ...
    # (fizyczne, znormalizowane); nieznana nazwa -> ConfigError z listą dostępnych
```

## Kryteria akceptacji

- [ ] Każda augmentacja stosowana z prawdopodobieństwem `p` (test statystyczny na 2000 losowaniach, tolerancja ±3 p.p.).
- [ ] Ten sam `rng` → identyczny wynik; kształt i float32 zachowane.
- [ ] `gaussian_noise` osiąga zadany SNR z dokładnością ±0,5 dB (moc liczona per odprowadzenie).
- [ ] `lead_dropout` wyłącza 1–2 odprowadzenia, ustawia `lead_mask=False`, a po pipeline odprowadzenia mają wartość 0.0.
- [ ] Pipeline z `train=False` nie zawiera żadnej augmentacji (test na `build_pipeline`).
- [ ] Parametry augmentacji trafiają do MLflow przez config (bez dodatkowego kodu).

## Testy

- `test_augmentations.py`: prawdopodobieństwo, determinizm, SNR, `lead_dropout` + maska, walidacja parametrów, nieznana nazwa.

## Weryfikacja

```bash
uv run pytest tests/unit/data/test_augmentations.py -q
```

## Wskazówki i pułapki

- `time_shift` w trybie `circular` przesuwa też granice uderzeń — w trybie `zero_pad` uzupełniaj zerami w mV (przed normalizacją).
- `temporal_mask` nie może zamaskować więcej niż ~10% sygnału łącznie — morfologia ma pozostać rozpoznawalna.
