#!/usr/bin/env bash
# Выжимка подозрительных событий из Kubernetes audit.log (NDJSON) → JSON-массив.
# Использование: bash Task6/filter-audit.sh [audit.log] [audit-extract.json]
set -euo pipefail

IN="${1:-Task6/audit.log}"
OUT="${2:-Task6/audit-extract.json}"

if [[ ! -f "$IN" ]]; then
  echo "нет файла: $IN" >&2
  exit 1
fi
command -v jq >/dev/null || { echo "нужен jq" >&2; exit 1; }

# Реальные сигнатуры simulate-incident (не шаблон jq из урока 1:1):
# - secrets: kubectl get → list/get; от SA — impersonatedUser
# - exec: verb get + URI/subresource exec (не create)
# - privileged-pod в secure-ops
# - RoleBinding escalate-binding → cluster-admin
# - delete audit-policy: в этом прогоне до API не дошёл (файла нет на хосте)
jq -s '
  map(select(
    .stage == "ResponseComplete"
    and (
      (
        .objectRef.resource == "secrets"
        and (.verb == "get" or .verb == "list")
        and (
          (.impersonatedUser.username // "") == "system:serviceaccount:secure-ops:monitoring"
          or ((.objectRef.namespace // "") == "kube-system" and .user.username == "minikube-user"
              and (.impersonatedUser.username // "") != "")
        )
      )
      or (
        (.objectRef.subresource == "exec" or ((.requestURI // "") | test("/exec")))
        and .user.username == "minikube-user"
      )
      or (
        .objectRef.resource == "pods"
        and .verb == "create"
        and (.objectRef.name // "") == "privileged-pod"
        and (.requestObject.spec.containers // [] | any(.securityContext.privileged == true))
      )
      or (
        .objectRef.resource == "rolebindings"
        and .verb == "create"
        and (
          (.objectRef.name // "") == "escalate-binding"
          or (.requestObject.roleRef.name // "") == "cluster-admin"
        )
        and (.objectRef.namespace // "") == "secure-ops"
      )
    )
  ))
' "$IN" > "$OUT"

echo "wrote $(jq 'length' "$OUT") events → $OUT"
