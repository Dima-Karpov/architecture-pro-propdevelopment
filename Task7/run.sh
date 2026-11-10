#!/usr/bin/env bash
# Полный прогон Task7: NS → Gatekeeper → constraints → insecure deny / secure allow → verify.
# Из корня репо: bash Task7/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
GK_URL="${GATEKEEPER_URL:-https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.17.1/deploy/gatekeeper.yaml}"

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "FAIL: нет кластера. Сначала: minikube start --memory=4000 --cpus=2" >&2
  exit 1
fi

echo "=== 1. namespace audit-zone (PSS restricted) ==="
kubectl apply -f "$ROOT/01-create-namespace.yaml"
kubectl get ns audit-zone --show-labels

echo "=== 2. Gatekeeper ==="
kubectl apply -f "$GK_URL"
kubectl -n gatekeeper-system rollout status deploy/gatekeeper-controller-manager --timeout=180s
kubectl -n gatekeeper-system get pods

echo "=== 3. ConstraintTemplates + Constraints ==="
kubectl apply -f "$ROOT/gatekeeper/constraint-templates/"
# CRD kind'ов появляются не мгновенно
for i in 1 2 3 4 5 6 7 8 9 10; do
  if kubectl get crd k8spspprivilegedcontainers.constraints.gatekeeper.sh >/dev/null 2>&1 \
    && kubectl get crd k8spsphostfilesystems.constraints.gatekeeper.sh >/dev/null 2>&1 \
    && kubectl get crd k8spsprunasnonroots.constraints.gatekeeper.sh >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
kubectl apply -f "$ROOT/gatekeeper/constraints/"
kubectl get constrainttemplate
kubectl get constraints -A

echo "=== 4. insecure (ожидаем deny) ==="
for f in "$ROOT"/insecure-manifests/*.yaml; do
  set +e
  out=$(kubectl apply -f "$f" 2>&1)
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "PASS deny  $(basename "$f")"
  else
    echo "FAIL deny  $(basename "$f") (unexpected OK)" >&2
    echo "$out" >&2
    exit 1
  fi
done

echo "=== 5. secure (ожидаем allow) ==="
kubectl apply -f "$ROOT/secure-manifests/"
kubectl -n audit-zone get pods

echo "=== 6. verify ==="
bash "$ROOT/verify/validate-security.sh"
bash "$ROOT/verify/verify-admission.sh"

echo "=== 7. cleanup secure pods ==="
kubectl delete -f "$ROOT/secure-manifests/" --ignore-not-found

echo "OK: Task7 run complete"
