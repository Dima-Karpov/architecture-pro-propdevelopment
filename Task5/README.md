# Task5: NetworkPolicy (PropDevelopment)

Микросегментация east-west в одном namespace `pd-demo`: клиентская пара отдельно от админской.  
Решение и «почему так» — ADR [`docs/adr/0001-network-plane-split.md`](docs/adr/0001-network-plane-split.md).

## Матрица

| Источник → цель | `back-end-api` | `front-end` | `admin-back-end-api` | `admin-front-end` |
| --- | :---: | :---: | :---: | :---: |
| `front-end` | ✓ | — | ✗ | ✗ |
| `back-end-api` | — | ✓ | ✗ | ✗ |
| `admin-front-end` | ✗ | ✗ | ✓ | — |
| `admin-back-end-api` | ✗ | ✗ | — | ✓ |

## Что здесь лежит

| Артефакт                               | Назначение                                 |
| -------------------------------------- | ------------------------------------------ |
| `manifests/00-namespace.yaml`          | NS `pd-demo`                               |
| `manifests/01-workloads.yaml`          | 4× nginx Deployment+Service, labels `role` |
| `manifests/default-deny.yaml`          | default-deny + DNS                         |
| `manifests/non-admin-api-allow.yaml`   | front ↔ api (имя как в задании)            |
| `manifests/admin-api-allow.yaml`       | admin-front ↔ admin-api                    |
| `docs/adr/0001-network-plane-split.md` | ADR: что/как разделяем                     |
| `deploy.sh` / `verify.sh`              | apply + wget-матрица                       |

## CNI

Без Calico политики **создаются, но не режут** (kindnet). Стенд:

```bash
minikube delete
minikube start --cni=calico --memory=4000 --cpus=2
# Task4 после пересоздания:
# ./Task4/create-users.sh && ./Task4/create-roles.sh && ./Task4/bind-roles.sh
```

`deploy.sh` откажется работать на kindnet и дождётся Ready у `calico-node`.

## Порядок

```bash
cd Task5
chmod +x deploy.sh verify.sh
./deploy.sh
./verify.sh   # матрица: 4 allow + 4 deny из подов с role=*
```

Apply вручную:

```bash
kubectl apply -f manifests/00-namespace.yaml
kubectl apply -f manifests/01-workloads.yaml
kubectl apply -f manifests/default-deny.yaml
kubectl apply -f manifests/non-admin-api-allow.yaml
kubectl apply -f manifests/admin-api-allow.yaml
```

### Как в уроке (alpine без labels)

Чужой pod **не** в allow-парах → timeout (доказательство default-deny):

```bash
kubectl -n pd-demo run probe --rm -i -t --image=alpine --restart=Never -- \
  wget -qO- --timeout=2 http://back-end-api-app
# ожидание: wget: download timed out
```

Разрешённый путь — только из pod с нужным `role` (это делает `verify.sh`):

```bash
kubectl -n pd-demo exec deploy/front-end-app -- wget -qO- --timeout=2 http://back-end-api-app
# ожидание: HTML nginx (exit 0)
```

## Связь с 1–4 / дыра labels

- Task2: нет сегментации → здесь default-deny + пары.
- Task4: RBAC режет API Kubernetes; NetworkPolicy режет pod↔pod TCP.
- Доверие к `role=…`: на стенде labels ставит наш манифест; в проде кто угодно с правом create pod может «войти» в пару — закрывается admission (Task7 PSS/Gatekeeper), не NetworkPolicy.
