# Task4: RBAC в Kubernetes (PropDevelopment)

Least-privilege RBAC для доменов PropDevelopment: namespaces `sales`, `housing`, `finance`, `data`.  
Роли: `pd-viewer` + узкий `pd-cluster-reader`, `pd-configurator`, `pd-secrets-admin`. Workloads и secrets — только через RoleBinding в доменных NS (не `kube-system`). Таблица — [`roles-table.md`](roles-table.md).

## Требования

- [Minikube](https://minikube.sigs.k8s.io/) и `kubectl` (Minikube уже установлен → при необходимости только `minikube start`)
- OpenSSL
- Пустой/чистый кластер Minikube (CA в `~/.minikube/ca.crt` и `ca.key`)

## Что здесь лежит

| Артефакт | Назначение |
| --- | --- |
| `roles-table.md` | Роль → права → группы (для ревьюера) |
| `create-users.sh` | Клиентские сертификаты + контексты kubeconfig (`openssl` + kubeconfig) |
| `create-roles.sh` | `kubectl apply` namespaces + ClusterRoles |
| `bind-roles.sh` | `kubectl apply` ClusterRoleBinding / RoleBinding |
| `manifests/*.yaml` | Описание ролей и bindings текстом (как в уроке «Как настроить RBAC») |
| `certs/` | `.key` / `.crt` пользователей (генерится скриптом, в git не коммитить) |

Связка: **YAML = описание** Role / ClusterRole / Binding → **`.sh` = apply / openssl вокруг них**. Без скриптов задание формально не закрыто; без YAML слабее связь с теорией — поэтому оба.

Пользователь в учебном K8s — это пара файлов (ключ + сертификат), не логин/пароль. В CSR поле `CN` = имя пользователя, `O` = группа RBAC (`pd-viewers`, `pd-devops`, `pd-security`).

## Пользователи → группы

| Пользователь | Группа (`O=` в сертификате) | Роль |
| --- | --- | --- |
| `alice-analyst` | `pd-viewers` | `pd-viewer` + `pd-cluster-reader` |
| `bob-devops` | `pd-devops` | `pd-configurator` |
| `carol-security` | `pd-security` | `pd-secrets-admin` (только доменные NS) |

## Сертификаты: полные команды (ручной прогон)

Те же команды — тело `create-users.sh`. Ниже — copy-paste для ручного прогона.

```bash
# каталог для файлов
mkdir -p Task4/certs && cd Task4/certs

# --- bob-devops (группа pd-devops) ---
openssl genrsa -out bob-devops.key 2048
openssl req -new -key bob-devops.key -out bob-devops.csr -subj "/CN=bob-devops/O=pd-devops"
openssl x509 -req -in bob-devops.csr \
  -CA "$HOME/.minikube/ca.crt" \
  -CAkey "$HOME/.minikube/ca.key" \
  -CAcreateserial -out bob-devops.crt -days 365
kubectl config set-credentials bob-devops \
  --client-certificate="$PWD/bob-devops.crt" \
  --client-key="$PWD/bob-devops.key"
kubectl config set-context bob-devops@minikube --cluster=minikube --user=bob-devops

# --- alice-analyst (группа pd-viewers) ---
openssl genrsa -out alice-analyst.key 2048
openssl req -new -key alice-analyst.key -out alice-analyst.csr -subj "/CN=alice-analyst/O=pd-viewers"
openssl x509 -req -in alice-analyst.csr \
  -CA "$HOME/.minikube/ca.crt" \
  -CAkey "$HOME/.minikube/ca.key" \
  -CAcreateserial -out alice-analyst.crt -days 365
kubectl config set-credentials alice-analyst \
  --client-certificate="$PWD/alice-analyst.crt" \
  --client-key="$PWD/alice-analyst.key"
kubectl config set-context alice-analyst@minikube --cluster=minikube --user=alice-analyst

# --- carol-security (группа pd-security) ---
openssl genrsa -out carol-security.key 2048
openssl req -new -key carol-security.key -out carol-security.csr -subj "/CN=carol-security/O=pd-security"
openssl x509 -req -in carol-security.csr \
  -CA "$HOME/.minikube/ca.crt" \
  -CAkey "$HOME/.minikube/ca.key" \
  -CAcreateserial -out carol-security.crt -days 365
kubectl config set-credentials carol-security \
  --client-certificate="$PWD/carol-security.crt" \
  --client-key="$PWD/carol-security.key"
kubectl config set-context carol-security@minikube --cluster=minikube --user=carol-security
```

Где гонять руками: `minikube start` / `kubectl` — из любого каталога; `openssl` — в `Task4/certs`.

## Порядок запуска (скрипты)

```bash
minikube start

cd Task4
./create-users.sh
./create-roles.sh
./bind-roles.sh
```

(Скрипты сами находят `manifests/` и `certs/` рядом с собой — можно и из корня репо: `./Task4/create-users.sh` и т.д.)

1. **create-users.sh** — для `alice-analyst`, `bob-devops`, `carol-security`: `openssl` (ключ → CSR → подпись CA Minikube) и `kubectl config set-credentials` / `set-context`.
2. **create-roles.sh** — `kubectl apply -f manifests/00-namespaces.yaml` и `01-clusterroles.yaml`.
3. **bind-roles.sh** — снимает старые cluster-wide bindings (если были); `02-bindings.yaml` = только `pd-cluster-reader` (ClusterRoleBinding); RoleBinding viewer/secrets/configurator — цикл по `sales`/`housing`/`finance`/`data` (без копипасты ×4 в YAML).

## Проверки

```bash
# alice (viewer): доменный NS — да; secrets — нет; чужой системный NS — нет
kubectl --context=alice-analyst@minikube auth can-i get pods -n sales
kubectl --context=alice-analyst@minikube auth can-i get secrets -n sales
kubectl --context=alice-analyst@minikube auth can-i get pods -n kube-system
kubectl --context=alice-analyst@minikube auth can-i get nodes

# bob (devops): workloads в доменном NS — да, secrets — нет
kubectl --context=bob-devops@minikube auth can-i create deployments -n housing
kubectl --context=bob-devops@minikube auth can-i get secrets -n housing

# carol (ИБ): secrets в доменном NS — да; в kube-system — нет
kubectl --context=carol-security@minikube auth can-i get secrets -n finance
kubectl --context=carol-security@minikube auth can-i get secrets -n kube-system
```

Ожидание: `yes` / `no` / `no` / `yes` / `yes` / `no` / `yes` / `no`.

Namespaces `sales` / `housing` / `finance` / `data` — домены кейса (продажи, ЖКУ, финансы, data).

## Как посмотреть роли и права

### 1. Список ролей

```bash
kubectl get clusterroles | grep pd-
kubectl get clusterrolebindings | grep pd-
kubectl get rolebindings -A | grep pd-
```

### 2. Права роли (самое полезное)

```bash
kubectl describe clusterrole pd-viewer
kubectl describe clusterrole pd-cluster-reader
kubectl describe clusterrole pd-configurator
kubectl describe clusterrole pd-secrets-admin
```

В блоке **PolicyRule**: колонки Resources + Verbs.

Ожидаемо:

- `pd-viewer` — `get` / `list` / `watch` на pods, services, deployments, configmaps (namespaced)
- `pd-cluster-reader` — `get` / `list` / `watch` только на nodes, namespaces
- `pd-configurator` — CRUD на pods / services / deployments / configmaps / ingresses
- `pd-secrets-admin` — `get` / `list` / `watch` / `create` / `update` / `patch` на secrets

### 3. Кому выдано (binding)

```bash
kubectl describe clusterrolebinding pd-viewers-cluster-reader
kubectl describe rolebinding pd-viewers -n sales
kubectl describe rolebinding pd-security-secrets -n finance
kubectl describe rolebinding pd-devops-configurator -n sales
```

Subjects = группа (`pd-viewers` / `pd-devops` / `pd-security`).

### 4. Глазами конкретного юзера (весь список прав)

```bash
kubectl --context=alice-analyst@minikube auth can-i --list -n sales
kubectl --context=bob-devops@minikube auth can-i --list -n housing
kubectl --context=carol-security@minikube auth can-i --list -n finance
```

Точечные `auth can-i …` выше — те же права, но один вопрос «можно ли X».

### 5. YAML целиком

```bash
kubectl get clusterrole pd-viewer -o yaml
# или локально:
# cat manifests/01-clusterroles.yaml
# cat manifests/02-bindings.yaml
```
