#!/usr/bin/env bash
#
# lib.sh - Shared functions for bcgasl scripts
#
# Source this file in scripts:
#   source "$(dirname "$0")/lib.sh"
#
# Requires: VERBOSE variable to be set (0 or 1) before calling log_verbose

# Current version
BCGASL_VERSION="1.0.1"

# Naming convention: c-{ORG_PREFIX}-{type}-{name}
# shellcheck disable=SC2034
ITEM_PREFIX="c"
# shellcheck disable=SC2034
ORG_PREFIX="bpm"
# Type prefixes for glob patterns
# shellcheck disable=SC2034
SK_PREFIX="${ITEM_PREFIX}-${ORG_PREFIX}-sk"  # c-bpm-sk
# shellcheck disable=SC2034
CM_PREFIX="${ITEM_PREFIX}-${ORG_PREFIX}-cm"  # c-bpm-cm
# shellcheck disable=SC2034
AG_PREFIX="${ITEM_PREFIX}-${ORG_PREFIX}-ag"  # c-bpm-ag
# shellcheck disable=SC2034
RB_PREFIX="${ITEM_PREFIX}-${ORG_PREFIX}-rb"  # c-bpm-rb

# Map category name to its type prefix
# Usage: prefix=$(get_category_prefix "skills")
get_category_prefix() {
  case "$1" in
    skills)   echo "$SK_PREFIX" ;;
    commands) echo "$CM_PREFIX" ;;
    agents)   echo "$AG_PREFIX" ;;
    runbooks) echo "$RB_PREFIX" ;;
  esac
}

# Trusted domains for downloads (security: only allow known hosts)
TRUSTED_DOMAINS=("github.com" "raw.githubusercontent.com")

# Repository URLs (exported for use by sourcing scripts)
# shellcheck disable=SC2034
REPO_TARBALL="https://github.com/BPMspaceUG/bpm-claude-global-agent-skill-library/archive/refs/tags/v${BCGASL_VERSION}.tar.gz"
# shellcheck disable=SC2034
N8N_TARBALL="https://github.com/czlonkowski/n8n-skills/archive/main.tar.gz"
# shellcheck disable=SC2034
BCGASL_URL="https://raw.githubusercontent.com/BPMspaceUG/bpm-claude-global-agent-skill-library/v${BCGASL_VERSION}/bcgasl"

# Checksums file URL
# shellcheck disable=SC2034
CHECKSUMS_URL="https://raw.githubusercontent.com/BPMspaceUG/bpm-claude-global-agent-skill-library/main/checksums.sha256"

# Expected checksum for current version tarball
# shellcheck disable=SC2034
REPO_TARBALL_CHECKSUM="babc86aa3d8e8fdf65006371b54f61166abe72144d818ba6263e803c3e7e9546"

# Extracted directory name for the tarball
# shellcheck disable=SC2034
EXTRACTED_DIR_NAME="bpm-claude-global-agent-skill-library-${BCGASL_VERSION}"

# Security: Validate URL against trusted domains
# Usage: validate_url "https://example.com/file"
# Returns: 0 if valid, 1 if invalid
validate_url() {
  local url="$1"
  local host

  # Validate URL is not empty
  if [[ -z "$url" ]]; then
    echo "ERROR: Empty URL provided" >&2
    return 1
  fi

  # Require HTTPS
  if [[ ! "$url" =~ ^https:// ]]; then
    echo "ERROR: URL must use HTTPS: $url" >&2
    return 1
  fi

  # Extract host from URL
  if [[ "$url" =~ ^https://([^/]+)/ ]]; then
    host="${BASH_REMATCH[1]}"
  else
    echo "ERROR: Invalid URL format: $url" >&2
    return 1
  fi

  # Check if host is in trusted domains
  for domain in "${TRUSTED_DOMAINS[@]}"; do
    if [[ "$host" == "$domain" ]]; then
      return 0
    fi
  done

  echo "ERROR: Untrusted domain '$host' in URL: $url" >&2
  echo "Trusted domains: ${TRUSTED_DOMAINS[*]}" >&2
  return 1
}

# Security: Validate path to prevent directory traversal
# Usage: validated_path=$(validate_path "/some/path")
# Returns: validated path or exits with error
# Note: This validates but does not sanitize - it rejects unsafe paths
validate_path() {
  local path="$1"

  # Check for empty path
  if [[ -z "$path" ]]; then
    echo "ERROR: Empty path provided" >&2
    return 1
  fi

  # Reject directory traversal attempts
  if [[ "$path" == *".."* ]]; then
    echo "ERROR: Path contains '..' (directory traversal): $path" >&2
    return 1
  fi

  # Check for null bytes (common injection technique)
  if [[ "$path" == *$'\0'* ]]; then
    echo "ERROR: Path contains null bytes: $path" >&2
    return 1
  fi

  echo "$path"
}

# Alias for backward compatibility
sanitize_path() {
  validate_path "$@"
}

# Security: Validate filename to prevent injection
# Usage: validated=$(validate_filename "myfile.txt")
# Returns: validated filename or exits with error
# Note: This validates but does not sanitize - it rejects unsafe filenames
validate_filename() {
  local filename="$1"

  # Check for empty filename
  if [[ -z "$filename" ]]; then
    echo "ERROR: Empty filename provided" >&2
    return 1
  fi

  # Reject if contains path separators
  if [[ "$filename" == *"/"* ]] || [[ "$filename" == *"\\"* ]]; then
    echo "ERROR: Filename contains path separator: $filename" >&2
    return 1
  fi

  # Reject directory traversal
  if [[ "$filename" == ".." ]] || [[ "$filename" == "." ]]; then
    echo "ERROR: Invalid filename: $filename" >&2
    return 1
  fi

  # Reject filenames starting with dash (could be interpreted as options)
  if [[ "$filename" == -* ]]; then
    echo "ERROR: Filename cannot start with dash: $filename" >&2
    return 1
  fi

  echo "$filename"
}

# Alias for backward compatibility
sanitize_filename() {
  validate_filename "$@"
}

# Verbose logging helper
# Usage: log_verbose "message"
# Requires: VERBOSE variable to be set (0 or 1)
log_verbose() {
  if [[ "${VERBOSE:-0}" -eq 1 ]]; then
    echo "[DEBUG] $*" >&2
  fi
}

# Compute SHA256 checksum of a file
# Usage: checksum=$(compute_sha256 "/path/to/file")
compute_sha256() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "ERROR: File not found for checksum: $file" >&2
    return 1
  fi

  # Use sha256sum (Linux) or shasum (macOS)
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | cut -d' ' -f1
  else
    echo "ERROR: No sha256sum or shasum command found" >&2
    return 1
  fi
}

# Verify file checksum against expected value
# Usage: verify_checksum "/path/to/file" "expected_sha256"
# Returns: 0 if match, 1 if mismatch
verify_checksum() {
  local file="$1"
  local expected="$2"

  local actual
  actual=$(compute_sha256 "$file") || return 1

  if [[ "$actual" == "$expected" ]]; then
    log_verbose "Checksum verified: $file"
    return 0
  else
    echo "ERROR: Checksum mismatch for $file" >&2
    echo "  Expected: $expected" >&2
    echo "  Actual:   $actual" >&2
    return 1
  fi
}

# Download and verify a file with optional checksum
# Usage: download_with_checksum "url" "/path/to/output" ["expected_sha256"]
# Returns: 0 on success, 1 on failure
download_with_checksum() {
  local url="$1"
  local output="$2"
  local expected_checksum="${3:-}"

  # Validate URL
  validate_url "$url" || return 1

  # Download
  log_verbose "Downloading: $url"
  if ! curl -fsSL "$url" -o "$output"; then
    echo "ERROR: Failed to download: $url" >&2
    return 1
  fi

  # Verify file exists and is not empty
  if [[ ! -s "$output" ]]; then
    echo "ERROR: Downloaded file is empty: $output" >&2
    rm -f "$output"
    return 1
  fi

  # Verify checksum if provided
  if [[ -n "$expected_checksum" ]]; then
    if ! verify_checksum "$output" "$expected_checksum"; then
      rm -f "$output"
      return 1
    fi
  fi

  return 0
}

# Load checksums from a checksums file
# Usage: load_checksums "/path/to/checksums.sha256"
# Sets: LOADED_CHECKSUMS associative array (filename -> checksum)
declare -A LOADED_CHECKSUMS
load_checksums() {
  local checksums_file="$1"
  LOADED_CHECKSUMS=()

  if [[ ! -f "$checksums_file" ]]; then
    log_verbose "No checksums file found: $checksums_file"
    return 0
  fi

  while IFS=' ' read -r checksum filename; do
    # Skip empty lines and comments
    [[ -z "$checksum" || "$checksum" == "#"* ]] && continue
    # Remove leading ./ or * from filename (sha256sum formats vary)
    filename="${filename#./}"
    filename="${filename#\*}"
    LOADED_CHECKSUMS["$filename"]="$checksum"
    log_verbose "Loaded checksum for $filename: $checksum"
  done < "$checksums_file"

  log_verbose "Loaded ${#LOADED_CHECKSUMS[@]} checksums"
  return 0
}

# Get checksum for a file from loaded checksums
# Usage: checksum=$(get_loaded_checksum "filename")
# Returns: checksum or empty string if not found
get_loaded_checksum() {
  local filename="$1"
  echo "${LOADED_CHECKSUMS[$filename]:-}"
}

# Determine the target directory for Claude configuration
# Usage: target=$(get_target_dir)
# Checks which directory Claude Code actively uses (by settings.json presence)
get_target_dir() {
  if [[ -f "$HOME/.claude/settings.json" ]]; then
    echo "$HOME/.claude"
  elif [[ -f "$HOME/.config/claude/settings.json" ]]; then
    echo "$HOME/.config/claude"
  elif [[ -d "$HOME/.claude" ]]; then
    echo "$HOME/.claude"
  elif [[ -d "$HOME/.config/claude" ]]; then
    echo "$HOME/.config/claude"
  else
    echo "$HOME/.claude"
  fi
}

# Create a secure temporary directory
# Usage: tmp_dir=$(create_secure_tmpdir)
# Caller is responsible for cleanup: trap 'rm -rf "$tmp_dir"' EXIT
create_secure_tmpdir() {
  local tmp_dir
  tmp_dir="$(mktemp -d)" || {
    echo "ERROR: Failed to create temporary directory" >&2
    return 1
  }

  # Ensure only owner can access
  chmod 700 "$tmp_dir" || {
    rm -rf "$tmp_dir"
    echo "ERROR: Failed to set permissions on temporary directory" >&2
    return 1
  }

  echo "$tmp_dir"
}

# Download file with validation
# Usage: download_file "https://url" "/path/to/output"
# Returns: 0 on success, 1 on failure
download_file() {
  local url="$1"
  local output="$2"

  # Validate URL
  validate_url "$url" || return 1

  # Download with curl
  log_verbose "Downloading: $url -> $output"
  if ! curl -fsSL "$url" -o "$output"; then
    echo "ERROR: Failed to download: $url" >&2
    return 1
  fi

  # Verify file was created and is not empty
  if [[ ! -s "$output" ]]; then
    echo "ERROR: Downloaded file is empty: $output" >&2
    rm -f "$output"
    return 1
  fi

  return 0
}

# Download and extract tarball with validation
# Usage: download_and_extract "https://url" "/path/to/tmpdir" "expected-dir-name"
# Returns: 0 on success, 1 on failure
download_and_extract() {
  local url="$1"
  local tmp_dir="$2"
  local expected_dir="$3"

  # Validate URL
  validate_url "$url" || return 1

  # Download and extract
  log_verbose "Downloading and extracting: $url"
  if ! curl -fsSL "$url" | tar -xz -C "$tmp_dir"; then
    echo "ERROR: Failed to download or extract: $url" >&2
    return 1
  fi

  # Validate extracted directory exists
  if [[ ! -d "$tmp_dir/$expected_dir" ]]; then
    echo "ERROR: Expected directory not found after extraction: $expected_dir" >&2
    return 1
  fi

  log_verbose "Extracted to: $tmp_dir/$expected_dir"
  return 0
}

# Validate directory name is in allowed list
# Usage: validate_dir_name "agents" agents skills runbooks templates
# Returns: 0 if valid, 1 if invalid
validate_dir_name() {
  local dir="$1"
  shift
  local allowed=("$@")

  # Check for empty
  if [[ -z "$dir" ]]; then
    echo "ERROR: Empty directory name" >&2
    return 1
  fi

  # Check against allowed list
  for allowed_dir in "${allowed[@]}"; do
    if [[ "$dir" == "$allowed_dir" ]]; then
      return 0
    fi
  done

  echo "ERROR: Directory '$dir' not in allowed list: ${allowed[*]}" >&2
  return 1
}

# Validate extracted tarball directory name matches expected pattern
# Usage: validate_extracted_dir "repo-name-main" "repo-name"
# Returns: 0 if valid, 1 if invalid
validate_extracted_dir() {
  local actual="$1"
  local expected_prefix="$2"

  # Check for directory traversal or absolute paths
  if [[ "$actual" == *".."* ]] || [[ "$actual" == /* ]]; then
    echo "ERROR: Invalid extracted directory name: $actual" >&2
    return 1
  fi

  # Check it starts with expected prefix
  if [[ ! "$actual" =~ ^${expected_prefix} ]]; then
    echo "ERROR: Extracted directory '$actual' does not match expected pattern '$expected_prefix*'" >&2
    return 1
  fi

  return 0
}

# Host variants (#195). The next-step line exists in two variants, and a host
# installs exactly one of them:
#   c-bpm-sk-next-step        development hosts (step chosen via ask-matt), default
#   c-bpm-sk-next-step-admin  admin hosts (step from the host repo's open issues)
# A host is an admin host when my/hosts/<hostname>/next-step-admin exists; its
# first matching line names the host repo as owner/name. Pull, push and compare
# all skip the variant this host does not use, so a pull never installs it and a
# push --clean never deletes it from the repo.
NEXT_STEP_ADMIN_FILE="next-step-admin"

# Print the host repo (owner/name) of an admin host, nothing otherwise.
# Usage: host_admin_repo "/path/to/repo"
host_admin_repo() {
  local f
  f="$1/my/hosts/$(hostname)/$NEXT_STEP_ADMIN_FILE"
  [[ -f "$f" ]] || return 0
  grep -m1 -E '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' "$f" || true
}

# Print the item key (category/name) that this host does not install.
# Usage: host_skipped_item "/path/to/repo"
host_skipped_item() {
  if [[ -n "$(host_admin_repo "$1")" ]]; then
    echo "skills/${ITEM_PREFIX}-${ORG_PREFIX}-sk-next-step"
  else
    echo "skills/${ITEM_PREFIX}-${ORG_PREFIX}-sk-next-step-admin"
  fi
}

# True when this host does not install the item.
# Usage: is_host_skipped "/path/to/repo" "skills/c-bpm-sk-next-step"
is_host_skipped() {
  [[ "$2" == "$(host_skipped_item "$1")" ]]
}

# Write host inventory to my/hosts/<HOSTNAME>/
# Records which c-bpm items are installed on this host
# Usage: write_host_inventory "/path/to/repo" "/path/to/claude-dir"
write_host_inventory() {
  local repo_dir="$1"
  local claude_dir="$2"
  local host_name
  host_name="$(hostname)"
  local host_dir="$repo_dir/my/hosts/$host_name"

  mkdir -p "$host_dir"

  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # One file per category. A file is rewritten only when its item list
  # changed, so a routine pull does not leave a timestamp-only diff behind.
  local category file items
  for category in skills commands agents; do
    file="$host_dir/$category.txt"
    items=""
    if [[ -d "$claude_dir/$category" ]]; then
      items="$({ ls -1 "$claude_dir/$category/" 2>/dev/null | grep "^${ITEM_PREFIX}-${ORG_PREFIX}-" || true; } | sort)"
    fi
    if [[ -f "$file" ]] && [[ "$(grep -v '^#' "$file" || true)" == "$items" ]]; then
      continue
    fi
    {
      echo "# Host: $host_name"
      echo "# Updated: $ts"
      echo "# Category: $category"
      echo "#"
      [[ -z "$items" ]] || printf '%s\n' "$items"
    } > "$file"
  done

  log_verbose "Host inventory written to $host_dir"
}

# --- Sync state management (shared between pull/push) ---
# Requires: DRY_RUN variable to be set (0 or 1) before calling save_sync_state

declare -A SYNC_STATE

# Compute a deterministic hash for a file or directory
# Usage: hash=$(compute_item_hash "/path/to/item")
compute_item_hash() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1)
  elif [[ -f "$path" ]]; then
    sha256sum "$path" | cut -d' ' -f1
  else
    echo ""
  fi
}

# Load sync state from file into SYNC_STATE associative array
# Usage: load_sync_state "/path/to/sync-file"
load_sync_state() {
  local sync_file="$1"
  SYNC_STATE=()
  [[ -f "$sync_file" ]] || return 0
  while IFS=' ' read -r hash key; do
    [[ -z "$hash" || "$hash" == "#"* ]] && continue
    SYNC_STATE["$key"]="$hash"
  done < "$sync_file"
  log_verbose "Loaded ${#SYNC_STATE[@]} sync baselines"
}

# Get the stored hash for a sync key
# Usage: hash=$(get_sync_hash "category/item_name")
get_sync_hash() {
  echo "${SYNC_STATE[$1]:-}"
}

# Set the hash for a sync key
# Usage: set_sync_hash "category/item_name" "hash_value"
set_sync_hash() {
  SYNC_STATE["$1"]="$2"
}

# Save sync state to file (skips if DRY_RUN=1)
# Usage: save_sync_state "/path/to/sync-file"
# Requires: DRY_RUN variable
save_sync_state() {
  local sync_file="$1"
  [[ "${DRY_RUN:-0}" -eq 1 ]] && return 0
  : > "$sync_file"
  for key in $(echo "${!SYNC_STATE[@]}" | tr ' ' '\n' | sort); do
    echo "${SYNC_STATE[$key]} $key" >> "$sync_file"
  done
  log_verbose "Saved ${#SYNC_STATE[@]} sync baselines"
}

# Prune sync state entries where the source item no longer exists
# Usage: prune_sync_state "/path/to/source/dir"
prune_sync_state() {
  local source_dir="$1"
  local pruned=0
  for key in "${!SYNC_STATE[@]}"; do
    local category="${key%%/*}"
    local item_name="${key#*/}"
    local source_path="$source_dir/$key"
    # Skills are directories, others are files
    if [[ "$category" == "skills" ]]; then
      [[ -d "$source_path" ]] && continue
    else
      [[ -f "$source_path" ]] && continue
    fi
    unset 'SYNC_STATE[$key]'
    log_verbose "Pruned stale sync entry: $key"
    ((pruned++)) || true
  done
  [[ "$pruned" -gt 0 ]] && echo "Pruned $pruned stale sync entries" || true
}

# --- End sync state ---

# Remove the skill-rules.json that older versions of c-bpm-cm-library-pull
# generated. Nothing reads it any more. A skill-rules.json written by someone
# else (no "Auto-generated by c-bpm-cm-library-pull" marker) is left alone.
# Usage: remove_legacy_skill_rules "/path/to/claude-dir"
remove_legacy_skill_rules() {
  local rules_file="$1/skills/skill-rules.json"
  [[ -f "$rules_file" ]] || return 0
  grep -q 'Auto-generated by c-bpm-cm-library-pull' "$rules_file" 2>/dev/null || return 0
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[dry-run] Would remove legacy $rules_file"
  else
    rm -f "$rules_file"
    echo "Removed legacy $rules_file"
  fi
}

# Install the library's hooks: copy my/hooks/c-bpm-hk-*.sh to <claude-dir>/hooks/
# and merge my/hooks/c-bpm-hooks.json into <claude-dir>/settings.json (created
# when missing) and into ~/.config/claude/settings.json when that file exists.
# Idempotent: every existing hook whose command names a c-bpm-hk- script or the
# legacy agent-cleanup-guard.sh is removed first, then the fragment is added.
# Usage: install_c_bpm_hooks "/path/to/repo" "/path/to/claude-dir"
install_c_bpm_hooks() {
  local repo_dir="$1" claude_dir="$2"
  local fragment="$repo_dir/my/hooks/c-bpm-hooks.json"
  [[ -f "$fragment" ]] || return 0

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "[dry-run] Would install c-bpm hooks from $fragment"
    return 0
  fi

  command -v jq >/dev/null 2>&1 || echo "WARNING: jq is not installed; the agent cleanup hook can stop teammates without it, but cannot list running agents at turn end." >&2

  # The fragment's commands point at ~/.claude/hooks/, so the scripts always
  # land there, whatever the settings target dir is.
  local hooks_dir="$HOME/.claude/hooks"
  mkdir -p "$hooks_dir"
  local src
  for src in "$repo_dir"/my/hooks/c-bpm-hk-*.sh; do
    [[ -f "$src" ]] || continue
    install -m 0755 "$src" "$hooks_dir/$(basename "$src")"
  done
  rm -f "$hooks_dir/agent-cleanup-guard.sh"

  local settings=("$claude_dir/settings.json")
  [[ -f "$HOME/.config/claude/settings.json" ]] && settings+=("$HOME/.config/claude/settings.json")
  local f
  for f in "${settings[@]}"; do
    [[ -f "$f" ]] || printf '{}\n' > "$f"
    python3 -I - "$f" "$fragment" <<'PYMERGE' || { echo "ERROR: could not register hooks in $f" >&2; return 1; }
import json, sys
path, frag_path = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    text = fh.read().strip()
settings = json.loads(text) if text else {}
fragment = json.load(open(frag_path, encoding="utf-8"))
ours = ("c-bpm-hk-", "agent-cleanup-guard.sh")
hooks = settings.setdefault("hooks", {})
for event in list(hooks):
    kept = []
    for entry in hooks[event]:
        entry["hooks"] = [h for h in entry.get("hooks", []) if not any(o in h.get("command", "") for o in ours)]
        if entry["hooks"]:
            kept.append(entry)
    if kept:
        hooks[event] = kept
    else:
        del hooks[event]
for event, entries in fragment.items():
    hooks.setdefault(event, []).extend(entries)
import os, tempfile
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), prefix=".settings.", suffix=".json")
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    json.dump(settings, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
if os.path.exists(path):
    os.chmod(tmp, os.stat(path).st_mode & 0o777)
os.replace(tmp, path)
PYMERGE
    echo "Registered c-bpm hooks in $f"
  done
}

# Check if a command exists
# Usage: command_exists "curl"
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Ensure required commands are available
# Usage: require_commands "curl" "tar" "diff"
require_commands() {
  local missing=()
  for cmd in "$@"; do
    if ! command_exists "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Required commands not found: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
