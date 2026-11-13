# ADR. Интеграция партнёра «Умный дом»

### Название задачи:

PROP-ADR-3. Внешние интеграции интеллектуального домофона и шлагбаума через партнёра «Умный дом»

### Автор:

d.karpov

### Дата:

08.11.2026

### Функциональные требования

На одну квартиру (`object_id`) — **несколько собственников** (сособственники) и **члены домохозяйства** (семья), у каждого свой `subject_id`. Роли: `owner` (управление домом) и `resident` (пользователь доступа). Биометрия и согласие — **на человека**, не «на квартиру целиком». Whitelist ГРЗ — список номеров домохозяйства на объект. PropDevelopment — мастер согласий и whitelist; match лица и LPR — у партнёра на edge. CRM, Data/BI и платежи в контур партнёра не входят. Опора на Task1 (**ГРЗ = confidential**; биометрия в mindmap отдельным активом не размечена — здесь отдельный режим: согласие у нас, match на edge) и Task2 (единые политики партнёрских API, tenant-изоляция, IdP/RBAC).

| **№** | **Действующие лица или системы** | **Use Case** | **Описание** |
| :---: | :------------------------------- | :----------- | :----------- |
| UC1 | Собственник / член семьи, витрина, Keycloak, tenant-core-app, smart-home-adapter, партнёр, домофон | Видео и открытие домофона | 1. Subject логинится в витрину по OIDC (Auth Code + PKCE); JWT несёт `subject_id`. 2. AuthZ: subject привязан к `object_id` (роль `owner` или `resident`). 3. Звонок: партнёр → adapter → push всем subject с правом на этот object. 4. Видео: session ticket → WebRTC/HLS у партнёра; не через tenant-core. 5. Open: витрина → tenant-core → adapter → партнёр (`POST open`), scope `tenant_id` + `object_id`; в audit — кто открыл (`subject_id`). 6. Step-up/MFA; идемпотентный ключ. |
| UC2 | Собственник (`owner`), члены семьи (`resident`), витрина, Keycloak, tenant-core, adapter, партнёр, домофон | Биометрия семьи | 1. `owner` приглашает членов домохозяйства на object (или сособственники уже привязаны). 2. Каждый subject **сам** даёт согласие 152-ФЗ на свою биометрию; мастер — `smart-home-db` (строка `subject_id` + `object_id` + статус согласия). 3. Enrollment лица — у партнёра на edge; нам в sync уходит только политика допуска `subject↔object↔device` (разрешено/запрещено + opaque `partner_person_ref`), **без** сырых шаблонов в BI/Data. 4. На одной квартире N лиц (семья); match на edge открывает дверь только при активном согласии этого subject. 5. Отзыв согласия одним человеком не снимает допуск остальных. |
| UC3 | Собственник / член семьи, витрина, Keycloak, tenant-core, adapter, партнёр, шлагбаум | Управление шлагбаумом | 1. Ручное open — как UC1. 2. Авто: LPR сверяет номер с whitelist **домохозяйства** на этот object. 3. Audit в `smart-home-db`. |
| UC4 | Собственник (`owner`), витрина, tenant-core, adapter, smart-home-db, партнёр, шлагбаум | Sync whitelist ГРЗ | 1. CRUD whitelist — только роль `owner` (несколько сособственников могут править один список object). 2. Несколько номеров на квартиру; мастер — `smart-home-db`. 3. Adapter пушит минимальный срез LPR (`PUT whitelist sync`), scope `tenant_id` + `object_id`. 4. Кросс-УК запрещён. 5. Step-up/MFA. |
| UC5 | Subject (сам о себе) или `owner` (отзыв члена), витрина, tenant-core, adapter, smart-home-db, партнёр | Отзыв согласия / исключение из дома | 1. Subject отзывает **своё** согласие — снимается только его био-допуск. 2. `owner` исключает `resident` из домохозяйства — revoke привязки subject↔object + sync запрета партнёру. 3. Edge-match этого человека больше не открывает дверь этой квартиры. |
| UC6 | tenant-core, adapter, smart-home-db, ИБ / аудит | Аудит команд открытия | 1. Журнал: кто (`subject_id`), роль, когда, tenant, object, device, исход. 2. Сырое видео и биошаблоны в журнал и Data не кладём. 3. Для аудита Task2. |
| UC7 | Собственник (`owner`), витрина, Keycloak, tenant-core, smart-home-db | Управление домохозяйством | 1. Приглашение / отзыв членов семьи на `object_id`. 2. Несколько `owner` на одну квартиру равноправны в управлении (если иное не задано CRM). 3. `resident` не правит whitelist и не приглашает других. |

### Нефункциональные требования

| **№** | **Требование** |
| :-: | :- |
| S1 | Least privilege: subject видит только свои `object_id`; роль `resident` не управляет домом; партнёрский токен — `tenant_id` + `object_id`; запрет кросс-УК. |
| S2 | Tenant isolation: данные и команды одной УК недоступны другой; adapter отклоняет запросы вне scope. |
| S3 | Минимизация ПДн (152-ФЗ): в партнёрский контракт — open / LPR / политика `subject↔object↔device` + opaque ref; сырые шаблоны и полное видео в PropDevelopment/BI/Data не уходят. |
| S4 | ГРЗ — confidential (Task1); биометрия — отдельный режим (edge у партнёра, согласие у нас; в mindmap Task1 как класс не размечена). Мастер согласий и whitelist — `smart-home-db`. |
| S5 | Согласие персональное: один человек ≠ вся квартира; отзыв одного не трогает остальных членов семьи. |
| S6 | Локализация контура умного дома в РФ; секреты и ключи mTLS вне кода (vault/K8s secrets). |
| S7 | Партнёр только через `smart-home-adapter`; TLS на всех внешних каналах. |
| S8 | AuthN — существующий Keycloak OIDC для всех subject (owners и residents); критичные действия (`owner`: whitelist, приглашения; любой: open) — step-up/MFA. |
| S9 | AuthN/AuthZ к партнёру — OAuth 2.0 client credentials + mTLS, короткоживущие токены. |
| S10 | TTL видеопотока/ticket'ов и журналов — конечный; просроченное удаляется/архивируется. |
| S11 | Идемпотентность open: повтор с тем же ключом не даёт второе открытие и не дублирует смысл audit. |
| S12 | CRM / Data/BI / платежи вне периметра партнёра; прямых связей к партнёру нет. |

### Решение

Новые контейнеры на исходном ландшафте PropDevelopment: `smart-home-adapter` — единственная дверь к партнёру; `smart-home-db` — домохозяйство (`subject↔object` + роль), согласия биометрии **по subject**, whitelist ГРЗ на object, привязка object↔device, журнал команд. Люди (сособственники и члены семьи) ходят в существующую витрину и Keycloak; `tenant-core-app` оркестрирует услуги и зовёт adapter. Партнёр держит устройства, edge-match и LPR; PropDevelopment не SDK-клиент устройств.

Модель доступа (KISS):

```text
object_id (квартира / въезд)
  ├── subject_id × N  (owner | resident)
  │     └── consent_bio + partner_person_ref   ← персонально
  ├── plates[]                                 ← whitelist домохозяйства
  └── device_id (домофон / шлагбаум)
```

Исходники C4 (PlantUML): [`01-context-smart-home.puml`](../../c4/01-context-smart-home.puml), [`02-containers-smart-home.puml`](../../c4/02-containers-smart-home.puml). SVG соберёт GitHub Actions после push — в ADR картинки не вставляем.

Контекст: собственники / члены семьи, PropDevelopment, партнёр, домофон, шлагбаум; звонок/push только через PropDevelopment.

Контейнеры: витрина, Keycloak, tenant-core, adapter + smart-home-db, партнёр; CRM / Data / платежи вне контура.

#### Кто кого вызывает

Стрелка от вызывающего. Вторая колонка — протокол.

| Кто вызывает                | Кого               | Протокол и формат                         | Что в теле / зачем                                               |
| --------------------------- | ------------------ | ----------------------------------------- | ---------------------------------------------------------------- |
| Subject (owner/resident) | Витрина | HTTPS, mobile → BFF/API | ЛК «Умный дом» |
| Subject | Keycloak | HTTPS OIDC, Auth Code + PKCE | Логин, step-up MFA; JWT с `subject_id` |
| Витрина | Keycloak | HTTPS, JWT introspection / JWKS | Проверка access token |
| Витрина | tenant-core-app | HTTPS sync REST JSON, Bearer OIDC | Open, согласия, whitelist, управление домом |
| Subject (через витрину) | Партнёр (видео) | HTTPS ticket → WebRTC/HLS | Просмотр; не через tenant-core |
| tenant-core-app | smart-home-adapter | HTTPS sync REST JSON + service identity (mTLS или JWT клиента) | Open, sync политик subject, audit; не анонимный east-west |
| smart-home-adapter | smart-home-db | SQL sync | Домохозяйство, согласия, whitelist, журнал |
| smart-home-adapter | Партнёр | HTTPS sync REST JSON, OAuth 2.0 CC + mTLS | `POST open`, `PUT whitelist sync`, sync политики `subject↔object↔device` |
| Партнёр | smart-home-adapter | HTTPS async webhook / callback | Звонок, результат open / edge-match (`partner_person_ref`) |
| smart-home-adapter | Витрина | HTTPS sync / internal event | Событие звонка; витрина шлёт mobile push subject |
| Партнёр | Домофон / шлагбаум | vendor device API over TLS | Видео, open, edge biometrics (N лиц), LPR |

#### Логика выбора

- Одна дверь (adapter) закрывает боль Task2: партнёрские API без единых политик и с кросс-УК. Политики, scope и audit живут в одном месте.
- Отдельная БД умного дома — относительно раздувания `tenant-core-db`: ЖКУ-ПДн и мастер ГРЗ/согласий не смешиваем; Data не получает сырой био/видео контур.
- Keycloak уже есть: новый IdP для собственников не вводим.
- Биометрия на edge у партнёра: согласие и допуск — **на каждого члена семьи**; сырой шаблон у нас не храним (Task1, 152-ФЗ).
- Несколько собственников и семья — норма домена ЖК; boolean «квартира открыта биометрией» ломает отзыв согласия одного человека.
- ГРЗ: мастер у нас (несколько номеров на object), партнёру — узкий sync под шлагбаум.

### Альтернативы

Прямой SDK мобилки к партнёру. Витрина обходит tenant-core и политики PropDevelopment; step-up, tenant isolation и единый audit ломаются. Отклонено: партнёр только через adapter.

Раздувание `tenant-core` без adapter. Ядро ЖКУ тащит OAuth CC, mTLS, sync устройств и журнал. Меняется чаще партнёрского контракта и смешивает домены. Отклонено: отдельный adapter + `smart-home-db`.

Статические API-ключи без mTLS. Долгоживущий секрет, слабая привязка к клиенту, проще утечка. Отклонено: OAuth 2.0 client credentials + mTLS, короткоживущие токены.

Партнёр как мастер ПДн / whitelist. PropDevelopment теряет контроль согласий и ГРЗ; отзыв и аудит зависят от чужой модели. Отклонено: мастер у нас, партнёру — политика и минимальный sync.

Общая БД с партнёром. Нет границы доверия, кросс-tenant и лишние ПДн в одном хранилище. Отклонено: раздельные базы, контракт только через API adapter.

### Недостатки, ограничения, риски

ИБ edge у партнёра. Match лица и LPR на устройстве — контур партнёра. Риск компрометации edge принимаем; компенсируем договором, аудитом open-команд у нас и минимальным объёмом данных в sync.

Лаг sync whitelist. Между записью в `smart-home-db` и применением на шлагбауме есть окно. В это окно LPR может открыть по устаревшему списку или не открыть по новому. Компенсация: sync сразу после CRUD, мониторинг ошибок push, ручное open через ЛК.

Видеопоток через партнёра. Сырое видео не храним у себя; TTL session ticket и политики партнёра ограничивают окно просмотра. Риск задержки/недоступности видео при сбое партнёра; open-команды при этом остаются в нашем audit-журнале.

Расширение Keycloak без нового IdP. Owners и residents сидят на auth-service-1; step-up/MFA на существующем IdP. Риск усложнения realm/ролей: отдельный IdP под умный дом не окупается.

Конфликт сособственников. Несколько `owner` на одну квартиру могут одновременно править whitelist / состав семьи. Принимаем last-write-wins + audit кто изменил; отдельный workflow согласования между сособственниками — вне MVP.

Зависимость от доступности партнёра. Без партнёра нет видео, edge-био и LPR. Мастер whitelist/согласий и журнал остаются у нас; при аварии open даёт явный отказ, не «тихий» успех.
