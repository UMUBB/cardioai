# Poprawki dokumentacji — rejestr zmian (audyt)

Data: 2026-11-06. Zakres i upoważnienie: tabela „Decyzje zespołu” (D1–D18) z polecenia redakcyjnego.
Uwaga: w katalogu nie było `reports/docs-audit/REPORT.md` ani repozytorium git — zmiany wykonano wg opisu ustaleń z polecenia, bez gałęzi i commitów.

## Nowe wpisy w `docs/decisions.md`

| Wpis | Status | Dotyczy (decyzja) | Ustalenia |
|---|---|---|---|
| D-023 | przyjęta | D1 — `robustness_corruption` w `build_pipeline` | F-001 |
| D-024 | przyjęta | D2 — importy bezpośrednie (import-linter) | F-002 |
| D-025 | przyjęta | D3 + D4 — pierwszeństwo configu, skład `config_hash` | F-003, F-020 |
| D-026 | przyjęta | D5 — `CARDIOAI_PREDICTOR` `auto`/`real`/`mock` | F-004 |
| D-027 | proponowana | D7 — reguła E05 | F-007 |
| D-028 | przyjęta | D8 — demo `int16` w µV | F-008 |
| D-029 | przyjęta | D9 — nazwy metryk MLflow | F-009, F-013 |
| D-030 | proponowana | D11 — Transformer a „3 rodziny modeli” | F-010 |
| D-031 | przyjęta | D10 — jeden eksperyment MLflow na Exx | F-021 |
| D-032 | proponowana | D15 — `aux_sizes`, `n_metadata`, `age_90plus` w bundlu | F-030 |
| D-033 | przyjęta | D16 — extra `tracking` | F-032 |
| D-034 | przyjęta | D17 — `models/bundles/current` jako katalog | F-033 |
| D-035 | przyjęta | D18 — drobne odstępstwa od specyfikacji | F-028, F-038 |

Uzupełnione zdaniem „Uzupełnione przez D-0xx.”: D-005 (D-033), D-008 (D-024), D-010 (D-023), D-017 (D-028), D-022 (D-026).
Bez wpisu (zgodnie z tabelą): D6 (F-005), D12 (F-011), D13 (F-029), D14 (F-012, F-015).

## Zmienione pliki wg ustaleń

- **F-001:** `docs/data_contract.md` §8 (przypis), `tasks/T108`, `T302`, `T303`, `T305`.
- **F-002:** `AGENTS.md` §3, `docs/architecture.md` §4, `tasks/T001`.
- **F-003, F-020:** `docs/config.md` §1, §3, §4, §6, `docs/modeling.md` §8, `docs/environment.md` §4, `tasks/T002`, `T003`, `T204`.
- **F-004:** `docs/inference_api.md` §8–§9, `docs/environment.md` §4, `docs/mlops.md` §7, `tasks/T604`, `T605`, `T701`.
- **F-005:** `tasks/T107`, `T108`, `T204`; `docs/data_contract.md` §9 sprawdzony (zgodny).
- **F-006, F-016:** `depends_on` w T110, T207, T305, T704; `tasks/T609` (kryterium usunięte), `T402`, `T703` (Pliki).
- **F-007:** `docs/experiments.md` (E05), `tasks/T303`, `T306`.
- **F-008:** `docs/inference_api.md` §9, `tasks/T604`, `T605`.
- **F-009, F-013:** `docs/mlops.md` §3, `docs/evaluation.md` §3 i §5, `tasks/T201`, `T502`, `T504` (`docs/reliability.md` §6 nie wymienia nazw metryk MLflow — bez zmian).
- **F-010:** `docs/decisions.md` (D-030), `tasks/T401` (odsyłacz).
- **F-011:** `tasks/T206` (przejęcie `subgroup_metrics`), `tasks/T402`.
- **F-012, F-015:** front matter T005 (B/C) i T704 (A/B), `docs/experiments.md` §3 (E01 → C, E11 → C/B/A), `tasks/T110`, `docs/architecture.md` §3.
- **F-014:** `docs/modeling.md` §3.3.
- **F-017:** `tasks/T204` (`MetricHook`, `metric_hooks`, `peak_memory_mb`), `T303` (`hooks_quality.py`), `T403` (`hooks_aux.py`), `T404`.
- **F-018:** `tasks/T108` (Pliki, Testy).
- **F-019:** `tasks/README.md` §5.
- **F-021:** `docs/mlops.md` §2, `docs/config.md` §5, `tasks/T208`.
- **F-022:** `tasks/T102`, `tasks/T204`.
- **F-023:** `docs/environment.md` §4, `tasks/T604`.
- **F-024:** `docs/reliability.md` §3.
- **F-025:** `AGENTS.md` §7, `.github/pull_request_template.md`, `tasks/T209`.
- **F-026:** `.github/pull_request_template.md`.
- **F-027:** `docs/architecture.md` §6.
- **F-028, F-038:** `docs/decisions.md` (D-035) + odwołania w T103, T110, T201, T303, T604, T802.
- **F-029:** `tasks/T209`, `T801`, `T201`.
- **F-030:** `docs/inference_api.md` §2, `docs/config.md` §4, `docs/data_contract.md` §12, `tasks/T601`, `T402`.
- **F-031:** `AGENTS.md` §2 pkt 2, `.github/copilot-instructions.md`.
- **F-032:** `tasks/T001`, `T701`, `docs/environment.md` §2, `docs/mlops.md` §6 (komenda CI z `--extra all`).
- **F-033:** `docs/mlops.md` §7–§8, `tasks/T701`, `docs/reliability.md` §5 i §7, `tasks/T501`, `docs/data_contract.md` §9, `tasks/T107`, `tasks/T604`.
- **F-034, F-035:** `docs/environment.md` §5, §1.
- **F-036:** `tasks/T208`, `tasks/T203` (+ `docs/architecture.md` §3: `classical.py`).
- **F-037:** `docs/README.md` (zasady utrzymania, pkt 3), `tasks/T001` (`!reports/docs-audit/`).

`tasks/BACKLOG.md` zregenerowany (`python3 scripts/tasks.py backlog`); zmieniły się tylko wiersze T005, T110, T207, T305, T704, sumy, plan tygodniowy i graf.
