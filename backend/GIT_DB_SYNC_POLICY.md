# Política obrigatória GitHub + Supabase

A partir do Reino Tribal v1.0.1, qualquer alteração que mude regra online, persistência, RPC, tabela, índice, RLS/policy, cooldown, economia, combate, IA/automação, autenticação ou ADM deve existir nos dois lados:

1. SQL versionado em `backend/` no GitHub.
2. Migration aplicada no Supabase de produção.
3. `public.rt_schema_manifest()` recalculado após a migration.
4. `public.rt_schema_sync_state` atualizado com o commit Git que contém o schema aplicado.
5. Gates de regressão executados antes do merge quando a alteração atingir runtime/frontend.
6. O pacote distribuído deve conter os SQLs correspondentes.
7. O manifesto deve contar migrations com prefixos `rt*`, `fix_rt*`, `reinos_tribais_*` e `reino_tribal_*`.

## Verificação atual

Manifesto canônico: `backend/PRODUCTION_DB_MANIFEST.json`.
Verificador: `backend/check-production-drift.sql`.
Exportador de auditoria: `backend/export-production-schema-audit.sql`.
Registro no banco: `public.rt_schema_sync_state`.

Não salvar neste diretório dumps de dados de jogador, senhas, tokens, e-mails privados ou segredos. O snapshot é apenas de schema/metadata técnica.
