#!/bin/bash
# Generates ExcitingCompressor.xcodeproj from project.yml, filling in the
# signing team and bundle ID prefix from .env.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/load-env.sh
load_env "$(pwd)"
require_env DEVELOPMENT_TEAM BUNDLE_ID_PREFIX

xcodegen generate --quiet "$@"
