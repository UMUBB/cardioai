---
id: T802
title: Karta modelu, README i instrukcja reprodukcji
epic: final
owner: C
reviewer: A
week: 14
size: S
level: Core
gate: G6
experiment: none
depends_on: [T801]
status: todo
---

# T802 — Karta modelu, README i instrukcja reprodukcji

## Kontekst

- `docs/model_card.md` (szablon)
- `docs/data_contract.md` §1 (cytowanie i licencja)
- `docs/environment.md` §2, §5; `docs/mlops.md` §8
- `docs/decisions.md`: D-035 (karta modelu w tygodniu 14)
- Specyfikacja §13.2 (Definition of Done: README, model card, ograniczenia, reprodukcja)

## Cel

Ktoś spoza zespołu (prowadzący) uruchamia demo i odtwarza wyniki z README, a karta modelu uczciwie opisuje przeznaczenie, wyniki i ograniczenia.

## Zakres

- Wypełnienie `docs/model_card.md` danymi z `release/final_test_log.jsonl`, `metrics_test.json`, raportu niezawodności i robustness (liczby z plików, bez przepisywania „z pamięci”).
- README: opis i zastrzeżenie, architektura (link do `docs/architecture.md`), szybki start (demo przez `docker compose`), dane, reprodukcja wyników
  (komendy z seedami i configami finalnymi), struktura repo, zespół, cytowanie PTB-XL i licencja.
- Test reprodukcji: osoba, która nie pisała README, wykonuje je na świeżym klonie (inna maszyna) i zgłasza problemy.
- Model card dołączona do wydania (T702).

## Poza zakresem

- Raport końcowy przedmiotu (tekst) — korzysta z T803.

## Pliki

- `docs/model_card.md`, `README.md` — aktualizacja

## Kryteria akceptacji

- [ ] Wszystkie pola `<…>` w karcie modelu wypełnione; sekcja ograniczeń zawiera D-015 i brak walidacji zewnętrznej.
- [ ] Zastrzeżenie „nie jest wyrobem medycznym” w README, karcie i UI.
- [ ] Cytowanie PTB-XL i informacja o licencji CC BY 4.0 w README i karcie.
- [ ] Test reprodukcji na świeżym klonie zaliczony (notatka w PR: kto, na jakiej maszynie, ile trwało).

## Testy

- Brak testów automatycznych; weryfikacja przez test reprodukcji.

## Weryfikacja

```bash
git clone <repo> cardioai-fresh && cd cardioai-fresh
# kroki z README: instalacja, demo, reprodukcja jednego wyniku z tabeli
```

## Wskazówki i pułapki

- Liczby do karty kopiuj skryptem z plików JSON (np. mały helper w `scripts/make_report_assets.py`), żeby uniknąć literówek.
