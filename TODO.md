# Ralph Framework — TODO

Lista uporządkowanych zadań do wykonania na Ralph Framework. Każda sekcja jest self-contained — można ją wykonać w pojedynczej iteracji z czystym kontekstem.

**Instrukcja dla agenta wykonującego:** Weź **jedną** sekcję oznaczoną `[ ]` (pierwszą nieukończoną od góry), wykonaj wszystko z niej, zmień `[ ]` na `[x]` w tym pliku, i zrób pojedynczy commit. Nie bierz kilku sekcji naraz — kontekst nie starczy. Nie rób refaktoru poza scope sekcji.

**Kluczowe pliki:**
- `scripts/ralph/ralph.sh` — orkiestrator (867 linii)
- `scripts/ralph/CLAUDE.md` — instrukcje dla agenta
- `scripts/ralph/ralph.config` — konfiguracja
- `scripts/ralph/skills/` — 4 skille (prd_init, prd_append, karpathy-guidelines, playwright-skill)
- `init.sh` — bootstrap do projektu
- `README.md` — dokumentacja

---

## [x] 1. Napraw lub usuń `--tool amp`

**Problem:** W `ralph.sh` ok. linii 390-400 budowany jest `enriched_prompt` z task_id, opisem, acceptance criteria. Ścieżka dla `TOOL=claude` używa tego prompta. Ścieżka dla `TOOL=amp` go ignoruje i tylko pipe'uje `CLAUDE.md` do `amp`. Amp nie wie który task ma wziąć — każde odpalenie robi to samo niezależnie od `task_id`.

**Do wyboru:**
- **Opcja A (preferowana):** Usuń całkowicie `--tool amp`. Usuń flagę CLI, usuń branch w `run_worker`, usuń wzmianki z README. Zostaw tylko claude.
- **Opcja B:** Napraw tak, żeby amp dostawał `enriched_prompt` przez stdin albo argument (zależnie od tego jak amp faktycznie przyjmuje prompt — sprawdź `amp --help` jeśli jest zainstalowany; jeśli nie, wybierz opcję A).

**Akceptacja:**
- Jeden tryb działa, README zgadza się z kodem.
- `grep -r amp scripts/ README.md` zwraca tylko sensowne referencje (albo brak).

---

## [x] 2. Usuń fallback `git add -A` który maskuje niedokończone zadania

**Problem:** W `ralph.sh` (ok. linii 407-417) po uruchomieniu agenta sprawdzany jest `commits_ahead`. Jeśli 0 ale są zmiany w `git status --porcelain`, orchestrator sam robi `git add -A && git commit -m "feat: $task_id - automated implementation"`. To:
- łapie śmieci z `npm install` (np. zmodyfikowany lockfile)
- ukrywa że agent nie dokończył zadania
- generyczny commit message zamiast tego co agent miał napisać

**Do zrobienia:**
- Usuń cały bloczek `if [ "$commits_ahead" -eq 0 ]; then ... git add -A ... fi`.
- Zostaw tylko sprawdzenie `commits_ahead == 0` → oznacz task jako failed (return 1), z jasnym komunikatem: `"Agent nie zrobił commita — zadanie zostanie retry'owane"`.
- Zadbaj żeby retry counter się zwiększył dla takiego przypadku.

**Akceptacja:**
- Brak `git add -A` w `ralph.sh` (poza ewentualnie konflikt-resolve, który jest OK).
- Taski bez commitów są liczone jako failed, nie jako success.

---

## [x] 3. Feedback validation failure do agenta na retry

**Problem:** Gdy `VALIDATE_CMD` failuje (`ralph.sh` ok. linii 430-445), branch jest kasowany i task idzie na retry. Agent przy retry nie dostaje loga walidacji — zaczyna od zera, ma takie same szanse jak poprzednio.

**Do zrobienia:**
- Kiedy validation failuje, zapisz ostatnie N (~50) linii `$logfile.validate` do pliku `$LOG_DIR/${task_id}.last_failure.txt`.
- W `run_worker`, przy budowaniu `enriched_prompt`, jeśli ten plik istnieje — dodaj sekcję:
  ```
  PREVIOUS ATTEMPT FAILED VALIDATION WITH:
  <tail z last_failure.txt>
  
  Fix these issues specifically.
  ```
- Po zadaniu zakończonym success — usuń `last_failure.txt`.

**Akceptacja:**
- Po failed validation, następny retry dostaje log błędu w prompcie.
- Nie duplikuje się przy kolejnych iteracjach (tylko ostatni failure).

---

## [ ] 4. Wytnij kosmetykę z ralph.sh

**Problem:** ~200 linii w `ralph.sh` to wyłącznie UX dla człowieka który i tak nie ogląda. Ralph działa godzinami w tle. Nikomu nie potrzebny jest spinner i merge-box.

**Do usunięcia:**
- Wszystkie zmienne kolorów (BOLD/DIM/RED/GREEN/BOLD\* itd.) — linie ~85-105. Zostaw 3-4 proste: RED, GREEN, YELLOW, RST.
- `start_spinner` / `stop_spinner` — cały blok (linie ~155-178). Zastąp prostym `wait` bez spinnera.
- `progress_bar()` — wytnij, zastąp `"$completed/$total"`.
- `print_merge_box()` — cały (~105 linii) wytnij. Zastąp jedno-liniowym logiem: `log_ok "Merged $task_id: $t_title ($files_n files, +$ins_n/-$del_n)"`.
- ASCII-art logo na starcie (linie ~697-702) — wytnij.
- `hr()` helper — wytnij (lub zostaw najprostszą wersję bez kolorów).
- Ujednolić `log_*` helpery — powinny być 3-4, nie 6.

**Do zachowania:**
- Podstawowe logi (timestamp + message).
- `failed_report.json` — to ma wartość.
- Task-id prefix w logach.

**Akceptacja:**
- `ralph.sh` ma ≤ 667 linii (z ~867).
- Output działa w terminalu bez kolorów też czytelnie.
- Nie ma spinnera ani ASCII art.

---

## [ ] 5. Usuń plugin-installation hack w init.sh

**Problem:** `init.sh` (linie ~87-140) ręcznie manipuluje `~/.claude/plugins/cache/local/ralph-framework/1.0.0/` i edytuje `~/.claude/plugins/installed_plugins.json` przez inline Python. To kruche, undocumented API Claude Code. Dodatkowo skille są kopiowane 2× (do projektu + do plugin cache) — niejasne która wersja wygrywa.

**Do zrobienia:**
- Wytnij cały blok plugin-installation (od `PLUGIN_CACHE=` do końca `fi` sekcji pluginowej).
- Skille zostają tylko w `scripts/ralph/skills/` (per-project).
- Dodaj do README sekcję **"Manual skill installation"** z instrukcją jak user może ręcznie skopiować skille do `~/.claude/skills/` jeśli chce globalnie (opcjonalne). NIE automatyzuj tego.
- Zaktualizuj komunikat na końcu `init.sh` — bez "restart Claude Code to activate skills".

**Akceptacja:**
- `init.sh` nie dotyka niczego poza katalogiem target-projektu.
- `init.sh` nie ma inline Pythona.
- README wyjaśnia że skille są project-local, globalna instalacja jest manualna.

---

## [ ] 6. Usuń `karpathy-guidelines` skill (treść już w CLAUDE.md)

**Problem:** `skills/karpathy-guidelines/SKILL.md` duplikuje zasady które są już wklejone w `scripts/ralph/CLAUDE.md` (sekcja "Coding Philosophy"). Skill sam w opisie mówi "use this to review the principles". Osobny skill na statyczny dokument to nadmiar.

**Do zrobienia:**
- Usuń katalog `scripts/ralph/skills/karpathy-guidelines/`.
- Usuń wzmianki o `karpathy-guidelines` z:
  - `init.sh` (mkdir, cp, plugin register)
  - `README.md` (sekcja Skills)
  - ewentualne refy w innych skillach
- Sprawdź że w `CLAUDE.md` zasady są w całości (sekcja "Coding Philosophy" ma 4 punkty: Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution). Jeśli czegoś brakuje — dopisz do CLAUDE.md.

**Akceptacja:**
- `grep -r karpathy scripts/ README.md init.sh` zwraca 0 matchów (poza ewentualnie commit message history).
- `CLAUDE.md` ma pełne 4 zasady Karpathy'ego.

---

## [ ] 7. Pogódź Karpathy "ask when confused" z `--print` mode

**Problem:** `CLAUDE.md` i enriched_prompt każą agentowi "State assumptions, present interpretations, ask when confused, don't guess". Ale Ralph odpala claude w `--print --dangerously-skip-permissions` — one-shot, non-interactive. Agent fizycznie NIE MOŻE zapytać. To cargo-cult instrukcja.

**Do zrobienia:**
- W `scripts/ralph/CLAUDE.md`, sekcja "Coding Philosophy" / "Think Before Coding" — zmień na realistyczne: zamiast "ask when confused" napisz:
  > **Think Before Coding** — State your assumptions explicitly in your progress report. If a request has multiple valid interpretations, pick the most conservative one and flag the ambiguity in `progress.txt` under `**Learnings**` so the human reviewer sees it. You are running non-interactively — do not wait for clarification, but do not silently guess either.
- Podobnie dla "Goal-Driven Execution" / "For multi-step tasks: State a plan ... confirm before executing" — zmień na: "state the plan in your commit message/progress report, then execute".
- Jeśli jest wzmianka w README o tych zasadach — dopasuj język.

**Akceptacja:**
- Żadna instrukcja nie każe agentowi "ask", "confirm with user", "wait for approval" w runtime który jest `--print`.
- Ambiguity handling jest: "log it, pick safe default, move on".

---

## [ ] 8. Dedupe `enriched_prompt` vs CLAUDE.md

**Problem:** `run_worker` buduje duży `enriched_prompt` ze story_title, story_desc, acceptance_criteria, tags, recent_progress. Ale `CLAUDE.md` już każe agentowi "read prd.json, check RALPH_TASK_ID, read progress.txt". Agent dostaje te same info dwa razy.

**Do zrobienia — wybierz jedną ścieżkę:**

**Opcja A (preferowana — prosty prompt):** Uprość `enriched_prompt` do:
```
You are Ralph. Read scripts/ralph/CLAUDE.md and follow it.
RALPH_TASK_ID=$task_id
```
Agent sam wyciągnie story z prd.json i progress.txt z pliku. Mniej duplikacji, mniej tokenów.

**Opcja B (inline kontekst, wywal plik-reading):** Zostaw `enriched_prompt` z task context, ale w `CLAUDE.md` USUŃ instrukcje "read prd.json, read progress.txt — pick story" — bo to jest już w prompcie. CLAUDE.md skupia się wtedy tylko na ZASADACH (jak pisać kod, jak commitować), nie na task-picking.

Wybierz A. Jest prostsze i trzyma "source of truth" w prd.json + CLAUDE.md, zamiast w bash heredocu.

**Akceptacja:**
- `enriched_prompt` w ralph.sh ma ≤ 5 linii.
- CLAUDE.md jest jedynym miejscem z instrukcjami jak agent ma czytać prd.json i progress.txt.
- `recent_progress` z tail -30 zostaje wyrzucone z bash-a (agent czyta plik sam).

---

## [ ] 9. Playwright opt-in, nie domyślny

**Problem:** `init.sh` kopiuje playwright-skill do każdego projektu i odpala `npm run setup` który ściąga Chromium (~300MB). Nie każdy projekt to UI.

**Do zrobienia:**
- Dodaj flagę `--with-playwright` do `init.sh`. Bez niej — pomiń playwright-skill całkowicie (nie kopiuj, nie instaluj).
- Zmień sekcję w `init.sh` która kopiuje `PW_SRC` → `PW_DST` na conditional: tylko jeśli `$WITH_PLAYWRIGHT == true`.
- Zaktualizuj `README.md` — sekcja Quick Start: "UI testing jest opcjonalny. Dodaj `--with-playwright` do init.sh jeśli projekt ma frontend."
- W `CLAUDE.md` sekcja "Browser Testing" — dodaj wstęp: "If playwright-skill is installed at scripts/ralph/skills/playwright-skill/, use it for UI verification. Otherwise skip browser testing and note it in progress report."

**Akceptacja:**
- `./init.sh /path` bez flagi NIE ściąga Chromium i NIE kopiuje playwright-skill.
- `./init.sh /path --with-playwright` robi to co teraz.
- README i CLAUDE.md mówią jasno że to opcjonalne.

---

## [ ] 10. Timeout per task + rotacja progress.txt

**Problem 1:** Brak timeoutu — agent może utknąć na godzinę. Przy opus to drogo.
**Problem 2:** `progress.txt` rośnie nieograniczenie. Agent czyta tail -30 ale sam plik może mieć 5000 linii.

**Do zrobienia:**

**Timeout:**
- Dodaj do `ralph.config` zmienną `TASK_TIMEOUT_SEC=1800` (default 30 min).
- W `run_worker`, owiń wywołanie `claude` w `timeout "$TASK_TIMEOUT_SEC" claude ...`.
- Przy exit code 124 (timeout) — log jako `TIMEOUT`, zalicz jako failure, retry normalnie.

**Rotacja progress.txt:**
- Dodaj funkcję `rotate_progress()` która:
  - Sprawdza jeśli `progress.txt` > 200 linii.
  - Przenosi wszystko POZA sekcją `## Codebase Patterns` (od góry) do `archive/progress-YYYY-MM-DD-HHMM.txt`.
  - Zostawia tylko Codebase Patterns + fresh header.
- Wywołaj `rotate_progress` raz na początku każdego batcha (w głównej pętli `while`).

**Akceptacja:**
- Zadanie które trwa > timeout jest zabijane i retry'owane.
- `progress.txt` nigdy nie przekracza ~250 linii operacyjnie (Codebase Patterns + ostatnie zadania).
- Zarchiwizowane progressy lądują w `archive/`.

---

## [ ] 11. `get_pending_tasks` — pozwól na cross-priority parallelism

**Problem:** Funkcja bierze tylko taski z `min_priority`. Przy `[priority=1, priority=2, priority=3]` i `--parallel 4` polecą tylko taski z priority=1. Równoległość marnowana.

**Do zrobienia:**
- Zmień `get_pending_tasks` żeby zwracała WSZYSTKIE `passes=false` posortowane po priority rosnąco (nie tylko `min_priority`).
- Filtrowanie po retry-exhausted zostaw.
- W main loop, `run_batch=("${batch[@]:0:$PARALLEL}")` wybierze top-N po priority, więc zachowamy ordering "dependencies first".

**UWAGA:** Jeśli user polega na tym że priority=1 kończy się przed priority=2 (bo zależności) — ten zmiana jest OK, bo i tak priority=1 będą wybrane pierwsze, a ralph.sh i tak mergeuje batch przed następnym. Ale warto dodać notkę do README:
> "Priority defines preferred execution order, but parallel workers may execute different priorities concurrently within one batch. Put hard dependencies in earlier priorities and trust the batch boundary (merge happens between batches)."

**Akceptacja:**
- `--parallel 4` z 4 pending taskami o różnych priority — odpala 4 workerów.
- Ordering nadal preferuje niższy priority.
- README ma krótką notkę o semantyce priority.

---

## [ ] 12. Napraw PR workflow albo go usuń

**Problem:** Orchestrator tworzy PR przez `gh pr create`, potem mergeuje lokalnie i robi `gh pr close` z komentarzem "Merged by Ralph". `gh pr close` zostawia PR w stanie **closed, NOT merged** — na liście GitHub wygląda jak anulowany. Workflow PR-owy traci wartość.

**Do zrobienia — wybierz:**

**Opcja A (preferowana — właściwy merge przez gh):**
- Zamiast mergować lokalnie + zamykać PR, użyj `gh pr merge $pr_number --squash --delete-branch` (albo `--merge` jeśli user woli merge-commit — sparametryzuj).
- Usuń blok lokalnego `git merge --no-ff` z `merge_tasks()` dla ścieżki gdzie PR istnieje.
- Konflikt-resolve zostaje lokalnie (bo gh nie radzi sobie z konfliktami), ale po resolve robisz `git push` do feature branch i dopiero wtedy `gh pr merge`.

**Opcja B (prostsza — usuń PR całkowicie):**
- Wytnij flagę `--no-pr` i cały kod `gh pr create` / `gh pr close`.
- Ralph tylko mergeuje lokalnie i pushuje do base branch.
- README wyjaśnia: "Ralph merges directly. Code review happens on the base branch post-factum, not per-task."

Wybierz B jeśli chcesz mniej kodu, A jeśli chcesz trzymać audit trail.

**Akceptacja:**
- Nie ma stanu "PR closed, not merged" w GitHubie.
- Kod jest spójny z wybraną opcją (brak martwych ścieżek).

---

## [ ] 13. Polish — drobne poprawki higieny

**Do zrobienia w jednym commit:**

- **`set -e` w ralph.sh:** Zmień `set -uo pipefail` na `set -euo pipefail`. Przejdź przez plik i dodaj `|| true` tam gdzie failure jest OK (np. `git worktree remove`). Usuń `|| true` tam gdzie maskuje prawdziwe błędy.
- **`progress_bar` local var:** Zmienna `pb_i` w `progress_bar` nie jest `local`. Jeśli `progress_bar` już nie istnieje (po sekcji 4) — pomiń.
- **jq STORIES_FIELD interpolacja:** W `ralph.sh` jest mnóstwo `jq ".${STORIES_FIELD}[]..."` — jeśli STORIES_FIELD ma w sobie backticki lub cudzysłowy, jq się wysypie. Zwaliduj na początku: `[[ "$STORIES_FIELD" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || { echo "Invalid STORIES_FIELD"; exit 1; }`.
- **Auto-resolve `prd.json` merge:** W `merge_tasks()` auto-resolve dla `prd.json` — zostaw, ale dodaj komentarz dlaczego ("agent nie powinien modyfikować prd.json; konflikt oznacza że orchestrator sam aktualizuje mark_done pomiędzy mergami").
- **`--force-with-lease` na pierwszym push:** `git push -u origin "$branch" --force-with-lease` na nowym branchu który nie istnieje w remote — zamień na `git push -u origin "$branch"` (zwykły push, bez force). `--force-with-lease` ma sens tylko przy update istniejącego brancha.

**Akceptacja:**
- `bash -n scripts/ralph/ralph.sh` przechodzi.
- Shell errors nie są ciche.
- Komentarze tam gdzie zachowanie jest nieoczywiste.

---

## [ ] 14. Aktualizacja README pod kątem wszystkich zmian

**Problem:** Po wszystkich cięciach README będzie nieaktualny.

**Do zrobienia:**
- Zaktualizuj `README.md`:
  - Usuń wzmianki o amp (jeśli wybrano opcję A z #1).
  - Usuń `karpathy-guidelines` z sekcji Skills (sekcja #6).
  - Dodaj notkę o `--with-playwright` (sekcja #9).
  - Dodaj notkę o `TASK_TIMEOUT_SEC` i rotacji progress.txt (sekcja #10).
  - Dodaj notkę o cross-priority parallelism (sekcja #11).
  - Zaktualizuj PR workflow opis (sekcja #12).
- Zaktualizuj `README.md` / tabelę konfiguracji — dodaj `TASK_TIMEOUT_SEC`.
- Sprawdź że Quick Start jest nadal poprawny (kroki install → prd_init → ralph.sh).

**Akceptacja:**
- `README.md` odpowiada stanowi kodu po wszystkich poprzednich sekcjach.
- Nie ma referencji do usuniętych feature'ów.
- Sekcja Configuration jest kompletna.

---

## Kolejność wykonania (rekomendacja)

1. Najpierw **zepsute** (sekcje 1-3) — usuwa kłamstwa z projektu.
2. Potem **redukcja** (4-6) — tnie kod i duplikację.
3. Potem **spójność filozofii** (7-8) — dopasuj instrukcje do runtime.
4. Potem **opcjonalność i safety** (9-10) — playwright opt-in, timeouty.
5. Potem **ulepszenia** (11-12) — parallelism, PRy.
6. Na końcu **polish + docs** (13-14).
