---
id: T703
title: Eksport ONNX i kwantyzacja INT8 (opcjonalne, E11)
epic: deploy
owner: B
reviewer: C
week: 13
size: M
level: Extended
gate: none
experiment: E11
depends_on: [T601]
status: todo
---

# T703 — Eksport ONNX i kwantyzacja INT8 (opcjonalne, E11)

## Kontekst

- `docs/inference_api.md` §2 (`model.backend`, `model.onnx` w bundlu)
- `docs/experiments.md` §4 (E11 — reguła akceptacji kwantyzacji)
- Specyfikacja §9.4 (static quantization zalecana dla CNN)

## Cel

Sprawdzić, czy ResNet1D w ONNX Runtime (FP32 i INT8) daje tę samą jakość przy niższym opóźnieniu na CPU — i jeśli tak, udostępnić ten backend w bundlu.

## Zakres

- `scripts/export_onnx.py`: wrapper zwracający `(logits, quality_logits)`, eksport z dynamiczną osią batcha (opset ≥ 17), walidacja `onnx.checker`.
- Test parzystości PyTorch vs ONNX Runtime FP32 (max |Δ logitów| ≤ 1e-4).
- Statyczna kwantyzacja INT8 (format QDQ) z czytnikiem kalibracyjnym na 200 rekordach train; porównanie macro AUROC val i opóźnienia.
- Opcjonalny backend `onnx` w `Predictor` (`model.backend: "onnx"` w bundlu), gdy reguła E11 jest spełniona.

## Poza zakresem

- Kwantyzacja Transformera, eksport mobilny (ExecuTorch).

## Pliki

- `scripts/export_onnx.py` — nowy
- `src/cardioai/inference/onnx_backend.py` — nowy
- `src/cardioai/inference/predictor.py` — zmiana (wybór backendu `onnx`)
- `tests/unit/inference/test_onnx_parity.py` — nowy

## Kryteria akceptacji

- [ ] Parzystość FP32 na 20 rekordach fixture'a: max |Δ| ≤ 1e-4.
- [ ] Tabela E11: macro AUROC val (PyTorch FP32, ORT FP32, ORT INT8), opóźnienie p50/p95, rozmiar pliku.
- [ ] Decyzja według reguły E11 zapisana w `docs/experiments.md`.
- [ ] Bundle z `backend: "onnx"` ładuje się w `Predictor`; bez `onnxruntime` w środowisku — czytelny błąd.

## Testy

- `test_onnx_parity.py` (pomijany bez extra `onnx`): eksport małego modelu, parzystość, dynamiczny batch.

## Weryfikacja

```bash
uv run pytest tests/unit/inference/test_onnx_parity.py -q
uv run python scripts/export_onnx.py --bundle models/bundles/<wersja> --quantize int8
```

## Wskazówki i pułapki

- Eksport w trybie `eval()`; BatchNorm jest wtedy foldowalny i kwantyzacja działa lepiej.
- Kalibracja kwantyzacji wyłącznie na rekordach train — nie val (który służy do oceny).
