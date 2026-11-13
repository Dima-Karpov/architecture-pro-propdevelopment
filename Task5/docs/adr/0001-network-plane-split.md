# ADR. Разделение клиентской и админской сетевых плоскостей

### Название задачи:

PROP-ADR-5. Микросегментация east-west: `front-end`/`back-end-api` отдельно от `admin-front-end`/`admin-back-end-api`

### Автор:

d.karpov

### Дата:

09.11.2026

### Функциональные требования

В одном namespace живут четыре сервиса (учебный стенд на nginx). Нужно разрешить трафик **только** в парах клиентской и админской плоскостей и запретить перекрёст. Опора на Task2 (нет сегментации / межсегментной фильтрации; направление — default-deny) и Task4 (least privilege по ролям — сеть не должна быть «плоской», если RBAC уже режет API).

| **№** | **Действующие лица или системы**                                    | **Use Case**       | **Описание**                                                                                    |
| :---: | :------------------------------------------------------------------ | :----------------- | :---------------------------------------------------------------------------------------------- |
|  UC1  | Клиент / собственник, `front-end`, `back-end-api`                   | Клиентский контур  | Витрина / ЛК ходит только в свой API. Компрометация front не даёт сетевого пути в admin-api.    |
|  UC2  | Сотрудник УК / back-office, `admin-front-end`, `admin-back-end-api` | Админский контур   | Админ-UI ходит только в admin-api (привилегированные операции, ПДн, кросс-квартирные действия). |
|  UC3  | Любой pod в NS, чужая пара                                          | Перекрёст запрещён | `front-end` -  `admin-back-end-api`, `admin-front-end` - `back-end-api`, и зеркально.           |
|  UC4  | DevOps / ИБ                                                         | Политика как код   | Политики в git (`manifests/`), apply без ручных `kubectl edit`.                                 |

### Нефункциональные требования

| **№** | **Требование**                                                                      |
| :---: | :---------------------------------------------------------------------------------- |
|  S1   | Default-deny Ingress+Egress в NS; allow только по явному правилу (Task2 §III п.11). |
|  S2   | Пары открыты **в обе стороны** (задание курса).                                     |
|  S3   | DNS к CoreDNS разрешён — иначе Service discovery ломается.                          |
|  S4   | Один NS + labels `role`, без Istio/Cilium NetworkPolicy CRD.                        |
|  S5   | CNI с enforcement NetworkPolicy (Calico); kindnet политики принимает, но не режет.  |

### Решение

**Что разделяем.** Две логические плоскости в одном namespace `pd-demo`:

```text
pd-demo
├── plane: client  — role=front-end ↔ role=back-end-api
└── plane: admin   — role=admin-front-end ↔ role=admin-back-end-api
```

**Как разделяем.**

1. Labels на подах: `role` ∈ {`front-end`, `back-end-api`, `admin-front-end`, `admin-back-end-api`}.
2. `default-deny-all` — пустой selector `{}`, `policyTypes: [Ingress, Egress]`.
3. `allow-dns` — egress UDP/TCP 53 → CoreDNS в `kube-system`.
4. `non-admin-api-allow.yaml` — Ingress+Egress TCP/80 только между `front-end` и `back-end-api`.
5. `admin-api-allow.yaml` — то же для admin-пары.

C4 Container: [`c4/01-containers-network-planes.puml`](../../c4/01-containers-network-planes.puml) (SVG — GitHub Actions).

Правила NetworkPolicy **аддитивны**: deny + allow-pair даёт нужную матрицу без «дыр» у подов без selector.

**Почему не отдельные namespace на этом шаге.** Задание курса явно: один NS и разрез по labels. Для PropDevelopment в проде домены уже режем NS (`sales`/`housing`/`finance`/`data`, Task4); внутри домена ЖКУ всё равно нужны плоскости client vs admin — это как раз NetworkPolicy по `role`. Отдельный NS на admin — следующий шаг (если появятся разные команды/секреты), не замена label-политик.

### Альтернативы

Только Ingress allow без default-deny egress. Перекрёст на вход режется, но исходящий «шум» и обход через третий сервис остаются. Отклонено: default-deny как в Task2.

Отдельные namespace `client` / `admin` без NetworkPolicy. Изоляция NS есть, но внутри NS снова плоская сеть; задание требует политики в одном NS. Отклонено для стенда; в проде — NS **и** NetworkPolicy.

Service mesh (mTLS + AuthorizationPolicy). Сильнее (идентичность сервиса, L7), тяжелее для спринта. Отклонено: NetworkPolicy закрывает L3/L4 требования задания.

Плоская сеть + только RBAC (Task4). RBAC не режет pod→pod TCP. Отклонено: сеть и API — разные плоскости контроля.

### Недостатки, ограничения, риски

CNI. Без Calico/Cilium политики декоративны. На стенде — `minikube start --cni=calico` (см. README).

Доверие к label. Selector смотрит только на `role`; pod с подделанным label попадает в пару. На стенде labels из нашего Deployment. В проде — контроль create/update labels через admission (Task7 PSS/Gatekeeper), не через NetworkPolicy.

Только L3/L4. Path/method admin API NetworkPolicy не видит — AuthZ остаётся в приложении / API gateway (Task3). Bidirectional api→front — требование задания; в проде чаще только front→api.

Учебные nginx. Нет реальных ПДн; модель ролей переносится на housing/tenant-core vs admin-BFF.

Ingress снаружи. Политики режут east-west. North-south (Ingress/firewall кейса) и партнёрский контур — отдельно; сюда не тащим.
