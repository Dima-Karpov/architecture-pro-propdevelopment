# Отчёт по результатам анализа Kubernetes Audit Log

Источник: `Task6/audit.log` после `simulate-incident.sh` на Minikube с `audit-policy.yaml`.  
Выжимка: `audit-extract.json` (`filter-audit.sh`). Связь с целевой моделью — Task4 (`pd-secrets-admin` только в доменных NS, без `cluster-admin`).

## Подозрительные события

1. Доступ к секретам:
   - Кто: инициатор `minikube-user` (system:masters), **impersonate** → `system:serviceaccount:secure-ops:monitoring`
   - Где: `list` secrets в namespace `kube-system` (скрипт: `kubectl get secret … --as=…:monitoring`)
   - Результат: **403 Forbidden** — у SA `monitoring` нет прав на secrets
   - Почему подозрительно: мониторинг не должен даже пытаться читать secrets в `kube-system` (токены, bootstrap). В Task4 secrets — только у `pd-secrets-admin` и только в доменных NS (`sales`/`housing`/`finance`/`data`)

2. Привилегированные поды:
   - Кто: `minikube-user`
   - Где: create pod `privileged-pod` в `secure-ops`, `securityContext.privileged: true` → **201**
   - Комментарий: privileged = почти root на ноде. RBAC админа это разрешил; нет Pod Security / Gatekeeper (закрытие — Task7)

3. Использование kubectl exec в чужом поде:
   - Кто: `minikube-user`
   - Что делал: `GET …/pods/coredns-…/exec?command=cat&command=/etc/resolv.conf` в `kube-system` (в audit verb = `get`, subresource/URI `exec`)
   - Результат API: websocket **101**; внутри контейнера `cat` нет (distroless) — но **запрос exec уже успешен** с точки зрения API
   - Почему подозрительно: exec в системный DNS без разделения обязанностей (SoD)

4. Создание RoleBinding с правами cluster-admin:
   - Кто: `minikube-user`
   - Где: RoleBinding `escalate-binding` в `secure-ops`: SA `monitoring` → ClusterRole `cluster-admin` → **201**
   - К чему привело: эскалация прав monitoring до admin **в пределах NS** `secure-ops` (RoleBinding сужает ClusterRole до namespace). Для мониторинга достаточно read-only metrics; в модели Task4 `cluster-admin` продуктовым ролям не выдаётся

5. Удаление audit-policy.yaml:
   - Кто: скрипт вызывал `kubectl delete -f /etc/kubernetes/audit-policy.yaml --as=admin`
   - В audit.log **нет** события: файла нет на Mac-хосте, kubectl упал **до** запроса в API
   - Возможные последствия (если бы путь существовал / удалили конфиг apiserver): остановка или «ослепление» аудита — anti-forensics. На проде audit log выносить с ноды и делать неизменяемым

## Вывод

Цепочка инцидента в логе видна: попытка чтения secrets от SA monitoring (отклонена) → privileged pod → exec в CoreDNS → RoleBinding на `cluster-admin`. Компрометацией кластера считать успешный privileged и/или выдачу admin-прав чужому SA и/или уничтожение audit trail. Ошибки политики: нет запрета bind на `cluster-admin`, нет ограничения privileged pods, SA monitoring без узкой Role, админ может exec в `kube-system`. Закрытие: RBAC как в Task4 + PodSecurity/Gatekeeper (Task7) + вынос audit log.
