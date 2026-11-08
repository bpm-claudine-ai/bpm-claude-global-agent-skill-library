# BPMspace Claude Global Skills Library

A small library of custom commands and skills for the Claude Code CLI, installed
once per machine and used in any repository, plus the scripts that keep the
installed copies in sync with this repo. Architecture and conventions live in
[CLAUDE.md](CLAUDE.md).

## 1. What This Is

Process skills come from Matt Pocock's plugin `mattpocock-skills@mattpocock`
(grilling, to-spec, to-tickets, implement, tdd, code-review, domain-modeling,
research, retro and the rest). This library holds only what that plugin does
not cover. Every custom item follows the `c-{org}-{type}-{name}` convention —
`c-bpm-sk-` for skills, `c-bpm-cm-` for commands, `c-bpm-ag-` for agents — so
several organisations' libraries can coexist in one `~/.claude/`.

| Path | Holds | Format |
|------|-------|--------|
| `my/skills/` | custom skills | directory per skill with `SKILL.md` |
| `my/commands/` | slash commands | one flat `.md` per command |
| `my/agents/` | teammate role definitions (currently none) | one flat `.md` per agent |
| `my/hooks/` | the hooks and their settings fragment | `c-bpm-hk-*.sh` + `c-bpm-hooks.json` |
| `my/hosts/` | per-host inventory written by the sync scripts | `.txt` |

## 2. Installation

### Fresh install

```bash
git clone git@github.com:BPMspaceUG/bpm-claude-global-agent-skill-library.git ~/bpm-claude-global-agent-skill-library
cd ~/bpm-claude-global-agent-skill-library
./install --global --with-c-bpm-library   # installs bcgasl + the c-bpm-library CLIs
c-bpm-cm-library-pull                     # copies all c-bpm items into ~/.claude/
```

Without a clone, the installer can be piped — the repo is cloned on the first
`c-bpm-cm-library-pull`:

```bash
curl -fsSL https://raw.githubusercontent.com/BPMspaceUG/bpm-claude-global-agent-skill-library/main/install | bash -s -- --global --with-c-bpm-library
```

`bcgasl` installs the standard (non-`c-bpm`) items from a **pinned release
tarball**; `c-bpm-cm-library-pull` is the path for the current `c-bpm` items.

### Required environment

- `gh` authenticated for the target repositories (`gh auth status`)
- `codex` CLI on `PATH` — the read-only reviewer used by `c-bpm-cm-spec-oneshot` and `c-bpm-sk-gogo`
- Matt Pocock's plugin installed: `claude plugin install mattpocock-skills@mattpocock`, then `/c-bpm-cm-pocock-update` once so the model may call its skills
- `bats` for the test suite

### Verification

```bash
ls ~/.claude/commands | grep -c '^c-bpm-cm-'            # 1. commands landed (expect 5)
ls ~/.claude/skills | grep -c '^c-bpm-sk-'              # 2. skills landed (expect 1)
command -v bcgasl c-bpm-cm-library-pull                 # 3. CLIs on PATH
gh auth status && codex --version                       # 4. reviewer reachable
```

### Updating an existing installation

After changes land on `main`, every machine needs both steps — pulling the repo
alone leaves the installed copies under `~/.claude/` stale:

```bash
cd ~/bpm-claude-global-agent-skill-library && git pull
c-bpm-cm-library-pull    # refresh the installed copies in ~/.claude/
```

### The hooks

`c-bpm-cm-library-pull` installs four hooks, `c-bpm-hk-agent-cleanup-guard`,
`c-bpm-hk-skills-refresh`, `c-bpm-hk-ask-matt-after-clear` and
`c-bpm-hk-ask-matt-read-guard`, and
registers them in `~/.claude/settings.json` (plus `~/.config/claude/settings.json`
when that file exists). Re-running the pull is idempotent and also replaces the
older stand-alone `agent-cleanup-guard.sh` registration.

| Event | What happens |
|-------|--------------|
| `TeammateIdle` | The teammate that just finished its turn is stopped by Claude Code (`continue: false`). |
| `Stop` | The user sees a line listing every teammate, subagent and shell still in flight. Open teammates and shells get one request to `TaskStop` them; never twice in a row. |
| `Stop` | An answer whose next-step line says "ask-matt empfiehlt" goes back to Claude once when ask-matt was not read in the session (a tool call on `ask-matt/SKILL.md`, a Skill call, or `/ask-matt`). |
| `SessionStart` (startup, /clear) | Claude is told to run `ListAgents` and stop leftover teammates before answering. |
| `SessionStart` (/clear) | The user sees at once the last next-step line ("Robert, du bist dran: …") of the conversation just cleared. A `Stop` hook caches that line after every answer in `~/.cache/c-bpm-next-step/` (per tmux pane and per directory); without a cache the cleared transcript is scanned. No model run. In tmux the first `/command` of a "Robert, du bist dran:" line (skipping `/clear`, `/compact`, `/resume`, `/exit`) is typed into the prompt without Enter. The line is also written to `session-<id>`, which the host status line (`/usr/local/bin/claude-statusline.sh`, `refreshInterval: 2`, see bpm-contabo03 #49) shows below the prompt until the first answer ends. Log `~/.claude/hooks/c-bpm-hk-ask-matt-after-clear.log`. |
| `SessionStart` (startup, resume) | The installed Pocock skills are unlocked at once, without network. At most once per 24 h a detached worker updates the plugin, unlocks again and runs `c-bpm-cm-library-pull`; the result applies from the next session. Log: `~/.claude/hooks/c-bpm-hk-skills-refresh.log`. |

Restart Claude Code after the first pull so the registration is loaded. The
cleanup hook writes every payload it sees, without the assistant's text, to
`~/.claude/hooks/c-bpm-hk-agent-cleanup-guard.log`. Both logs are capped at 256 KiB.

### Host variants

The next-step line exists in two variants, and each host gets exactly one:
`c-bpm-sk-next-step` (development hosts, step chosen via ask-matt) or
`c-bpm-sk-next-step-admin` (admin hosts, step from the open issues of the
host's repo). A host is an admin host when the file
`my/hosts/<hostname>/next-step-admin` exists in this repo; its first
`owner/name` line is the host repo, e.g. `BPMspaceUG/bpm-contabo04` for
contabo04. To make a host an admin host, commit that file here and run
`c-bpm-cm-library-pull` there:

```bash
mkdir -p my/hosts/<hostname> && echo '<owner>/<repo>' > my/hosts/<hostname>/next-step-admin
```

`c-bpm-cm-library-pull` then installs the admin variant and removes the
regular one (and the other way round when the file is deleted).
`c-bpm-cm-library-push` and `c-bpm-cm-library-compare` skip the variant a host
does not use, so `push --clean` never deletes it from the repo. The selection
lives in `lib.sh` (`host_admin_repo`, `host_skipped_item`). Hooks and mod parse
both variants' lines; the corpus `tests/fixtures/next-step-lines.tsv` holds
real lines of both.

### The mod

`my/mods/c-bpm-md-last-recommendation` is a Claude Code mod (hooks module,
early-access API): a pane on the right of the chat, "Last recommendation",
showing the last next-step line of an answer and keeping it across `/clear`
(it reads the per-pane cache of `c-bpm-hk-ask-matt-after-clear`). It opens by
itself from 144 terminal columns; `/last-recommendation` opens it at any width.
The mobile app docks no pane, so the hook's status-line hint and prefill stay.

It is not installed by `c-bpm-cm-library-pull`. It is loaded in every session
from this checkout through the `env` block of `~/.claude/settings.json`:

```json
"CLAUDE_CODE_PLUGIN_DIRS": "/home/matt/bpm-claude-global-agent-skill-library/my/mods/c-bpm-md-last-recommendation"
```

Edits reload live in running sessions; a new setting needs a session restart.
Check with `claude plugin validate my/mods/c-bpm-md-last-recommendation`.

### Removing the former enforcement hooks

Until 2026-10-23 this library registered `PreToolUse` and `SessionStart` hooks
(`issue-write-gate`, `plan-doc-gate`, `codex-sod-tracker`). They are gone from
the repo, but a host that installed them still has the registrations in its
settings files. Clean such a host once:

```bash
rm -rf ~/.claude/hooks/dist
for f in ~/.claude/settings.json ~/.config/claude/settings.json; do
  [ -f "$f" ] || continue
  python3 - "$f" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); hooks = d.get("hooks", {})
names = ("issue-write-gate", "plan-doc-gate", "codex-sod-tracker")
for ev in list(hooks):
    kept = []
    for entry in hooks[ev]:
        entry["hooks"] = [h for h in entry.get("hooks", []) if not any(n in h.get("command", "") for n in names)]
        if entry["hooks"]:
            kept.append(entry)
    if kept: hooks[ev] = kept
    else: del hooks[ev]
json.dump(d, open(p, "w"), indent=2); print("cleaned", p)
EOF
done
```

## 3. Items

| Item | Invoke as | Purpose |
|------|-----------|---------|
| `c-bpm-cm-spec-oneshot` | `/c-bpm-cm-spec-oneshot [major\|minor\|patch]` | Write or version a self-contained specification under `/specification/` and the overnight build prompt under `/prompts/`. One optional grilling round with Rob; every other open point is decided in the spec or delegated to Codex. |
| `c-bpm-sk-gogo` | `/c-bpm-sk-gogo [spec issue \| label]` | Unattended overnight run over the ready, unblocked tickets of the current repo: agent team, one worktree per ticket, Codex plan and implementation reviews, draft PR per integration branch. `TEAMMATE.md` is the teammate contract. |
| `c-bpm-sk-next-step` | model-invoked (also `/c-bpm-sk-next-step`) | Ends every answer with exactly one action line naming who acts: "Robert, du bist dran: …" (step chosen via ask-matt) or "Claude ist dran, du musst nichts tun: …" with the next watchdog check time. Running agents get a `CronCreate` watchdog loop that checks at least every 5 minutes. |
| `c-bpm-sk-next-step-admin` | model-invoked (also `/c-bpm-sk-next-step-admin`) | Admin-host variant of `c-bpm-sk-next-step`, installed instead of it where `my/hosts/<hostname>/next-step-admin` names the host repo: the step comes from that repo's open issues and the current admin work, never from ask-matt; the line names the issue (`#n`) and gives the reason after "Grund:". See "Host variants". |
| `c-bpm-cm-pocock-update` | `/c-bpm-cm-pocock-update [--check] [--no-update]` | Manual, immediate Pocock update and unlock; the `c-bpm-hk-skills-refresh` hook does the same at session start. |
| `c-bpm-cm-library-pull` | `/c-bpm-cm-library-pull` or the CLI | Sync c-bpm items from this repo into `~/.claude/` |
| `c-bpm-cm-library-push` | `/c-bpm-cm-library-push` or the CLI | Sync c-bpm items from `~/.claude/` into this repo; auto-commits and pushes |
| `c-bpm-cm-library-compare` | `/c-bpm-cm-library-compare` or the CLI | Show which c-bpm items differ between `~/.claude/` and the repo; optionally repair |
| `c-bpm-hk-agent-cleanup-guard` | hook, automatic | Stops finished teammates, lists what still runs at every turn end, demands an agent sweep after start and `/clear` (see "The hooks") |
| `c-bpm-hk-ask-matt-after-clear` | hook, automatic | Replays the last next-step line after `/clear`, prefills its `/command` in tmux, shows it in the status line until the first answer |
| `c-bpm-hk-ask-matt-read-guard` | hook, automatic | Sends an answer back once when it cites ask-matt that was not read in the session |
| `c-bpm-hk-skills-refresh` | hook, automatic | Unlocks the Pocock skills at start; daily plugin update and library pull |
| `c-bpm-md-last-recommendation` | mod, `/last-recommendation` | Pane "Last recommendation" beside the chat (see "The mod") |

How the two overnight flows relate: `c-bpm-cm-spec-oneshot` produces a spec and
a build prompt that rebuilds a whole project from an empty directory; the run is
started by pasting that prompt into `claude`. `c-bpm-sk-gogo` works the ticket
graph of an existing repo (tickets from `/to-spec` and `/to-tickets` carrying the
"ready for agent" label). Both never ask a human; both route decisions to Codex.

Shell CLIs installed by `./install`: `bcgasl` (standard items from the pinned
release) and `c-bpm-cm-library-pull` / `-push` / `-compare` — the sync engines
behind the slash commands above. Common sync flags: `--dry-run`, `--verbose`,
`--force`, `--clean`, `--only-skills`, `--only-agents`, `--only-commands`; push
adds `--message`, compare `--repair`.

### Sync conflict handling

Both sync scripts track a SHA256 baseline per item in
`~/.claude/.c-bpm-library-sync`. An item changed on **both** sides since the
last sync is flagged and skipped rather than silently overwritten.

| Scenario | Pull | Push |
|----------|------|------|
| Only repo changed | Updates local | — |
| Only local changed | Updates local (repo wins) | Updates repo |
| Both changed | **CONFLICT** (skipped) | **CONFLICT** (skipped) |
| Both changed + `--force` | Repo wins | Local wins |
| No baseline (first sync) | Updates local | Updates repo |

## 4. Testing

```bash
./tests/run_tests.sh     # requires bats on PATH; equivalent to: bats tests/bash/
bats tests/bash/readme-guards.bats   # a single suite
./tests/typecheck-mods.sh            # tsc --noEmit over every mod under my/mods/
git config core.hooksPath .githooks  # once per clone: pre-push runs both
```

The suite is offline and deterministic. It covers the installer and sync
scripts (`install.bats`, `sync-dedup.bats`, `sync-only-flags.bats`,
`bpm-bootstrap.bats`, `c-bpm-cm-library-compare.bats`,
`c-bpm-hosts-inventory.bats`, `c-bpm-host-variant.bats`), drift guards over this README
(`readme-guards.bats`), content guards over the custom items
(`c-bpm-items.bats`) and the agent cleanup hook with its installation
(`c-bpm-hk-agent-cleanup-guard.bats`), the skills refresh hook (`c-bpm-hk-skills-refresh.bats`) the ask-matt-after-clear hook and the mod's line parser against real next-step lines in `tests/fixtures/next-step-lines.tsv` (`c-bpm-hk-ask-matt-after-clear.bats`) the ask-matt read guard (`c-bpm-hk-ask-matt-read-guard.bats`), and the pre-push hook and live-test helper (`guardrails.bats`).

Live checks in a real Claude session in tmux use `tests/live/tmux-claude.sh`
(start, send keys, wait for a pattern, capture, kill) instead of fixed sleeps.

## 5. Maintenance

- After editing any root script, refresh `checksums.sha256` (command in CLAUDE.md).
- No item pins a model name or version; `readme-guards.bats` and
  `c-bpm-items.bats` fail if one appears.
- When a build's `RETRO.md` finds a recurring gap in `c-bpm-cm-spec-oneshot` or
  `c-bpm-sk-gogo`, file an issue here and fix the item here, never in a
  project repo.
- The former enforcement hooks, agents, runbooks, templates and skills were removed on
  2026-10-23 in favour of the Pocock plugin; git history is the archive.

## External Skill Packs

The n8n skill pack is maintained in a <a href="https://github.com/czlonkowski/n8n-skills" target="_blank">separate repository</a>. Install it with `bcgasl --n8n`.

## License

MIT. See the `LICENSE` file.
