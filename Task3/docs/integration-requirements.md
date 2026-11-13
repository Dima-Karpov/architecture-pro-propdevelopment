# Task3 — Требования к внешним интеграциям «Умный дом»

Чеклист. Источники: задание 3 спринта 5, ADR [`adr/0001-partner-smart-home-integration.md`](adr/0001-partner-smart-home-integration.md), C4 [`../c4/`](../c4/), Task1 (**ГРЗ = confidential**; биометрия в mindmap отдельным классом не размечена) и Task2 (единые политики партнёрских API, tenant-изоляция, IdP/RBAC).

Периметр: партнёрская платформа «Умный дом» (домофон, шлагбаум). CRM собственников, Data/BI и платежи в контур партнёра не входят.

Домен: на одну квартиру (`object_id`) — несколько сособственников (`owner`) и члены семьи (`resident`); у каждого свой `subject_id`. Биометрия и согласие — персональные.

---

## 1. Безопасность (security)

| №      | Требование                                                                  | Как закрыто                                                                                       |
| ------ | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| SEC-1  | Единая политика внешнего API вместо «API как попало» (боль кейса / Task2)   | Единственная дверь — `smart-home-adapter`; партнёр не ходит в `tenant-core` / CRM / Data напрямую |
| SEC-2  | TLS на всех внешних каналах (витрина ↔ бэкенд, adapter ↔ партнёр, webhooks) | HTTPS; vendor device API у партнёра — TLS                                                         |
| SEC-3  | Секреты и ключи mTLS вне кода                                               | Vault / K8s secrets; ротация клиентских credentials и сертификатов                                |
| SEC-4  | Least privilege на данные и команды                                         | Subject — только свои `object_id`; `resident` не управляет домом; токен партнёра — `tenant_id` + `object_id` |
| SEC-5  | Tenant isolation / запрет кросс-УК                                          | Adapter отклоняет запросы вне scope; чужой tenant в токене — отказ                                |
| SEC-6  | Минимизация ПДн в контракте (152-ФЗ)                                        | В партнёрский API — только поля для open / LPR / политики допуска                                 |
| SEC-7  | Локализация обработки/хранения контура умного дома в РФ                     | Данные `smart-home-db` и первичный контур — РФ; трансграничная передача не заложена               |
| SEC-8  | Audit команд доступа                                                        | Журнал open (кто, когда, tenant, object, device, исход) в `smart-home-db`                         |
| SEC-9  | TTL и retention                                                             | Конечный TTL session ticket видео и журналов; просроченное удаляется/архивируется                 |
| SEC-10 | Идемпотентность команд open                                                 | Повтор с тем же ключом не даёт второе открытие и не дублирует смысл audit-события                 |
| SEC-11 | Сегментация: CRM / Data / платежи вне периметра партнёра                    | Нет прямых связей этих контуров к партнёру (см. C4 containers)                                    |

---

## 2. Аутентификация и авторизация (authN / authZ)

| №    | Контур                                                      | Протокол                                                                                 | AuthZ / ограничения                                                                     |
| ---- | ----------------------------------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| AZ-1 | Subject (owner/resident) → витрина / Keycloak | OIDC Authorization Code + PKCE | JWT с `subject_id`; проверка JWKS / introspection |
| AZ-2 | Open двери/шлагбаума; `owner`: whitelist, приглашения | Step-up / MFA через Keycloak | Без step-up команда не уходит в adapter |
| AZ-3 | Витрина → `tenant-core-app` | Bearer OIDC JWT | RBAC по роли `owner`/`resident` + привязка subject↔object |
| AZ-4 | `tenant-core-app` → `smart-home-adapter` | HTTPS + service identity (mTLS или JWT service-account) | Не анонимный east-west; только оркестрация умного дома |
| AZ-5 | `smart-home-adapter` → партнёр                              | OAuth 2.0 client credentials + mTLS                                                      | Короткоживущий access token; scope `tenant_id` + `object_id`; audience партнёрского API |
| AZ-6 | Партнёр → adapter (webhook / callback)                      | HTTPS + проверка подлинности вызова (mTLS или подпись)                                   | Только события звонка / результат open; без произвольного CRUD в наши БД                |
| AZ-7 | Запрещено                                                   | Статические долгоживущие API-ключи без mTLS; токены в URL; прямой SDK мобилки к партнёру | Обход политик PropDevelopment и единого audit                                           |

Новый IdP не вводим: owners и residents на `auth-service-1` (Keycloak).

---

## 3. Взаимодействие систем

```text
Subject (owner|resident) → Витрина → Keycloak (OIDC, step-up)
                              ↓
                       tenant-core-app
                              ↓
                       smart-home-adapter  ←→  smart-home-db
                              ↓  OAuth2 CC + mTLS, scoped token
                       Партнёр «Умный дом»
                         ├── Домофон (видео, open, N лиц на edge)
                         └── Шлагбаум (open, LPR по списку номеров)
```

| Поток | Направление | Формат | Содержание |
| --- | --- | --- | --- |
| Open домофон / шлагбаум | витрина → tenant-core → adapter → партнёр | sync REST JSON | `POST open`; audit с `subject_id` |
| Видео | витрина ← ticket → партнёр (WebRTC/HLS) | session ticket + медиа | Не через tenant-core; сырое видео у нас не храним |
| Звонок / визит | партнёр → adapter → витрина | async webhook / push | Push всем subject с правом на object |
| Sync whitelist ГРЗ | adapter → партнёр | `PUT whitelist sync` | Несколько номеров домохозяйства на шлагбаум |
| Политика биометрии | adapter → партнёр | sync `subject↔object↔device` | N лиц на квартиру; opaque `partner_person_ref`; без сырых шаблонов |
| Управление домом | `owner` → витрина → tenant-core | REST | Приглашение/отзыв `resident`, CRUD whitelist |
| Результат open / edge-match | партнёр → adapter | webhook | Журнал; отказ при недоступности партнёра |

Мастер у PropDevelopment: домохозяйство (subject↔object + роль), согласия **по человеку**, whitelist ГРЗ на object, object↔device, журнал. Партнёр — устройства, edge-match, LPR.

---

## 4. Биометрия и ГРЗ (чувствительные данные)

ГРЗ по Task1: **confidential**. Биометрия в mindmap Task1 отдельным активом не размечена — здесь **отдельный режим**: согласие и политика у PropDevelopment, match на edge у партнёра; сырые шаблоны в наш контур/Data не берём.

### Домохозяйство (несколько собственников + семья)

| № | Требование | Как закрыто |
| --- | --- | --- |
| HH-1 | Несколько сособственников на квартиру | N× `owner` ↔ один `object_id` |
| HH-2 | Члены семьи без права собственности | Роль `resident`; приглашает/исключает `owner` |
| HH-3 | Разделение прав | `resident`: open, своё согласие/био; `owner`: + whitelist, состав дома |
| HH-4 | Audit с указанием человека | В журнале всегда `subject_id`, не только квартира |

### Биометрия (лицо)

| № | Требование | Как закрыто |
| --- | --- | --- |
| BIO-1 | Согласие **каждого** субъекта (152-ФЗ) | Строка согласия на `subject_id` + `object_id` в `smart-home-db` |
| BIO-2 | Семья = N лиц на одну квартиру | Политика `subject↔object↔device`; не boolean «на квартиру» |
| BIO-3 | Match на edge у партнёра | Сырые шаблоны в PropDevelopment/BI/Data не храним и не шлём |
| BIO-4 | В контракт — политика + opaque ref | Sync: разрешено/запрещено + `partner_person_ref` |
| BIO-5 | Отзыв одного человека | Снимает только его допуск; остальные члены семьи остаются |
| BIO-6 | Видео с домофона | TTL ticket у партнёра; полное видео у нас / в Data не кладём |

### ГРЗ (номера авто / whitelist)

| № | Требование | Как закрыто |
| --- | --- | --- |
| PLATE-1 | Мастер whitelist у PropDevelopment | CRUD только `owner` → `smart-home-db` |
| PLATE-2 | Несколько номеров на домохозяйство | Список plates[] на `object_id` |
| PLATE-3 | Минимальный sync партнёру | Номера для LPR конкретного шлагбаума (`tenant_id` + `object_id`) |
| PLATE-4 | Правка whitelist — критичное | Step-up / MFA |
| PLATE-5 | Авто-открытие | LPR сверяет номер со списком; audit у нас |
| PLATE-6 | Лаг sync | Принятый риск ADR: sync сразу + мониторинг + ручное open |

---

## 5. Сводка

| Критерий приёмки | Артефакт |
| --- | --- |
| Context C4 | [`../c4/01-context-smart-home.puml`](../c4/01-context-smart-home.puml) |
| Containers C4 | [`../c4/02-containers-smart-home.puml`](../c4/02-containers-smart-home.puml) |
| Security + authN/authZ + взаимодействие | этот файл, §1–3 |
| Биометрия, семья, номера авто | этот файл, §4; ADR UC2/UC4/UC5/UC7, S3–S5 |
| Решение / альтернативы / риски | [`adr/0001-partner-smart-home-integration.md`](adr/0001-partner-smart-home-integration.md) |
