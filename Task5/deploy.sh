#!/usr/bin/env bash
# Деплой 4 nginx + NetworkPolicy в namespace pd-demo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
NS=pd-demo

# kindnet политики принимает, но не режет. Calico после start поднимается ~1–2 мин.
if kubectl get ds -n kube-system kindnet >/dev/null 2>&1; then
  cat <<'EOF' >&2
[!] CNI = kindnet → NetworkPolicy не enforce'ится.
    minikube delete && minikube start --cni=calico --memory=4000 --cpus=2
EOF
  exit 1
fi

if ! kubectl get ds -n kube-system calico-node >/dev/null 2>&1 \
  && ! kubectl get ds -n calico-system calico-node >/dev/null 2>&1; then
  cat <<'EOF' >&2
[!] Calico не найден. Запусти Minikube с --cni=calico.
EOF
  exit 1
fi

echo "Waiting for calico-node..."
kubectl -n kube-system rollout status ds/calico-node --timeout=180s 2>/dev/null \
  || kubectl -n calico-system rollout status ds/calico-node --timeout=180s

kubectl apply -f "$ROOT/manifests/00-namespace.yaml"
kubectl apply -f "$ROOT/manifests/01-workloads.yaml"
kubectl apply -f "$ROOT/manifests/default-deny.yaml"
kubectl apply -f "$ROOT/manifests/non-admin-api-allow.yaml"
kubectl apply -f "$ROOT/manifests/admin-api-allow.yaml"

kubectl -n "$NS" rollout status deploy/front-end-app --timeout=120s
kubectl -n "$NS" rollout status deploy/back-end-api-app --timeout=120s
kubectl -n "$NS" rollout status deploy/admin-front-end-app --timeout=120s
kubectl -n "$NS" rollout status deploy/admin-back-end-api-app --timeout=120s

echo "OK: workloads + NetworkPolicy in $NS"
kubectl -n "$NS" get deploy,svc,networkpolicy
