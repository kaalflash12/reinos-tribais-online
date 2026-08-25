# Reino Tribal — backend Turso isolado

Este diretório pertence exclusivamente ao Reino Tribal.

## Banco

O backend usa `@tursodatabase/serverless` e exige credenciais de um banco Turso dedicado ao Reino Tribal.

Variáveis server-side obrigatórias:

- `TURSO_DATABASE_URL`
- `TURSO_AUTH_TOKEN`

Variáveis recomendadas:

- `RT_ADMIN_PASSWORD` — senha inicial da conta `reinos_admin` (mínimo 12 caracteres)
- `RT_ADMIN_RECOVERY_KEY` — chave de recuperação administrativa (mínimo 32 caracteres)
- `RT_ALLOWED_ORIGINS` — origens extras separadas por vírgula

Nunca colocar tokens Turso dentro de `index.html`, `JOGAR_REINOS_TRIBAIS.html`, JavaScript público ou GitHub Pages.

## APIs

- `POST /api/reino` — conta, sessão, mundos, associação jogador/mundo e save.
- `POST /api/admin` — painel administrativo compatível durante a migração.

O schema é criado idempotentemente no primeiro acesso configurado e também está documentado em `schema.sql`.

## Isolamento

A ponte `rt85-auth-bridge.js` bloqueia tráfego real para o Supabase legado. O Reino Tribal não deve compartilhar banco com Naruto Unison, Shinobi, Bacaworld ou MUNDO.
