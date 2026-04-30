#!/usr/bin/env bash
#
# Verify the prerequisites for running the release pipeline. Checks
# only — never installs anything. Emits a punch list of every missing
# item with the README's remediation command, then exits non-zero if
# anything is missing.
#
# Designed to run twice: standalone before committing to a release
# attempt, and (cheaply) as the first step of release-build.sh so the
# build fails fast on a misconfigured machine instead of mid-toolchain.

set -euo pipefail
IFS=$'\n\t'
trap 'echo "release-doctor: error on line $LINENO" >&2' ERR

readonly TAP_DIR="${MODALISER_TAP_DIR:-$HOME/Development/homebrew-taps}"

failed=0

mark_pass() {
  echo "  ✓ $*"
}

mark_fail() {
  echo "  ✗ $*"
  failed=1
}

remediation() {
  echo "      remediation: $*"
}

check_xcode_select() {
  if ! xcode-select -p >/dev/null 2>&1; then
    mark_fail "xcode-select: no developer dir set"
    remediation "xcode-select --install (or sudo xcode-select -s /Applications/Xcode.app)"
    return
  fi
  mark_pass "xcode-select: $(xcode-select -p)"
}

check_swift() {
  if ! command -v swift >/dev/null 2>&1; then
    mark_fail "swift: not on PATH"
    remediation "install Xcode or Command Line Tools (xcode-select --install)"
    return
  fi
  local version
  version="$(swift --version 2>/dev/null | head -n1 || echo unknown)"
  mark_pass "swift: $version"
}

check_codesign() {
  if ! command -v codesign >/dev/null 2>&1; then
    mark_fail "codesign: not on PATH"
    remediation "install Xcode Command Line Tools (xcode-select --install)"
    return
  fi
  mark_pass "codesign: available"
}

check_icon_tools() {
  local missing=()
  command -v sips >/dev/null 2>&1 || missing+=("sips")
  command -v iconutil >/dev/null 2>&1 || missing+=("iconutil")
  if (( ${#missing[@]} > 0 )); then
    mark_fail "icon tools: missing ${missing[*]}"
    remediation "install Xcode Command Line Tools (xcode-select --install)"
    return
  fi
  mark_pass "icon tools: sips, iconutil"
}

check_gh_auth() {
  if ! command -v gh >/dev/null 2>&1; then
    mark_fail "gh: not installed"
    remediation "brew install gh && gh auth login"
    return
  fi
  if gh auth status >/dev/null 2>&1; then
    mark_pass "gh: authenticated"
  else
    mark_fail "gh: not authenticated"
    remediation "gh auth login"
  fi
}

check_tap_dir() {
  if [[ ! -d "$TAP_DIR/.git" ]]; then
    mark_fail "tap clone: not a git repo at $TAP_DIR"
    remediation "git clone <your-tap-repo> $TAP_DIR (or set MODALISER_TAP_DIR)"
    return
  fi
  mark_pass "tap clone: $TAP_DIR"
}

main() {
  echo "release-doctor: checking release prerequisites"
  echo

  check_xcode_select
  check_swift
  check_codesign
  check_icon_tools
  check_gh_auth
  check_tap_dir

  echo
  if (( failed == 0 )); then
    echo "release-doctor: all prerequisites met"
    exit 0
  fi
  echo "release-doctor: missing prerequisites — fix the items marked above" >&2
  exit 1
}

main "$@"
