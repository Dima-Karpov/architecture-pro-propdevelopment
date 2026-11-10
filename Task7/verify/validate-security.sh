#!/usr/bin/env bash
# Labels NS = restricted; Gatekeeper Ready; templates + constraints на месте.
set -euo pipefail

fail=0

echo "=== namespace PSS restricted ==="
for key in enforce audit warn; do
  val=$(kubectl get ns audit-zone -o jsonpath="{.metadata.labels.pod-security\.kubernetes\.io/$key}" 2>/dev/null || true)
  if [[ "$val" == "restricted" ]]; then
    echo "PASS label pod-security.kubernetes.io/$key=restricted"
  else
    echo "FAIL label pod-security.kubernetes.io/$key (got='$val')" >&2
    fail=1
  fi
done

echo "=== Gatekeeper pods ==="
if kubectl get ns gatekeeper-system >/dev/null 2>&1; then
  echo "PASS gatekeeper-system ns"
else
  echo "FAIL gatekeeper-system ns" >&2
  fail=1
fi
if kubectl -n gatekeeper-system wait --for=condition=Ready pod --all --timeout=30s >/dev/null 2>&1; then
  echo "PASS Gatekeeper pods Ready"
else
  echo "FAIL Gatekeeper pods Ready" >&2
  fail=1
fi

echo "=== ConstraintTemplates ==="
for t in k8spspprivilegedcontainer k8spsphostfilesystem k8spsprunasnonroot; do
  if kubectl get constrainttemplate "$t" >/dev/null 2>&1; then
    echo "PASS template $t"
  else
    echo "FAIL template $t" >&2
    fail=1
  fi
done

echo "=== Constraints ==="
for pair in \
  "k8spspprivilegedcontainer deny-privileged" \
  "k8spsphostfilesystem deny-hostpath" \
  "k8spsprunasnonroot require-nonroot-readonly"; do
  kind=${pair%% *}
  name=${pair##* }
  if kubectl get "$kind" "$name" >/dev/null 2>&1; then
    echo "PASS constraint $name"
  else
    echo "FAIL constraint $name" >&2
    fail=1
  fi
done
if [[ $fail -ne 0 ]]; then
  echo "FAIL: security stack incomplete" >&2
  exit 1
fi
echo "OK: PSS + Gatekeeper present"
