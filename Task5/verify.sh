#!/usr/bin/env bash
# Проверка: свои пары — OK, перекрёст — timeout/fail.
set -euo pipefail

NS=pd-demo

probe() {
  local from_role=$1
  local to_svc=$2
  local expect=$3 # allow|deny
  local from_pod
  from_pod=$(kubectl -n "$NS" get pod -l "role=$from_role" -o jsonpath='{.items[0].metadata.name}')

  set +e
  out=$(kubectl -n "$NS" exec "$from_pod" -- wget -qO- --timeout=2 "http://${to_svc}" 2>&1)
  rc=$?
  set -e

  if [[ "$expect" == allow ]]; then
    if [[ $rc -eq 0 ]]; then
      echo "PASS allow  $from_role → $to_svc"
    else
      echo "FAIL allow  $from_role → $to_svc (rc=$rc) $out" >&2
      return 1
    fi
  else
    if [[ $rc -ne 0 ]]; then
      echo "PASS deny   $from_role → $to_svc"
    else
      echo "FAIL deny   $from_role → $to_svc (unexpected OK)" >&2
      return 1
    fi
  fi
}

echo "=== allowed pairs ==="
probe front-end            back-end-api-app       allow
probe back-end-api         front-end-app          allow
probe admin-front-end      admin-back-end-api-app allow
probe admin-back-end-api   admin-front-end-app    allow

echo "=== cross (must fail) ==="
probe front-end            admin-back-end-api-app deny
probe admin-front-end      back-end-api-app       deny
probe front-end            admin-front-end-app    deny
probe admin-back-end-api   back-end-api-app       deny

echo "OK: matrix matches ADR plane split"
