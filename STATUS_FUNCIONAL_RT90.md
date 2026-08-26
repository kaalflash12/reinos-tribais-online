# Reinos Tribais — Edição de Jogador — STATUS RT91

Data: 2026-08-26

## Estado geral

**NÃO CONCLUÍDO.** Todo o bloco público e automatizável está comprovado: Turso/Deno, jogador público, persistência, isolamento de Supabase, desktop, mobile, GitHub Pages, Edge/Selenium e o fechamento administrativo protegido contra downgrade. Também foi tentado o fechamento integral via GitHub Actions, mas o repositório não possui secret Deno configurado. Nenhuma mutação foi executada nessa tentativa. Resta uma única prova privada: autorizar a conta Deno em um Windows e executar `REINO_TRIBAL_FECHAR_ADMIN_PUBLICO.ps1` para gerar a credencial real `reinos_admin` e comprovar o dashboard administrativo pelo GitHub Pages.

## Concluído e comprovado

- [x] Turso/Deno é a autoridade online do fluxo normal.
- [x] `rt102-admin-recovery.js` legado foi neutralizado como stub inerte.
- [x] `rt85-auth-bridge.js` final: `1.0.6-turso-recovery-complete`.
- [x] Recuperação legada por e-mail/código é bloqueada; reset administrativo é encaminhado ao fluxo Turso.
- [x] RT85 Auth Regression — run `32969519598` — **SUCCESS**.
- [x] Player E2E de produção — run `32896601176` — **SUCCESS**: registro, login, Mundo 1, save, load, membership e logout.
- [x] RT89 Public Mobile E2E — run `32969474220` — **SUCCESS** em Edge `390x844`, com 16/16 checks e zero rede Supabase.
- [x] Artefato RT89: `RT89_PUBLIC_MOBILE_PROOF`, id `9607066129`, digest `sha256:d90f07413d997cf6ea550dd80dedffd304dd50b636c83b485f4fba6615a5d0f3`.
- [x] Foi detectado antes da execução que o antigo FIX17 faria source deploy do commit `d5d1edadd9f33b612a233c4feed0e06ec97203bc`, mais de 185 commits atrás do `main`, removendo inclusive o realtime atual.
- [x] O caminho perigoso foi substituído por `REINO_TRIBAL_ADMIN_SAFE_RT91.ps1`.
- [x] RT91 possui contrato `ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91`.
- [x] RT91 valida o SHA atual do `main`, baixa e verifica `deno/main.js`, `api/reino.js`, `api/admin.js`, `api/realtime.js` e schema Turso antes de qualquer alteração privada.
- [x] RT91 exige as rotas realtime `/ws` e `/api/realtime/ws` e executa `deno check deno/main.js`.
- [x] RT91 não contém source deploy; a única mutação Deno permitida é `deno deploy env update-value` para `RT_ADMIN_PASSWORD` e `RT_ADMIN_RECOVERY_KEY`.
- [x] `REINO_TRIBAL_CONTINUAR.ps1` aponta exclusivamente para RT91 e rejeita executor que contenha source deploy.
- [x] `REINO_TRIBAL_FECHAR_ADMIN_PUBLICO.ps1` exige `Contrato: ADMIN_AUTHORITY_NO_SOURCE_DEPLOY_RT91` e `ANTI_DOWNGRADE: nenhum source deploy executado = PASS` antes de aceitar a credencial.
- [x] RT90/RT91 gate — run `32971460199`, head `eedb994be627a091f4d60285c5ad3720d3cbfec0` — **SUCCESS**.
- [x] No gate RT90/RT91 passaram: parsers PowerShell, contrato anti-downgrade, launcher canônico RT91 `ValidateOnly`, `deno check` do `main` atual, CORS, sintaxe do runner e Edge/Selenium público real.
- [x] Artefato RT90/RT91 validate-only: `RT90_VALIDATE_ONLY_PROOF`, id `9607803649`, digest `sha256:e9cc2fd2e07e790378810e1ed0e42b745453ede77a102658bf73696f65bc5ede`.
- [x] RT80 Functional Browser Regression — run `32971460073` — **SUCCESS**.
- [x] RT80 Public/PR Edge Regression — run `32971460117` — **SUCCESS**.
- [x] Diagnose Reino Tribal Pages — run `32971460113` — **SUCCESS**.
- [x] Public Edge do checkpoint RT91 — run `32971882617` — **SUCCESS**, incluindo Edge functional, persistência da prova e upload do artefato.
- [x] Functional Browser do checkpoint RT91 — run `32971882506` — **SUCCESS**.
- [x] Diagnose do checkpoint RT91 — run `32971882530` — **SUCCESS**.
- [x] O runner RT90 usa senha somente via variável de ambiente temporária e não a imprime.
- [x] O fechamento final exige `rt60_admin_token`, `.rt60-admin-shell`, `admin_status.ok`, dashboard, zero rede Supabase e screenshot real.
- [x] Criado workflow `RT91 Final Admin Authorized` para tentar o fechamento sem depender do PC quando houver secret Deno válido no GitHub Actions.
- [x] Probe seguro do GitHub Actions — run `32972268802`, job `98188563681` — executado.
- [x] O probe confirmou `RT91_NO_DENO_SECRET_CONFIGURED`: `DENO_DEPLOY_TOKEN`, `DENO_TOKEN`, `DENO_ACCESS_TOKEN` e `DENO_AUTH_TOKEN` estavam vazios no runner.
- [x] Como o probe falhou na primeira etapa, setup Deno, validação do app, troca de secrets e fechamento RT90 foram todos **SKIPPED**; portanto essa tentativa realizou **zero mutações de produção**.

## Única pendência

- [ ] Executar `REINO_TRIBAL_FECHAR_ADMIN_PUBLICO.ps1` em Windows autorizado na conta Deno.
- [ ] Autorizar o device login oficial do Deno quando o navegador abrir.
- [ ] RT91 atualizar somente os dois secrets ADM, sem source deploy.
- [ ] Confirmar `VALIDACAO: login + admin_status + dashboard = PASS`.
- [ ] Confirmar `ANTI_DOWNGRADE: nenhum source deploy executado = PASS`.
- [ ] RT90 entrar no GitHub Pages como `reinos_admin`, obter `rt60_admin_token`, renderizar `.rt60-admin-shell`, passar `admin_status`, manter zero rede Supabase e gerar `RT90_ADMIN_DASHBOARD_PUBLICO.png` + `PROVA_RT90_ADMIN_PUBLICO.json`.
- [ ] Exigir o marcador final `REINO_TRIBAL_ADMIN_PUBLICO_RT90_PASS`.

## Critério 100%

**Somente após `REINO_TRIBAL_ADMIN_PUBLICO_RT90_PASS` e `ANTI_DOWNGRADE_NO_SOURCE_DEPLOY_PASS` o projeto pode ser marcado como 100% concluído neste checkpoint.**
