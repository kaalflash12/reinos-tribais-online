# Reino Tribal — Histórico de versões

## 1.0.2 — 2026-08-23

- Recuperação segura e de uso único para a conta administrativa `reinos_admin`.
- Nova tela de recuperação administrativa integrada ao login; nenhuma senha é fixa no código.
- Sessões administrativas antigas são revogadas ao trocar a senha.
- Backend de recuperação + autenticação administrativa validado E2E no banco.
- Interação mundial RT84 executada e persistida com custo, recompensa, cooldown e limite diário.
- Ciclo do Diretor IA `scheduled → active → finished` executado e comprovado no banco.
- Cache público e branding atualizados para `1.0.2`.

## 1.0.1 — 2026-08-22

- Sincronização definitiva entre Supabase Auth e `rt_players`.
- Backfill dos perfis faltantes: cada usuário Auth passa a possuir exatamente um perfil de jogador.
- Trigger automático para criar perfil quando uma nova conta Auth é criada.
- GitHub e Supabase vinculados por commit/hash de schema.
- Branding público continua como **Reino Tribal**, sem números RT visíveis.
- Cache-bust do branding atualizado para `1.0.1`.
- Pacote oficial deve ser regenerado a partir do `main` pós-correção.

## 1.0.0 — 2026-08-22

- Primeira versão pública oficial do Reino Tribal.
- Início da numeração SemVer.
- Identificadores técnicos RT antigos passam a ser internos e não são exibidos como versão pública.
