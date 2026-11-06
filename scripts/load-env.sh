#!/bin/bash
# Sourced by the other scripts: loads KEY=value pairs from .env at the repo root.
# Variables already set in the environment win, so one-off overrides like
# `NOTARY_PROFILE=foo scripts/make-installer.sh` still work.

load_env() {
    local file="$1/.env"
    [[ -f "$file" ]] || return 0

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        line="${line#export }"
        key="${line%%=*}"
        value="${line#*=}"
        key="${key//[[:space:]]/}"
        # Strip one pair of surrounding quotes.
        if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi
        [[ -z "${!key+x}" ]] && export "$key=$value"
    done < "$file"
}

# Exits with a hint if any of the named variables is empty.
require_env() {
    local missing=()
    for name in "$@"; do
        [[ -n "${!name:-}" ]] || missing+=("$name")
    done
    if (( ${#missing[@]} )); then
        printf 'Missing %s. Copy .env.example to .env and fill it in.\n' "${missing[*]}" >&2
        exit 1
    fi
}
