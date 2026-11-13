#!/usr/bin/env bash
# insecure → deny; secure → allow (server dry-run).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSECURE="$ROOT/insecure-manifests"
SECURE="$ROOT/secure-manifests"
fail=0

expect_deny() {
  local file=$1
  local out rc
  set +e
  out=$(kubectl apply --dry-run=server -f "$file" 2>&1)
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "PASS deny  $(basename "$file")"
  else
    echo "FAIL deny  $(basename "$file") (unexpected OK)" >&2
    fail=1
  fi
}

expect_allow() {
  local file=$1
  local out rc
  set +e
  out=$(kubectl apply --dry-run=server -f "$file" 2>&1)
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "PASS allow $(basename "$file")"
  else
    echo "FAIL allow $(basename "$file") (rc=$rc) $out" >&2
    fail=1
  fi
}

echo "=== insecure (must fail) ==="
expect_deny "$INSECURE/01-privileged-pod.yaml"
expect_deny "$INSECURE/02-hostpath-pod.yaml"
expect_deny "$INSECURE/03-root-user-pod.yaml"

echo "=== secure (must pass) ==="
expect_allow "$SECURE/01-secure.yaml"
expect_allow "$SECURE/02-secure.yaml"
expect_allow "$SECURE/03-secure.yaml"

if [[ $fail -ne 0 ]]; then
  echo "FAIL: admission checks" >&2
  exit 1
fi
echo "OK: admission matches PSS + Gatekeeper"
