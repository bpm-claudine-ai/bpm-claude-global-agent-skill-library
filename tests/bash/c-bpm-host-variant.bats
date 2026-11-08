#!/usr/bin/env bats
#
# c-bpm-host-variant.bats — the next-step skill exists in two host variants
# (#195): c-bpm-sk-next-step on development hosts, c-bpm-sk-next-step-admin on
# admin hosts (my/hosts/<hostname>/next-step-admin names the host repo). Pull
# installs exactly one, push --clean never deletes the other from the repo,
# compare does not report it.
#
# Offline: each test copies the repo into a throwaway HOME as the library
# checkout and sets the host marker there, so the result does not depend on
# the machine the suite runs on.

set -u

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
ADMIN_SKILL="${REPO_ROOT}/my/skills/c-bpm-sk-next-step-admin/SKILL.md"
DEV_SKILL="${REPO_ROOT}/my/skills/c-bpm-sk-next-step/SKILL.md"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="${TEST_HOME}"
  export GIT_CONFIG_GLOBAL="${HOME}/.gitconfig" GIT_CONFIG_NOSYSTEM=1
  LIB="${HOME}/bpm-claude-global-agent-skill-library"
  mkdir -p "${LIB}" "${HOME}/.claude"
  printf '{}\n' > "${HOME}/.claude/settings.json"
  # Copy the working tree (not .git) and make it a repo of its own.
  tar -C "${REPO_ROOT}" --exclude=.git -cf - . | tar -C "${LIB}" -xf -
  rm -rf "${LIB}/my/hosts"
  mkdir -p "${LIB}/my/hosts"
  git -C "${LIB}" init -q
  git -C "${LIB}" -c user.name=t -c user.email=t@t add -A
  git -C "${LIB}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init
  # A local bare remote, so the pull and push scripts can fast-forward.
  git clone -q --bare "${LIB}" "${HOME}/origin.git"
  git -C "${LIB}" remote add origin "${HOME}/origin.git"
  git -C "${LIB}" fetch -q origin
  git -C "${LIB}" branch -q --set-upstream-to="origin/$(git -C "${LIB}" symbolic-ref --short HEAD)"
}

teardown() {
  rm -rf "${TEST_HOME}"
}

make_admin_host() {
  mkdir -p "${LIB}/my/hosts/$(hostname)"
  printf '%s\n' "${1:-BPMspaceUG/bpm-example-host}" > "${LIB}/my/hosts/$(hostname)/next-step-admin"
}

pull() { run "${LIB}/c-bpm-cm-library-pull" "$@"; }

# ------------------------------------------------------------------
# lib.sh selection
# ------------------------------------------------------------------

@test "host_skipped_item: development host skips the admin variant" {
  run bash -c 'source "$1/lib.sh"; host_skipped_item "$1"' _ "${LIB}"
  [ "$status" -eq 0 ]
  [ "$output" = "skills/c-bpm-sk-next-step-admin" ]
}

@test "host_skipped_item: admin host skips the regular variant and names its repo" {
  make_admin_host BPMspaceUG/bpm-example-host
  run bash -c 'source "$1/lib.sh"; host_skipped_item "$1"; host_admin_repo "$1"' _ "${LIB}"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "skills/c-bpm-sk-next-step" ]
  [ "${lines[1]}" = "BPMspaceUG/bpm-example-host" ]
}

@test "host_admin_repo: a marker without an owner/name line is no admin host" {
  mkdir -p "${LIB}/my/hosts/$(hostname)"
  printf '# no repo here\nnot a repo\n' > "${LIB}/my/hosts/$(hostname)/next-step-admin"
  run bash -c 'set -euo pipefail; source "$1/lib.sh"; host_skipped_item "$1"' _ "${LIB}"
  [ "$status" -eq 0 ]
  [ "$output" = "skills/c-bpm-sk-next-step-admin" ]
}

# ------------------------------------------------------------------
# pull
# ------------------------------------------------------------------

@test "pull on a development host installs c-bpm-sk-next-step only" {
  pull
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  [ -f "${HOME}/.claude/skills/c-bpm-sk-next-step/SKILL.md" ]
  [ ! -e "${HOME}/.claude/skills/c-bpm-sk-next-step-admin" ]
}

@test "pull on an admin host installs c-bpm-sk-next-step-admin only, and the completeness check passes" {
  make_admin_host
  pull
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  [ -f "${HOME}/.claude/skills/c-bpm-sk-next-step-admin/SKILL.md" ]
  [ ! -e "${HOME}/.claude/skills/c-bpm-sk-next-step" ]
  [[ "$output" == *"Host variant: admin host (host repo BPMspaceUG/bpm-example-host)"* ]]
  [[ "$output" != *"DRIFT"* ]]
}

@test "pull switches a host: the variant installed before is removed" {
  pull
  [ -d "${HOME}/.claude/skills/c-bpm-sk-next-step" ]
  make_admin_host
  pull
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  [[ "$output" == *"- skills/c-bpm-sk-next-step (other host variant, removed locally)"* ]]
  [ ! -e "${HOME}/.claude/skills/c-bpm-sk-next-step" ]
  [ -d "${HOME}/.claude/skills/c-bpm-sk-next-step-admin" ]
  ! grep -q ' skills/c-bpm-sk-next-step$' "${HOME}/.claude/.c-bpm-library-sync"
}

@test "pull --dry-run on a switching host removes nothing" {
  pull
  make_admin_host
  pull --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"(other host variant, removed locally)"* ]]
  [ -d "${HOME}/.claude/skills/c-bpm-sk-next-step" ]
}

@test "a second pull on an admin host changes nothing" {
  make_admin_host
  pull
  pull
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already up to date"* ]]
}

# ------------------------------------------------------------------
# push and compare
# ------------------------------------------------------------------

@test "push --clean --dry-run on an admin host never deletes c-bpm-sk-next-step from the repo" {
  make_admin_host
  pull
  run "${LIB}/c-bpm-cm-library-push" --clean --dry-run
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  [[ "$output" != *"skills/c-bpm-sk-next-step "* ]]
  [[ "$output" != *"skills/c-bpm-sk-next-step ("* ]]
  [ -f "${LIB}/my/skills/c-bpm-sk-next-step/SKILL.md" ]
}

@test "push --clean --dry-run on a development host never deletes c-bpm-sk-next-step-admin from the repo" {
  pull
  run "${LIB}/c-bpm-cm-library-push" --clean --dry-run
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  [[ "$output" != *"c-bpm-sk-next-step-admin"* ]]
  [ -f "${LIB}/my/skills/c-bpm-sk-next-step-admin/SKILL.md" ]
}

@test "compare on an admin host reports everything in sync" {
  make_admin_host
  pull
  run "${LIB}/c-bpm-cm-library-compare"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  [[ "$output" != *"skills/c-bpm-sk-next-step"* ]]
  [[ "$output" == *"Everything is in sync"* ]]
}

# ------------------------------------------------------------------
# content of the admin variant
# ------------------------------------------------------------------

@test "admin variant keeps both line prefixes the hook and the mod parse" {
  grep -qF '    **Robert, du bist dran:** ' "${ADMIN_SKILL}"
  grep -qF '    **Claude ist dran, du musst nichts tun:** ' "${ADMIN_SKILL}"
  grep -qF '    **Robert, du bist dran:** ' "${DEV_SKILL}"
}

@test "admin variant: its line templates never cite ask-matt and always give a Grund" {
  local tpl
  tpl="$(grep -E '^    \*\*(Robert|Claude)' "${ADMIN_SKILL}")"
  [ -n "${tpl}" ]
  ! printf '%s\n' "${tpl}" | grep -q 'ask-matt'
  printf '%s\n' "${tpl}" | grep -q 'Robert, du bist dran:\*\* .*Grund: '
}

@test "admin variant reads the host repo from the marker file the pull uses" {
  grep -qF 'my/hosts/$(hostname)/next-step-admin' "${ADMIN_SKILL}"
  grep -qF 'NEXT_STEP_ADMIN_FILE="next-step-admin"' "${REPO_ROOT}/lib.sh"
}

@test "every admin-host marker in the repo names exactly one owner/name repo" {
  local f bad=0
  for f in "${REPO_ROOT}"/my/hosts/*/next-step-admin; do
    [ -e "$f" ] || continue
    [ "$(grep -cE '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' "$f")" -eq 1 ] || { echo "bad marker: $f" >&2; bad=1; }
  done
  return "$bad"
}
