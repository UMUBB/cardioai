---
id: T503
title: XAI — Integrated Gradients, saliency i agregacje (E11)
epic: reliability
owner: C
reviewer: A
week: 8
size: M
level: Core
gate: G5
experiment: E11
depends_on: [T108, T207]
status: todo
---

# T503 — XAI: Integrated Gradients, saliency i agregacje (E11)

## Kontekst

- `docs/reliability.md` §7 (metody, wiążące API, agregacje, testy poprawności, budżet czasu, komunikat)
- `docs/inference_api.md` §7 (pole `explanation`)
- `AGENTS.md` §2 pkt 11 (XAI jako atrybucja, nie wyjaśnienie)

## Cel

Atrybucja predykcji w czasie i po odprowadzeniach, gotowa do wyświetlenia w UI i opisana uczciwie jako wrażliwość modelu.

## Zakres

- `explain` dla metod `integrated_gradients` (domyślnie Captum; dopuszczalna własna implementacja), `saliency`, `gradient_x_input`.
- Wybór klasy docelowej (§7), agregacje `lead_importance` i `time_attribution`, `convergence_delta`, przygotowanie do API (uśrednienie do ≤ 100 Hz, skala `[-1, 1]`).
- Testy poprawności: kompletność IG; jednorazowy test randomizacji wag w skrypcie raportowym.
- `scripts/explain_record.py --checkpoint PATH --ecg-id ID --split val` → wykres 12 odprowadzeń z nałożoną atrybucją (PNG) do raportu.
- Pomiar czasu na CPU (100 Hz, ResNet1D) w PR.

## Poza zakresem

- Integracja z `Predictor` (T610) i UI (T609).

## Pliki

- `src/cardioai/reliability/xai.py` — nowy
- `scripts/explain_record.py` — nowy
- `tests/unit/reliability/test_xai.py` — nowy

## Interfejs (wiążący)

```python
# docs/reliability.md §7: Attribution, explain(...)
def select_target_class(probs: np.ndarray, thresholds: np.ndarray, requested: str | None = None) -> int: ...
def to_api_payload(attr: Attribution, *, fs: int, max_fs: int = 100) -> dict[str, Any]: ...
    # {"method", "target_class", "lead_importance": {lead: float}, "attribution_fs", "attribution": [[...]], "note"}
XAI_NOTE: Final[str]     # stały komunikat z docs/reliability.md §7
```

## Kryteria akceptacji

- [ ] Kompletność IG: `|Σ A − (f(x) − f(x₀))| / |f(x) − f(x₀)| < 0,05` przy `n_steps = 50` na modelu testowym.
- [ ] `lead_importance` sumuje się do 1; `time_attribution` w [0, 1]; kształty zgodne z §7.
- [ ] Wybór klasy: wskazana → ta; inaczej pozytywna o najwyższym prawdopodobieństwie; inaczej najwyższe prawdopodobieństwo.
- [ ] Payload API ma kształt `[12][≤ 1000]` i `attribution_fs ≤ 100`.
- [ ] Czas IG na CPU dla ResNet1D przy 100 Hz ≤ 1,5 s na rekord (pomiar w PR) albo plan redukcji (`n_steps`, `internal_batch_size`).
- [ ] Wykresy z `explain_record.py` wyłącznie dla rekordów val.

## Testy

- `test_xai.py`: kompletność na małej sieci, sumy i zakresy agregacji, wybór klasy, payload, działanie na CPU bez Captum (jeśli własna implementacja) lub z Captum.

## Weryfikacja

```bash
uv run pytest tests/unit/reliability/test_xai.py -q
uv run python scripts/explain_record.py --checkpoint <best.pt> --ecg-id <ID z val> --split val
```

## Wskazówki i pułapki

- Model w `eval()`; gradienty względem wejścia wymagają `x.requires_grad_(True)` — nie zostawiaj włączonych gradientów parametrów (`torch.no_grad` dla wag nie zadziała przy IG, użyj `requires_grad_(False)` na parametrach).
- Baseline „zera” jest zdefiniowany w przestrzeni znormalizowanej — to „średni sygnał”, nie płaska linia 0 mV.
