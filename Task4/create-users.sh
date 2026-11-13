#!/usr/bin/env bash
# Task4: клиентские сертификаты + kubeconfig.
# Связь с Task1–3: домены → NS; ПДн/secrets → только ИБ (pd-security);
# least privilege — группа в поле O= сертификата для RBAC.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/certs"
CA_CRT="${HOME}/.minikube/ca.crt"
CA_KEY="${HOME}/.minikube/ca.key"
CLUSTER_NAME="${CLUSTER_NAME:-minikube}"

if [[ ! -f "${CA_CRT}" || ! -f "${CA_KEY}" ]]; then
  echo "Minikube CA not found at ${CA_CRT} / ${CA_KEY}. Run: minikube start" >&2
  exit 1
fi

mkdir -p "${CERTS_DIR}"

# user:group
USERS=(
  "alice-analyst:pd-viewers"
  "bob-devops:pd-devops"
  "carol-security:pd-security"
)

create_user() {
  local user="$1"
  local group="$2"
  local key="${CERTS_DIR}/${user}.key"
  local csr="${CERTS_DIR}/${user}.csr"
  local crt="${CERTS_DIR}/${user}.crt"

  if [[ ! -f "${key}" ]]; then
    openssl genrsa -out "${key}" 2048
  fi

  openssl req -new -key "${key}" -out "${csr}" \
    -subj "/CN=${user}/O=${group}"

  openssl x509 -req -in "${csr}" \
    -CA "${CA_CRT}" \
    -CAkey "${CA_KEY}" \
    -CAcreateserial \
    -out "${crt}" \
    -days 365

  rm -f "${csr}"

  kubectl config set-credentials "${user}" \
    --client-certificate="${crt}" \
    --client-key="${key}"

  kubectl config set-context "${user}@${CLUSTER_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --user="${user}"

  echo "OK: ${user} (O=${group}) → context ${user}@${CLUSTER_NAME}"
}

for entry in "${USERS[@]}"; do
  create_user "${entry%%:*}" "${entry##*:}"
done

echo "Done. Certs in ${CERTS_DIR} (do not commit *.key/*.crt)."
