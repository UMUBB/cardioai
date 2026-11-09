---
id: T202
title: Interfejs modeli, rejestr enkoderów, głowy i narzędzia
epic: training
owner: B
reviewer: A
week: 2
size: S
level: MVP
gate: G2
experiment: none
depends_on: [T002, T003]
status: todo
---

# T202 — Interfejs modeli, rejestr enkoderów, głowy i narzędzia

## Kontekst

- `docs/modeling.md` §1 (interfejs), §2 (rejestr), §4 (głowy), §9 (porównywalność)
- `docs/config.md` §7 (walidacja `model.params`)
- `AGENTS.md` §3 (models nie importuje data ani training)

## Cel

Wspólny kontrakt dla wszystkich architektur: każdy enkoder rejestruje się raz, a trening, ewaluacja, XAI i bundle
pracują z jednym typem `ECGModel` i jednym typem wyjścia `ModelOutput`.

## Zakres

- `ModelOutput`, bazowy `Encoder`, `ECGModel` (enkoder + głowy + opcjonalna gałąź metadanych i fuzja — tu tylko punkty zaczepienia, implementacja fuzji w T402).
- Rejestr enkoderów z klasą `Params` (Pydantic, `extra="forbid"`), `build_model`, `list_encoders`.
- `MultiTaskHeads` (diagnoza zawsze; jakość i aux opcjonalnie).
- `count_parameters`, `estimate_flops` (`torch.utils.flop_counter.FlopCounterMode`).
- Minimalny enkoder `debug_linear` (średnia po czasie → `Linear(12, 16)`) zarejestrowany na stałe — używany przez `e00_smoke.yaml`
  i testy integracyjne, zanim powstaną prawdziwe architektury.

## Poza zakresem

- Konkretne architektury (T205, T207, T401), fuzja metadanych (T402).

## Pliki

- `src/cardioai/models/__init__.py`, `base.py`, `registry.py`, `heads.py`, `utils.py`, `debug.py` — nowe
- `tests/unit/models/test_registry.py`, `test_heads.py`, `test_utils.py` — nowe

## Interfejs (wiążący)

```python
# docs/modeling.md §1 — ModelOutput, Encoder, ECGModel
def register_encoder(name: str, *, params: type[BaseModel]) -> Callable[[type[Encoder]], type[Encoder]]: ...
def build_model(model_cfg: ModelConfig, *, n_samples: int, n_leads: int = 12,
                aux_sizes: Mapping[str, int] | None = None, n_metadata: int = 0) -> ECGModel: ...
def list_encoders() -> list[str]: ...

class MultiTaskHeads(nn.Module):
    def __init__(self, in_dim: int, *, n_classes: int = 5, quality: bool = False,
                 aux: Mapping[str, int] | None = None, dropout: float = 0.0) -> None: ...
    def forward(self, z: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor | None, dict[str, torch.Tensor]]: ...

def count_parameters(model: nn.Module, trainable_only: bool = True) -> int: ...
def estimate_flops(model: nn.Module, input_shape: tuple[int, int, int]) -> int: ...
class UnknownModelError(KeyError): ...
```

## Kryteria akceptacji

- [ ] Rejestracja dwóch enkoderów o tej samej nazwie → błąd; nieznana nazwa → `UnknownModelError` z listą dostępnych.
- [ ] Błędny klucz w `model.params` → błąd walidacji z nazwą parametru, przed zbudowaniem sieci.
- [ ] `ECGModel` z enkoderem testowym zwraca `logits [B, 5]`, `quality_logits [B, 4]` (gdy włączone) i `aux_logits` zgodne z `aux_sizes`.
- [ ] `meta` przekazane do modelu bez gałęzi metadanych → jednorazowe ostrzeżenie, wynik bez zmian.
- [ ] `estimate_flops` > 0 dla enkodera konwolucyjnego; `count_parameters` zgodne z ręcznym policzeniem dla małej sieci.
- [ ] `lint-imports` potwierdza brak importów `cardioai.data` i `cardioai.training`.

## Testy

- `test_registry.py`: rejestracja, duplikaty, walidacja `Params`, `build_model` z enkoderem testowym.
- `test_heads.py`: kształty wyjść, wyłączanie głów, dropout.
- `test_utils.py`: liczenie parametrów i FLOPs.

## Weryfikacja

```bash
uv run pytest tests/unit/models -q
uv run lint-imports
```

## Wskazówki i pułapki

- `ModelOutput` jako `dataclass` nie przechodzi przez eksport ONNX/TorchScript — wrappery eksportowe zwracają krotki (T703).
- Rejestr wypełnia się przy imporcie modułów — `cardioai/models/__init__.py` importuje wszystkie moduły enkoderów.
