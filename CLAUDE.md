@AGENTS.md

## Claude Code — uzupełnienia

- Kartę zadania realizuj komendą `/task T###` (`.claude/commands/task.md`). Recenzję PR względem karty: `/review-task T###`.
- Przy zadaniach rozmiaru **L** zacznij w trybie planowania i pokaż plan przed edycją plików.
- Testy i skrypty uruchamiaj przez `uv run ...`. Nie uruchamiaj treningu na pełnym PTB-XL, jeśli karta lub człowiek o to nie prosi.
- Nie czytaj zawartości `data/`, `outputs/`, `mlruns/`, `mlartifacts/`, `models/bundles/` — to duże binaria. Do testów służy fixture `mini_ptbxl_root` (`tests/conftest.py`).
- Raport dla zespołu pisz po polsku; kod, docstringi i commity po angielsku.
- Jeśli realizacja wymaga zmiany kontraktu z `docs/` albo wyjścia poza „Zakres” karty — zatrzymaj się i zapytaj.
- Prywatne, niecommitowane instrukcje trzymaj w `CLAUDE.local.md` (plik jest w `.gitignore`).
