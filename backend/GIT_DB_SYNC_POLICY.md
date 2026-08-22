# Politica obrigatoria GitHub + Supabase

A partir da RT84, qualquer alteracao que mude regra online, persistencia, RPC, tabela, indice, RLS/policy, cooldown, economia, combate, IA/automacao ou ADM deve existir nos dois lados:

1. SQL versionado em `backend/` no GitHub.
2. Migration aplicada no Supabase de producao.
3. `public.rt_schema_manifest()` recalculado apos a migration.
4. `public.rt_schema_sync_state` atualizado com o commit Git que contem o schema aplicado.
5. Gates de regressao executados antes do merge quando a alteracao atingir runtime/frontend.
6. O pacote distribuido deve conter os SQLs correspondentes.

## Verificacao atual RT84

Manifesto canonico: `backend/PRODUCTION_DB_MANIFEST_RT84.json`.
Verificador: `backend/check-production-drift.sql`.
Registro no banco: `public.rt_schema_sync_state`.

Nao salvar neste diretorio dumps de dados de jogador, senhas, tokens, emails privados ou segredos. O snapshot e apenas de schema/metadata tecnica.
