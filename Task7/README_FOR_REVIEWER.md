# Task7: PodSecurity + Gatekeeper

Закрывает privileged-дыру из инцидента Task6 и усиливает защиту secret-данных Task1 на admission: privilege escalation / hostPath / root не проходят в `audit-zone`.

## Слои admission

1. **PSS restricted** (labels NS) — baseline: insecure режутся первыми (`violates PodSecurity "restricted:latest"`).
2. **Gatekeeper** — второй слой, defense-in-depth / policy-as-code: те же запреты (privileged, hostPath, `runAsNonRoot` + `readOnlyRootFilesystem`) как Constraints с `enforcementAction: deny` на `audit-zone`, не завязка только на labels NS.

Secure проходят оба слоя. В типичном прогоне текст ошибки — от PSA; Gatekeeper при этом установлен и constraints активны (см. ниже).

## Порядок (корень репо)

```bash
minikube start --memory=4000 --cpus=2
bash Task7/run.sh
```

`run.sh`: NS → Gatekeeper → templates/constraints → insecure deny / secure allow → `verify/*` → cleanup.

Ожидаемый хвост:

```text
PASS deny  01-privileged-pod.yaml
…
PASS allow 03-secure.yaml
OK: PSS + Gatekeeper present
OK: admission matches PSS + Gatekeeper
OK: Task7 run complete
```

Проверка, что Gatekeeper на месте:

```bash
kubectl -n gatekeeper-system get pods
kubectl get constraints -A
```

Ожидание: pods Ready; `deny-privileged`, `deny-hostpath`, `require-nonroot-readonly` с `ENFORCEMENT-ACTION=deny`.

## Audit policy

`audit-policy.yaml` — мост к Task6: узкий фокус на Pod create/update (`RequestResponse`) и admission webhooks. Подключение к apiserver — как в Task6.

## Самопроверка (чеклист ТЗ)

- [x] Небезопасные поды отклоняются (сначала PSA; Gatekeeper — второй слой)
- [x] Безопасные проходят
- [x] Gatekeeper активен (`gatekeeper-system` Ready, constraints deny)
- [x] PodSecurity Admission действует (`enforce/audit/warn=restricted` на `audit-zone`)
