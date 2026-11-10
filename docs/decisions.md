# Rejestr decyzji projektowych

Każda zmiana kontraktu, wybór technologii lub odstępstwo od specyfikacji trafia tutaj. Wpisów nie usuwamy —
nieaktualne oznaczamy statusem `zastąpiona przez D-xxx`.

Szablon nowego wpisu:

```markdown
## D-0xx — Tytuł
- **Status:** proponowana | przyjęta | zastąpiona przez D-0yy · **Data:** RRRR-MM-DD · **Zadanie:** T###
- **Kontekst:** dlaczego decyzja jest potrzebna.
- **Decyzja:** co wybieramy.
- **Konsekwencje:** co to zmienia, co trzeba zaktualizować.
```

## D-001 — AGENTS.md jako jedno źródło instrukcji dla agentów
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** zespół używa różnych narzędzi (Codex, Claude Code, Cursor, Copilot, Gemini); duplikowanie instrukcji prowadzi do rozjazdów.
- **Decyzja:** zasady są wyłącznie w `AGENTS.md`. `CLAUDE.md` i `GEMINI.md` importują go (`@AGENTS.md`), `.github/copilot-instructions.md` zawiera skrót i odsyłacz.
- **Konsekwencje:** zmiany zasad tylko w `AGENTS.md`; pliki narzędziowe zawierają wyłącznie dodatki specyficzne dla narzędzia.

## D-002 — Język dokumentacji i kodu
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** specyfikacja i raport są po polsku, ekosystem ML — po angielsku.
- **Decyzja:** `docs/`, `tasks/`, UI — po polsku; identyfikatory, docstringi, komentarze, logi i commity — po angielsku.
- **Konsekwencje:** komunikaty błędów API dla użytkownika po polsku (`message`), kody błędów po angielsku.

## D-003 — Oficjalny split i blokada testu
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** PTB-XL dostarcza `strat_fold` z rozłącznością pacjentów; foldy 9–10 mają wyższą jakość etykiet.
- **Decyzja:** train = 1–8, val = 9, test = 10; brak walidacji krzyżowej w głównym protokole; dostęp do testu tylko przez `cardioai.data.test_lock` (`docs/evaluation.md` §7).
- **Konsekwencje:** każdy wybór (także progi i kalibracja) odbywa się na foldzie 9; test używany jednorazowo w T801.

## D-004 — Etykiety superklas zgodne z benchmarkiem
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** chcemy porównywalności z benchmarkiem PTB-XL.
- **Decyzja:** superklasy z kodów `diagnostic == 1` przez `diagnostic_class`; `likelihood` ignorowane; rekordy bez superklasy w indeksie, ale wykluczone z zadania głównego (`docs/data_contract.md` §4).
- **Konsekwencje:** inny próg `likelihood` lub włączenie rekordów bez etykiet to osobne warianty eksperymentalne.

## D-005 — Menedżer środowiska uv i warianty PyTorch
- **Status:** przyjęta · **Data:** 2026-10-31 · **Uzupełnienie T001:** 2026-11-10
- **Kontekst:** trzy platformy (Windows + CUDA, macOS + MPS, Linux CI bez GPU) i jeden lockfile.
- **Decyzja:** `uv` + `pyproject.toml` + `uv.lock`; Python 3.11–3.12; PyTorch przez wykluczające się extras `cpu` i `cuda` z indeksami PyTorch; extras funkcjonalne `api`, `xai`, `onnx`, `lgbm`, zbiorczo `all`.
- **Wariant CUDA (T001):** wybieramy **CUDA 12.6 (`cu126`)**, z jawnym indeksem `https://download.pytorch.org/whl/cu126`. [Indeks PyTorch](https://download.pytorch.org/whl/cu126/torch/) udostępnia wheels Windows x86_64 dla Pythona 3.11 i 3.12; wspieramy wymaganą w projekcie architekturę RTX 2060 (Turing). Przyjmujemy sterownik Windows ≥ 560.76 / Linux ≥ 560.28.03 według tabeli CUDA 12.6 GA w [dokumentacji NVIDIA](https://docs.nvidia.com/cuda/archive/12.6.0/cuda-toolkit-release-notes/index.html#cuda-driver), bez polegania na ograniczonej zgodności minor. Wariant 12.6 pozwala pozostać w rodzinie CUDA 12 i ma gotowe wheels dla obu wspieranych wersji Pythona. Wersja sterownika rzeczywistego laptopa i dostępność GPU pozostają do potwierdzenia przez właściciela na Windows; nie były mierzone na Macu.
- **Konfiguracja (T001):** zgodnie z [przewodnikiem uv](https://docs.astral.sh/uv/guides/integration/pytorch/) indeksy są `explicit = true`, a `cpu` i `cuda` wykluczają się. Na macOS oba źródła mają wyłączający marker `sys_platform != 'darwin'`, więc PyTorch pochodzi z PyPI z obsługą MPS; zalecanym extra na Macu jest `cpu`. `all` łączy extras funkcjonalne przez zależność `cardioai[api,xai,onnx,lgbm,tracking]`, bez wyboru akceleratora.
- **Konsekwencje:** jeden wygenerowany `uv.lock` dla wszystkich platform; test instalacji i wykonania na Windows/RTX 2060 jest nadal wymagany w PR. PyTorch (> 50 MB) i frameworki API/tracking są przewidziane zakresem T001 i zamykane w extras. Uzupełnione przez D-033.
- **Audyt przenośności T001 (2026-11-10):** cele instalacji to macOS ARM64, Windows x86_64 i Linux x86_64/ARM64, Python 3.11–3.12. `required-environments` zabezpiecza te architektury podczas aktualizacji lockfile; testy instalacyjne sprawdzają wheels bez budowania kodu na niewłaściwej platformie oraz importy zainstalowanych bibliotek. Zależność systemowa LightGBM: OpenMP (`libomp` na macOS, `libgomp1` na Debianie/Ubuntu, runtime Visual C++ x64 na Windows). Sam sukces `uv sync` nie dowodzi możliwości załadowania biblioteki natywnej. Aktualny zestaw `all` wymaga macOS ≥ 14 i Linux z glibc ≥ 2.28; instrukcje są w `docs/environment.md` §2. Nie zmienia to kontraktów danych, konfiguracji modeli ani API. Docelowy frontend i produkcyjne obrazy Docker pozostają w T606/T701.

## D-006 — Config: YAML + Pydantic, bez Hydry
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** potrzebujemy walidacji i kompozycji configów przy małej złożoności.
- **Decyzja:** YAML z listą `extends`, nadpisania `--set`, walidacja Pydantic `extra="forbid"`, `config_hash` (`docs/config.md`).
- **Konsekwencje:** brak zależności od Hydry/OmegaConf; sweep hiperparametrów realizujemy skryptami.

## D-007 — Hosting serwera MLflow
- **Status:** proponowana (decyzja w T004) · **Data:** 2026-10-31
- **Kontekst:** trzy maszyny w różnych sieciach muszą logować do jednego trackera.
- **Decyzja:** do wyboru w T004 między serwerem na maszynie zespołu z VPN typu mesh a usługą hostowaną (`docs/mlops.md` §1).
- **Konsekwencje:** kod zależy tylko od `MLFLOW_TRACKING_URI`; po wyborze uzupełnić ten wpis i `docs/mlops.md` §1.

## D-008 — Dodatkowe pakiety względem specyfikacji
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** specyfikacja umieszcza metryki w `training/`, a API w katalogu `api/` bez pakietu.
- **Decyzja:** osobne pakiety `cardioai.evaluation` (metryki, progi, raporty) i `cardioai.tracking` (MLflow) oraz instalowalny pakiet `api/cardioai_api`; granice pilnuje `import-linter`.
- **Konsekwencje:** `reliability` i `inference` korzystają z metryk bez zależności od pętli treningowej. Uzupełnione przez D-024.

## D-009 — 100 Hz jako wariant domyślny
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** ograniczone zasoby (6 GB VRAM, 16 GB RAM), specyfikacja §1.2.
- **Decyzja:** wszystkie eksperymenty na 100 Hz; 500 Hz tylko w E10 dla ustabilizowanego ResNet1D, przez cache memmap.
- **Konsekwencje:** API przyjmuje inne `fs` i resampluje do `fs` modelu z ostrzeżeniem `RESAMPLED`.

## D-010 — Kolejność transformacji i konwencja brakującego odprowadzenia
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** SNR ma sens fizyczny w mV, a brak kanału musi znaczyć to samo w treningu, robustness i inferencji.
- **Decyzja:** kolejność z `docs/data_contract.md` §8; brakujące odprowadzenie = 0.0 w przestrzeni znormalizowanej + `lead_mask = False`.
- **Konsekwencje:** `lead_dropout` działa po normalizacji, korupcje i szum — przed nią. Uzupełnione przez D-023.

## D-011 — Brak filtracji w wariancie bazowym
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** informacja ST/T jest wrażliwa na filtrację (specyfikacja §4.3).
- **Decyzja:** domyślnie tylko normalizacja; filtry zerofazowe (`sosfiltfilt`) wyłącznie jako ablacja z oceną per klasa (szczególnie STTC).
- **Konsekwencje:** statystyki normalizacji są liczone osobno dla każdego wariantu preprocessingu (`pp_id`).

## D-012 — Etykiety jakości: 4 klasy
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** pola jakości PTB-XL są niepełne; korupcje syntetyczne dają dokładne etykiety.
- **Decyzja:** `static_noise`, `burst_noise`, `baseline_drift`, `electrode_problem`; korupcje mapowane na te klasy (`docs/reliability.md` §2); saturacja tylko jako reguła twarda.
- **Konsekwencje:** głowa jakości ma 4 logity; parsowanie per odprowadzenie — poza MVP.

## D-013 — Checkpoint ładowany z `weights_only=True`
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** nowsze wersje PyTorch domyślnie ładują checkpointy w trybie bezpiecznym.
- **Decyzja:** checkpoint zawiera tylko tensory i typy proste (`docs/modeling.md` §6).
- **Konsekwencje:** dataclassy, tablice NumPy i obiekty sklearn konwertujemy do typów prostych przed zapisem.

## D-014 — Bundle jako jedyny interfejs trening → serwowanie
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** API nie może zależeć od kodu treningowego ani MLflow.
- **Decyzja:** bundle (`docs/inference_api.md` §2) zawiera wagi i wszystkie parametry w JSON (bez pickle); `cardioai_api` importuje tylko `cardioai.inference`.
- **Konsekwencje:** wymiana modelu = wymiana bundla; testy round-trip eksport → ładowanie → predykcja.

## D-015 — Wielokrotne użycie foldu 9
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** early stopping, progi, kalibracja, quality gate i abstention potrzebują danych walidacyjnych, a test jest zamrożony.
- **Decyzja:** wszystkie dopasowania na foldzie 9; metryki niezawodności do raportu dodatkowo w schemacie cross-fitting (dwie połowy val, patient-wise).
- **Konsekwencje:** ograniczenie opisane w karcie modelu; wyniki finalne tylko z testu.

## D-016 — Wiek ≥ 300 traktowany jako 90+
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** PTB-XL zapisuje wiek powyżej 89 lat w okolicy 300 (anonimizacja).
- **Decyzja:** `age ≥ 300` → `90.0` + `age_90plus = 1`.
- **Konsekwencje:** analiza podgrup wiekowych i metadane bez wartości odstających.

## D-017 — Rekordy demo z foldu 9
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** demo w UI nie może oznaczać oglądania predykcji na teście przed T801.
- **Decyzja:** do 50 rekordów z foldu 9, losowanych z seedem warstwowo po klasach (nie według trafności modelu), z przypisaniem PTB-XL.
- **Konsekwencje:** pliki demo są jedynymi danymi PTB-XL w repo (mały rozmiar, licencja CC BY 4.0). Uzupełnione przez D-028.

## D-018 — Frontend bez mocków w przeglądarce
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** chcemy jednego kontraktu i wczesnej integracji.
- **Decyzja:** frontend zawsze rozmawia z API; w trakcie prac API działa w trybie mock; typy TS generowane z `api/openapi.json`.
- **Konsekwencje:** API mock powstaje w tygodniu 3 (T604), przed modelem.

## D-019 — Kanoniczne urządzenie dla wyników finalnych
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** wyniki MPS i CUDA nie są bitowo zgodne.
- **Decyzja:** finalne runy i benchmarki modeli finalnych na laptopie A (RTX 2060, CUDA); MPS do rozwoju i eksploracji.
- **Konsekwencje:** tag `device` w MLflow; tabele finalne filtrują po urządzeniu.

## D-020 — Deterministyczne augmentacje niezależne od workerów
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** liczba workerów DataLoadera różni się między maszynami.
- **Decyzja:** RNG próbki = `np.random.default_rng([seed, epoch, ecg_id])`; epoka przekazywana przez sampler zwracający `(epoch, index)`.
- **Konsekwencje:** ten sam seed daje te same augmentacje na każdej maszynie (przy tym samym kodzie).

## D-021 — Rozszerzenie odpowiedzi API względem specyfikacji
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** przykład JSON w specyfikacji jest ilustracyjny i nie obejmuje statusów ani sygnału do wyświetlenia.
- **Decyzja:** API v1 dodaje `status`, `explanation` (z `lead_importance`), `signal`, `timing_ms`, `request_id`, `calibrated` (`docs/inference_api.md` §7).
- **Konsekwencje:** UI nie musi parsować plików WFDB po swojej stronie.

## D-022 — Demo bez bundla działa w trybie mock
- **Status:** przyjęta · **Data:** 2026-10-31
- **Kontekst:** wagi nie trafiają do gita, a `docker compose up` ma działać z czystego checkoutu.
- **Decyzja:** brak bundla → `MockPredictor` z wyraźnym banerem w UI; prawdziwy model z wydania GitHub (`scripts/fetch_bundle.py`) lub z obrazu w GHCR — wybór mechanizmu w T701/T702.
- **Konsekwencje:** README opisuje oba tryby; test e2e sprawdza oba. Uzupełnione przez D-026.

## D-023 — Korupcja robustness w `build_pipeline` przy `train=False`
- **Status:** przyjęta · **Data:** 2026-11-06 · **Zadanie:** T108
- **Kontekst:** `docs/data_contract.md` §8 dopuszcza korupcje w kroku 3 „tylko w robustness”, a `build_pipeline(train=False)` ignorował korupcje; nie było określone, kto i jak wstrzykuje korupcję w ewaluacji (robustness T305, syntetyczny val jakości T303). Uzupełnia D-010.
- **Decyzja:** `build_pipeline` zachowuje `train: bool` i dostaje parametr `robustness_corruption: Transform | None = None`. Jest on stosowany w kroku 3 (w mV, przed filtrem i normalizacją) **tylko** przy `train=False`. Augmentacje przy `train=False` są nadal ignorowane. `SyntheticQualityDataset` (T303) buduje własny dataset val z takim pipeline'em zamiast opakowywać gotowy `PTBXLDataset`.
- **Konsekwencje:** zmiany w `docs/data_contract.md` §8 (przypis przy kroku 3) oraz w kartach T108, T302, T303, T305. Wywołanie z `train=True` ignoruje `robustness_corruption` z ostrzeżeniem (w treningu działa parametr `corruption`).

## D-024 — Granice modułów: zakazy dotyczą importów bezpośrednich
- **Status:** przyjęta · **Data:** 2026-11-06 · **Zadanie:** T001
- **Kontekst:** `AGENTS.md` §3 zabrania `cardioai_api` importować wszystko poza `cardioai.inference` i `cardioai.constants`, ale `cardioai.inference` importuje m.in. `data`, `models` i `reliability`; `tracking` może importować `inference` tylko w `tracking/pyfunc.py` (T702). Dosłowna wykładnia (także importy pośrednie) wykluczałaby obie architektury. Uzupełnia D-008.
- **Decyzja:** zakazy z `AGENTS.md` §3 dotyczą **importów bezpośrednich**. W T001 kontrakty `import-linter` dla `cardioai_api` i `cardioai.tracking` mają `allow_indirect_imports = true`, a wyjątek pyfunc jest zapisany jako `ignore_imports = ["cardioai.tracking.pyfunc -> cardioai.inference"]`.
- **Konsekwencje:** `AGENTS.md` §3 i `docs/architecture.md` §4 dostają jedno zdanie wyjaśnienia; T001 opisuje dokładną konfigurację kontraktów.

## D-025 — Pierwszeństwo źródeł configu i skład `config_hash`
- **Status:** przyjęta · **Data:** 2026-11-06 · **Zadanie:** T002
- **Kontekst:** `docs/config.md` mówił, że zmienne środowiskowe „mają pierwszeństwo”, ale nie określał kolejności względem `--set` i YAML ani miejsca, w którym zmienne są stosowane (`get_device` czytał `CARDIOAI_DEVICE` osobno). Hash configu uwzględniał pola zależne od maszyny (`data.cache_dir`, `data.batch_size_eval`, `training.log_every_n_steps`).
- **Decyzja:** pierwszeństwo: `--set` > zmienna środowiskowa > plik YAML (po `extends`) > wartość domyślna. Mapowanie zmiennych na klucze wykonuje loader configu (T002): `CARDIOAI_DATA_ROOT → data.root`, `CARDIOAI_DEVICE → training.device`. `get_device` dostaje wartość już rozstrzygniętą. Z `config_hash` wyłączamy dodatkowo `data.cache_dir`, `data.batch_size_eval` i `training.log_every_n_steps`; `training.amp` zostaje w hashu (na CPU/MPS jest ignorowane — adnotacja w `docs/config.md` §6).
- **Konsekwencje:** zmiany w `docs/config.md` §1 i §6, `docs/modeling.md` §8, `docs/environment.md` §4 oraz w kartach T002, T003, T204.

## D-026 — Tryby `CARDIOAI_PREDICTOR`: `auto`, `real`, `mock`
- **Status:** przyjęta · **Data:** 2026-11-06 · **Zadanie:** T604
- **Kontekst:** D-022 wymaga, by demo działało bez bundla, a `docs/inference_api.md` §8 przewiduje `MODEL_NOT_LOADED` (503) przy braku bundla; przy domyślnym `real` oba zapisy się wykluczały. Uzupełnia D-022.
- **Decyzja:** `CARDIOAI_PREDICTOR ∈ {auto, real, mock}`, domyślnie `auto`. `auto` + brak bundla → `MockPredictor` z ostrzeżeniem w logu i `predictor_mode: "mock"`. `real` + brak bundla → 503 `MODEL_NOT_LOADED`. `mock` → zawsze mock.
- **Konsekwencje:** zmiany w `docs/inference_api.md` §8 i §9, `docs/environment.md` §4, `docs/mlops.md` §7 oraz w kartach T604, T605, T701.

## D-027 — Reguła decyzyjna E05: AUROC diagnozy na syntetycznym val
- **Status:** proponowana (do potwierdzenia przez A i B) · **Data:** 2026-11-06 · **Zadanie:** T303
- **Kontekst:** reguła E05 wymagała, by „średnia z krzywej szumu” rosła, ale krzywe odporności powstają dopiero w T305/T306 (E06), po T303.
- **Decyzja:** głowę jakości włączamy, jeśli spadek macro AUROC diagnozy na czystym val wynosi ≤ 0,005, a macro AUROC diagnozy na syntetycznym val (`predictions_val_qsynth.parquet`) wzrasta względem wariantu „tylko diagnoza”. Krzywe robustness z E06 są raportowane w T306 jako uzupełnienie, nie warunek.
- **Konsekwencje:** zmiany w `docs/experiments.md` (E05) oraz w kartach T303 i T306. Po potwierdzeniu przez A i B status zmienia się na `przyjęta`.

## D-028 — Rekordy demo jako `int16` w µV
- **Status:** przyjęta · **Data:** 2026-11-06 · **Zadanie:** T605
- **Kontekst:** D-017 dopuszcza do 50 rekordów demo, ale 50 rekordów `float32 [12, 1000]` ma ok. 2,4 MB, a hook `check-added-large-files` blokuje pliki > 1 MB. Uzupełnia D-017.
- **Decyzja:** rekordy demo zapisujemy jako `int16` w µV (`np.savez_compressed`; rozdzielczość PTB-XL to 1 µV/LSB), do 50 rekordów. Jeśli plik przekracza 1 MB, zmniejszamy liczbę rekordów (minimum 20). Limit pre-commit bez zmian.
- **Konsekwencje:** zmiany w `docs/inference_api.md` §9 oraz w kartach T604 i T605; API konwertuje dane do `float32` w mV przy odczycie.

## D-029 — Nazwy metryk MLflow i zestaw metryk progowych
- **Status:** przyjęta · **Data:** 2026-11-06 · **Zadanie:** T201
- **Kontekst:** nazwa `val/selective_risk@0.9` zawierała znak `@`, który nie jest dozwolony w kluczach metryk MLflow; wynik `macro_f1` z `docs/evaluation.md` §5 miał w MLflow inną nazwę; metryki z tabel §2 (Hamming, czułość, swoistość) nie miały kluczy.
- **Decyzja:** nazwy metryk tylko ze znaków `[A-Za-z0-9_./-]` (bez `@` i `:`). Metryki selective risk: `val/selective_risk_cov095`, `val/selective_risk_cov090`, `val/selective_risk_cov080`. Dodajemy `val/hamming_loss`, `val/f1_<KLASA>_tuned`, `val/sensitivity_<KLASA>`, `val/specificity_<KLASA>`. `macro_f1` z pliku metryk to w MLflow `val/macro_f1_tuned`.
- **Konsekwencje:** zmiany w `docs/mlops.md` §3, `docs/evaluation.md` §3 i §5 oraz w kartach T201, T502, T504.

## D-030 — Transformer a „3 rodziny modeli” (opcje do rozstrzygnięcia)
- **Status:** proponowana · **Data:** 2026-11-06 · **Zadanie:** T401
- **Kontekst:** Definition of Done ze specyfikacji wymaga trzech rodzin modeli, a Transformer (T401) ma poziom Extended i może nie powstać. Karta T401 zakłada wtedy, że trzecią rodziną jest baseline klasyczny (E01), co czyni Transformer opcjonalnym.
- **Decyzja:** do wyboru przez zespół: (a) baseline klasyczny (T203) liczy się jako trzecia rodzina, a T401 pozostaje Extended; (b) minimalny Transformer jako element Core (poziom T401 zmieniony na Core, zakres ograniczony do wariantu `cls` i 1 seeda).
- **Konsekwencje:** do czasu decyzji poziom T401 pozostaje bez zmian (Extended). Po wyborze należy zaktualizować `tasks/T401-transformer.md`, `docs/architecture.md` §9 i `tasks/README.md`.

## D-031 — Jeden eksperyment MLflow na pozycję Exx
- **Status:** przyjęta · **Data:** 2026-11-06 · **Zadanie:** T208
- **Kontekst:** `docs/mlops.md` §2 dopuszczał „eksperyment na pozycję lub jej wariant”, a configi (np. E04) mogły mieć różne `experiment.name` dla wariantów, co rozbijało porównania w `summarize_runs.py`.
- **Decyzja:** jeden eksperyment MLflow na pozycję Exx (`experiment.name = eNN_<opis>`). Wariant wyłącznie w `experiment.variant` i w nazwie runu. Configi E04 mają `experiment.name: e04_imbalance`.
- **Konsekwencje:** zmiany w `docs/mlops.md` §2, `docs/config.md` §5 (przykład) i `tasks/T208-imbalance-thresholds.md`.

## D-032 — Bundle: `aux_sizes`, `n_metadata` i osobna cecha `age_90plus`
- **Status:** proponowana · **Data:** 2026-11-06 · **Zadanie:** T601
- **Kontekst:** `build_model` wymaga `aux_sizes` i `n_metadata`, których nie ma w sekcji `model` bundla, więc `Predictor` nie mógł odtworzyć modelu z głowami pomocniczymi i metadanymi. Dodatkowo `age_90plus` jest w `docs/data_contract.md` §12 flagą przy `age`, ale lista `model.metadata.features` jej nie zawierała, więc wymiar `M` był niejednoznaczny.
- **Decyzja:** sekcja `model` bundla zawiera `aux_sizes: {nazwa: liczba}` i `n_metadata: int`. `age_90plus` jest osobną cechą metadanych; domyślna lista `model.metadata.features` to `["age", "age_90plus", "sex", "height", "weight"]`.
- **Konsekwencje:** zmiany w `docs/inference_api.md` §2, `docs/config.md` §4, `docs/data_contract.md` §12 oraz w kartach T601 i T402. Zmiana kontraktu bundla i configu — do potwierdzenia przez zespół.

## D-033 — `mlflow` w extra `tracking`
- **Status:** przyjęta · **Data:** 2026-11-06 · **Zadanie:** T001
- **Kontekst:** `mlflow` był zależnością bazową, więc trafiał do obrazu API, choć `cardioai.inference` i `cardioai_api` mają nie zależeć od MLflow (D-014). Uzupełnia D-005.
- **Decyzja:** `mlflow` przechodzi z zależności bazowych do extra `tracking`. Extra `all` = `api` + `xai` + `onnx` + `lgbm` + `tracking`. Obraz API instaluje się bez `tracking`.
- **Konsekwencje:** zmiany w kartach T001 (zależności i extras) i T701 (komenda `uv sync` w obrazie API); `docs/environment.md` §2 pozostaje poprawne (`--extra all` obejmuje `tracking`).

## D-034 — `models/bundles/current` jako katalog
- **Status:** przyjęta · **Data:** 2026-11-06 · **Zadanie:** T701
- **Kontekst:** `fetch_bundle.py` „ustawiał `current`” bez określenia mechanizmu (kopia czy dowiązanie symboliczne).
- **Decyzja:** `models/bundles/current` to zwykły katalog (kopia bundla), nie dowiązanie symboliczne. Tworzy go `fetch_bundle.py`.
- **Konsekwencje:** zmiany w `docs/mlops.md` §7–§8 i `tasks/T701-docker-compose.md`.

## D-035 — Drobne odstępstwa od specyfikacji
- **Status:** przyjęta · **Data:** 2026-11-06 · **Zadanie:** T103, T110, T201, T303, T604, T802
- **Kontekst:** w trakcie projektowania kontraktów i kart wprowadzono kilka drobnych różnic względem specyfikacji (`docs/spec/CardioAI_PTBXL_specyfikacja.pdf`); zbiorczo rejestrujemy je w jednym miejscu.
- **Decyzja:** (1) status odpowiedzi odrzuconej ze względu na jakość to `REJECTED` (zamiast `RECORD_REJECTED` / `LOW_QUALITY`); (2) metryki liczymy własnym kodem z referencją scikit-learn, bez `torchmetrics`; (3) dodatkowy parametr `lambda_diag` w stracie wielozadaniowej; (4) przesunięcia w harmonogramie: EDA w tygodniu 3 (T110), karta modelu w tygodniu 14 (T802); (5) skrypt budujący indeks nazywa się `build_index.py`.
- **Konsekwencje:** brak zmian w kontraktach — wpis dokumentuje różnice względem specyfikacji.
