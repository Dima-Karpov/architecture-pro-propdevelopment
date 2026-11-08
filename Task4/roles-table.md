# Ролевая модель PropDevelopment (Task4)

Namespaces доменов кейса: `sales`, `housing`, `finance`, `data`.  
Права на workloads / secrets — только в этих NS (RoleBinding). `kube-system` и прочие системные NS закрыты.

| Роль K8s | Права | Группы |
| --- | --- | --- |
| `pd-viewer` (ClusterRole + RoleBinding в доменных NS) | `get` / `list` / `watch` на `pods`, `services`, `deployments`, `configmaps`; **без secrets** | `pd-viewers` — PO, бизнес-аналитики, менеджеры операционных команд, FE/BE разработчики (read-only в prod); пример: `alice-analyst` |
| `pd-cluster-reader` (ClusterRole + ClusterRoleBinding) | `get` / `list` / `watch` только на cluster-scoped `nodes`, `namespaces` | та же `pd-viewers` (узкая роль: nodes/namespaces нельзя выдать через RoleBinding) |
| `pd-configurator` (ClusterRole + RoleBinding в доменных NS) | CRUD на workloads, `configmaps`, `ingresses`; **без secrets** | `pd-devops` — DevOps и инженеры эксплуатации продуктовых команд; пример: `bob-devops` |
| `pd-secrets-admin` (ClusterRole + RoleBinding в доменных NS) | `get` / `list` / `watch` / `create` / `update` / `patch` на `secrets` (ПДн / ИБ); **не** cluster-wide | `pd-security` — специалист ИБ; пример: `carol-security` |
