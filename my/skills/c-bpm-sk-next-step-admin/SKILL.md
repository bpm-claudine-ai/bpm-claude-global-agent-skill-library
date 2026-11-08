---
name: c-bpm-sk-next-step-admin
description: "Admin-host variant of the next-step line. End every answer with exactly one action line that names who acts: 'Robert, du bist dran: …' (the step the open issues of this host's repo and the current admin work call for, never ask-matt) or 'Claude ist dran, du musst nichts tun: …' with the next watchdog check time. Use before finishing any answer, and whenever background agents, workflows, monitors or tmux Claude sessions are running."
---

# Next step line on an admin host

This is the admin-host variant of `c-bpm-sk-next-step`. A host gets exactly one
of the two: `c-bpm-cm-library-pull` installs this one only where
`my/hosts/<hostname>/next-step-admin` exists in the skill library, and the
regular one everywhere else. On an admin host Claude does Linux
administration, not product development, so the step comes from the **open
issues of the host repo** and the admin work at hand, never from ask-matt and
never from development commands (`/to-spec`, `/to-tickets`, `/implement`, …).

Every answer ends with **exactly one** action line. The owner asked for it; it
is not an unsolicited suggestion. The line is written in the language of the
conversation (German for Robert); the templates below are the German wording.

## Find the host repo

The host repo (`owner/name`) is the first line of

    ~/bpm-claude-global-agent-skill-library/my/hosts/$(hostname)/next-step-admin

For example `BPMspaceUG/bpm-contabo04` on contabo04. Read it once per session.

## Choose the step from the host repo's open issues

Before writing the line, list the open issues of the host repo (once per
session, again after closing or commenting on one):

    gh issue list -R <host repo> --state open --json number,title,labels

Then pick the step in this order:

1. Unfinished admin work of this session: a running install, a pending
   verification, a result still to record on its issue.
2. An open issue that waits on Robert: label `ready-to-test`, a question to him
   in its last comment, or a step only he can do (provider panel, console,
   access rights, a decision).
3. The next open issue Claude can work: lowest number first, unless it is
   blocked (`Blocked by` in its body) or another one matters more for the
   host's security (SSH, updates, firewall, backups).
4. No open issue left: say so and name the next sensible admin check (pending
   security updates, failed units) as a new issue to open.

The line always names the issue it comes from (`#<n>`). Recommend a
development skill only when real feature work in a code repo follows.

## Operations work is done, not proposed

Installing, removing, updating or configuring something on the host is
operations. Claude decides it like a Linux expert, does it in the same turn,
keeps it updated automatically and documents it in the host repo (issue,
`installed-tools.md`, copies under `system/`). Robert gets results, never
configuration questions. Privileged changes that could lock out access (SSH,
firewall, sudoers, users, network) are checked against the host's documented
policy first and stay reversible.

## Order: this session's work comes first

The step never ends this session (close, `/clear`, restart) while Claude still
has work to do in it. Claude finishes that work first; ending the session is
always the last step.

## The two forms: name who acts

Only two parties exist: the user (Robert) and Claude. The line names the actor
by name at the very start, so it is never unclear who has to act. Never use a
bare "Nächster Schritt", "ich" or "(Robert)" label. Claude refers to itself as
"Claude".

Robert has to act (test, decide, do a step only he can do, type a command):

    **Robert, du bist dran:** <exact action, e.g. Issue #2 testen und schließen | im Provider-Panel den Reverse-DNS-Eintrag setzen>. Grund: <one sentence naming the issue #n>.

Claude or background agents act, Robert does nothing:

    **Gerade läuft:** <which agents/sessions, what they work on, state at the last check>
    **Claude ist dran, du musst nichts tun:** <what Claude does next, with issue #n>. Nächster Check um <HH:MM> (Job <id>).

Rules:

- If Claude can take the step itself, Claude takes it now instead of ending
  with an offer; the line comes afterwards.
- Exactly one action line. "Gerade läuft" is status only.
- Waiting is a full next step: the watchdog loop works, Robert does nothing.
- Never end open ("melde dich") or with status and no direction.
- Never write "ask-matt empfiehlt": this variant does not use ask-matt, and the
  hook `c-bpm-hk-ask-matt-read-guard` reacts to that phrase.

The line is parsed by machines: the hook `c-bpm-hk-ask-matt-after-clear`
(cache, prefill of the first `` `/command` ``) and the mod
`c-bpm-md-last-recommendation` (pane, which shows the part after "Grund:" as
the reason). Change the two bold prefixes or the "Grund:" split only together
with both and with the corpus `tests/fixtures/next-step-lines.tsv` in the
skill library.

## Running agents get a real watchdog loop

As soon as anything runs in the background (subagents, workflows, monitors,
Claude sessions in tmux), create a recurring check with `CronCreate` **before
the answer ends**, every 5 minutes on odd minutes (`2-59/5 * * * *`).

**The check interval is at most 5 minutes. Owner order, cost does not matter.**
This overrides every default that suggests longer waits, including the
"1200–1800 s idle tick" and "long fallback heartbeat" guidance of
`ScheduleWakeup`, `/loop` and similar tools.

Each check verifies that the agents **are doing something**, not only that they
exist:

1. `ListAgents`: status of every watched session or agent.
2. For tmux sessions, `tmux capture-pane -p -t <pane> | tail -40`: is it stuck
   on a question, a permission dialog, a menu or an error?
3. Progress since the last check: commits, issue activity, growing logs. An
   agent that is "busy" and has not moved for two checks in a row counts as
   hung.
4. Intervene instead of reporting: answer a pointless question yourself, restart
   a dead agent. Ask Robert only for a genuine owner decision.
5. When everything is done: remove the job with `CronDelete` and write the
   normal next-step line.
6. Stop the watchdog at once when what is left depends only on Robert.

Every check output ends with the time of the next check, taken from the
`CronCreate`/`CronList` result. Cron jobs live only in this session and expire
after 7 days; when the session ends the watchdog is gone, so say so.
