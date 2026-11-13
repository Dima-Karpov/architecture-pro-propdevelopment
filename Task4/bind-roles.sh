#!/usr/bin/env bash
# Task4: RoleBinding / ClusterRoleBinding по ролевой модели.
# Связь с Task1–3: viewer/devops/ИБ по доменным NS; secrets не в kube-system;
# cluster-scoped только узкий pd-cluster-reader (nodes/namespaces).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
DOMAINS=(sales housing finance data)

# Снять старые cluster-wide bindings (если остались от ранней версии Task4).
kubectl delete clusterrolebinding pd-viewers-binding pd-security-secrets --ignore-not-found

kubectl apply -f "${MANIFESTS_DIR}/02-bindings.yaml"

# Один RoleBinding × 3 роли × N доменов — без копипасты в YAML.
{
  for ns in "${DOMAINS[@]}"; do
    cat <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pd-viewers
  namespace: ${ns}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pd-viewer
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: pd-viewers
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pd-security-secrets
  namespace: ${ns}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pd-secrets-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: pd-security
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pd-devops-configurator
  namespace: ${ns}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pd-configurator
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: pd-devops
EOF
  done
} | kubectl apply -f -

echo "Done. Bindings applied (run after create-roles.sh)."
