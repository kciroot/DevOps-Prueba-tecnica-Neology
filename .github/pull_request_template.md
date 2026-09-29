## Qué cambia y por qué

<!-- Una o dos líneas. Enlaza el issue si existe. -->

## Checklist

- [ ] El pipeline está en verde (CI, Security y Build)
- [ ] No se agregan secretos, `.env` ni credenciales
- [ ] Si cambia configuración: se actualizó `.env.example` / `environments/*.tfvars`
- [ ] Si cambia la operación: se actualizó `docs/RUNBOOK.md`
- [ ] Plan de rollback: volver a desplegar el tag `sha-` anterior
