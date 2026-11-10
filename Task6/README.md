# Task6: Audit log (PropDevelopment)

Kubernetes Audit на Minikube → симуляция инцидента → выжимка → отчёт.  
Отчёт: [`analysis.md`](analysis.md). Выжимка: [`audit-extract.json`](audit-extract.json).

## Что здесь лежит

| Артефакт | Назначение |
| --- | --- |
| `audit-policy.yaml` | политика аудита |
| `simulate-incident.sh` | симуляция с платформы |
| `filter-audit.sh` | Bash + `jq` → `audit-extract.json` |
| `audit-extract.json` | подозрительные события |
| `analysis.md` | отчёт для ревьюера |

`audit.log` локальный (в git не коммитить, см. `*.log` в `.gitignore`).

## Порядок (корень репо)

**1. Политика на диск Minikube** (путь `/etc/ssl/certs` — не `/etc/kubernetes`)

```bash
mkdir -p ~/.minikube/files/etc/ssl/certs
cp Task6/audit-policy.yaml ~/.minikube/files/etc/ssl/certs/audit-policy.yaml
```

**2. Старт с audit**

```bash
minikube delete
minikube start \
  --extra-config=apiserver.audit-policy-file=/etc/ssl/certs/audit-policy.yaml \
  --extra-config=apiserver.audit-log-path=/var/log/audit.log \
  --memory=4000 --cpus=2
```

**3. Проверка**

```bash
minikube ssh -- sudo test -f /etc/ssl/certs/audit-policy.yaml && echo OK_POLICY
kubectl get nodes
```

**4. Симуляция**

```bash
bash Task6/simulate-incident.sh
```

**5. Найти audit.log на ноде** (в контейнере apiserver нет `cat`; `crictl cp` у minikube 1.39 нет)

```bash
minikube ssh -- 'sudo find / -name audit.log 2>/dev/null'
```

**6. Выгрузить** (`/run/containerd/.../rootfs/var/log/audit.log`)

```bash
minikube ssh -- sudo cat /run/containerd/io.containerd.runtime.v2.task/k8s.io/CID/rootfs/var/log/audit.log > Task6/audit.log
wc -l Task6/audit.log
```

**7. Фильтр**

```bash
bash Task6/filter-audit.sh Task6/audit.log Task6/audit-extract.json
```

## Связь с Task4

Secrets только у `pd-secrets-admin` в доменных NS; без `cluster-admin`. Инцидент: SA `monitoring` → попытка secrets в `kube-system`, privileged, exec в CoreDNS, RoleBinding на `cluster-admin`.
