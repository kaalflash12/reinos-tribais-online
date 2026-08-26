# Reinos Tribais — Edição de Jogador — STATUS RT90

Data: 2026-08-26

## Estado geral

**NÃO CONCLUÍDO.** Infraestrutura, jogador público, persistência, isolamento Turso, E2E mobile público e o próprio mecanismo RT90 de navegador Edge/Selenium estão comprovados. Resta uma única prova privada: executar o fechamento RT90 no Windows que possui acesso à conta Deno e autenticar a credencial real `reinos_admin` pelo GitHub Pages.

## Concluído e comprovado

- [x] Turso/Deno é a autoridade online do fluxo normal.
- [x] `rt102-admin-recovery.js` legado foi neutralizado como stub inerte.
- [x] `rt85-auth-bridge.js` final: `1.0.6-turso-recovery-complete`.
- [x] Recuperação por e-mail/código antiga é bloqueada em vez de prometer um fluxo inexistente.
- [x] Botões ADM legados `data-admin-recovery` e `data-rt64-recovery` convertem para reset de senha administrativo Turso.
- [x] Rótulos principais de autenticação/landing foram migrados de Supabase para Turso/Deno em runtime.
- [x] RT85 Auth Regression — run `32969519598` — **SUCCESS**.
- [x] RT85 prova parser/sintaxe, UI de login, recovery seguro, conversão RT64 e zero requisições reais ao Supabase legado.
- [x] Player E2E de produção — run `32896601176` — **SUCCESS**: registro, login, Mundo 1, save, load, membership e logout.
- [x] RT80 Public/PR Edge Regression — run `32969474340` — **SUCCESS** no GitHub Pages público.
- [x] RT89 Public Mobile E2E — run `32969474220` — **SUCCESS**.
- [x] RT89 usa Edge `390x844` contra `https://kaalflash12.github.io/reinos-tribais-online/` e API de produção.
- [x] RT89 comprovou 16/16 checks: bridge Turso, API configurada, entrada online, formulário mobile, recovery seguro, registro real, login pela UI, sessão real, Mundo 1 listado/entrado, save, load persistente, membership, sem overflow horizontal global, zero rede Supabase e logout.
- [x] Artefato RT89: `RT89_PUBLIC_MOBILE_PROOF`, artifact id `9607066129`, digest `sha256:d90f07413d997cf6ea550dd80dedffd304dd50b636c83b485f4fba6615a5d0f3`.
- [x] RT90 finalizador criado: `REINO_TRIBAL_FECHAR_ADMIN_PUBLICO.ps1`.
- [x] Runner de navegador real criado: `tools/rt90_admin_public_proof.mjs`.
- [x] RT90 Admin Public Proof Static inicial — run `32969939595` — **SUCCESS**: parser PowerShell e sintaxe/contrato do runner.
- [x] RT90 não imprime a senha e a passa ao runner apenas via variável de ambiente temporária.
- [x] RT90 Admin Public Proof Static/Runtime — run `32970216378` — **SUCCESS**.
- [x] RT90 runtime executou **Deno 2.9.5 + Edge + Selenium + GitHub Pages público real** sem credencial e passou.
- [x] RT90 validate-only comprovou 4/4 checks: bridge Turso final público, UI pública de login visível, zero rede Supabase antes do login e runtime Selenium/Edge operacional.
- [x] RT90 validate-only gerou screenshot real `RT90_VALIDATE_ONLY_PUBLIC_LOGIN.png` e JSON `PROVA_RT90_ADMIN_PUBLICO.json` com `pass:true` e `validate_only:true`.
- [x] Artefato RT90 validate-only: `RT90_VALIDATE_ONLY_PROOF`, artifact id `9607294648`, digest `sha256:bc8cf8ab3354e02ff6c2958f589410f419a86b23762e43e2e4e54db2224f1f3f`.

## Única pendência

- [ ] Executar `REINO_TRIBAL_FECHAR_ADMIN_PUBLICO.ps1` no Windows autorizado.
- [ ] O script executará o FIX17 canônico e só aceitará `CREDENCIAIS_ADMIN_REINO_TRIBAL.txt` com `VALIDACAO: login + admin_status + dashboard = PASS`.
- [ ] Depois usará o mesmo runner Edge/Selenium já provado no CI, entrará no GitHub Pages como `reinos_admin`, exigirá `rt60_admin_token`, exigirá `.rt60-admin-shell`, exigirá `admin_status.ok`, verificará zero rede Supabase e salvará `RT90_ADMIN_DASHBOARD_PUBLICO.png` + `PROVA_RT90_ADMIN_PUBLICO.json`.
- [ ] Só aceitar conclusão quando o marcador final for `REINO_TRIBAL_ADMIN_PUBLICO_RT90_PASS`.

## Critério 100%

**Somente após `REINO_TRIBAL_ADMIN_PUBLICO_RT90_PASS` o projeto pode ser marcado como 100% concluído neste checkpoint.**
