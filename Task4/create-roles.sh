#!/usr/bin/env bash
# Task4: namespaces + ClusterRole по ролевой модели.
# Связь с Task1–3: домены sales/housing/finance/data → NS;
# ПДн/secrets → только ИБ; viewer без secrets; cluster-scoped — отдельный pd-cluster-reader.
# YAML = описание ролей (как в уроке); этот скрипт — apply вокруг них.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"

kubectl apply -f "${MANIFESTS_DIR}/00-namespaces.yaml"
kubectl apply -f "${MANIFESTS_DIR}/01-clusterroles.yaml"

echo "Done. Namespaces + ClusterRoles applied (bindings → bind-roles.sh)."
