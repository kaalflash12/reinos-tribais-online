# Reinos Tribais — Status funcional atual RT84

Este arquivo é o estado **atual** do produto. O `BENCHMARK_RT76_TRIBAL_TRAVIAN_OGAME_IKARIAM.md` permanece como histórico de lacunas antigas e não deve ser usado sozinho para afirmar que os itens abaixo continuam parciais.

Critério: uma função só aparece como implementada aqui quando existe interface/estado, execução real, persistência correspondente quando online e mecanismo de teste/gate ou RPC verificável.

## Estratégia e guerra — IMPLEMENTADO
- Central de guerra em `rt79-suite.js`/RT81: múltiplos alvos, lotes, waves, horário de chegada e cálculo inverso de partida.
- Inteligência de incoming: classificação, risco, vigia/torre e força visível.
- Agendamento online autoritativo: RT81/Supabase.
- Gate: `RT81 Master Spec Regression` + regressão funcional RT80.

## Farm Assistant — IMPLEMENTADO
- Modelos A/B/C editáveis.
- Distância, muralha, risco, último resultado, último saque, lotação, confiança e cooldown.
- Recomendação server-side: `rt79_farm_recommend`.
- Lote inteligente server-side: `rt79_farm_batch_smart`.

## Gerente de Conta 2.0 — IMPLEMENTADO
- Metas por aldeia e por grupo.
- Metas de prédios e unidades.
- Prioridade de pesquisa.
- Construção/recrutamento/pesquisa server-side: `rt78_manager_tick` + `rt79_manager_tick`.
- Redistribuição real: `rt79_equalize_resources`.
- Histórico operacional: `rt78_action_log`.

## Mercado 2.0 — IMPLEMENTADO
- Rotas persistentes, estoque mínimo, target/ratio, limites por ciclo e equalização.
- `rt78_market_route_upsert`, `rt79_market_autotrade`, `rt79_equalize_resources`.
- Transferências possuem deslocamento real no servidor.

## Multi-aldeia / grupos / alertas — IMPLEMENTADO
- Grupos, favoritos, tags, notas, visão compacta e logística.
- Alertas de incoming, filas vazias, armazém quase cheio, tropas ociosas e eventos.
- Frontend RT79 + estado/persistência RT78/79.

## PvE e pontos de recurso RT83 — IMPLEMENTADO E AUTORITATIVO
- Formação explícita de tropas.
- Suprimentos consumidos.
- Baixas permanentes.
- HP do inimigo persistente.
- Derrota sem loot.
- Saque limitado por sobreviventes/capacidade.
- Cooldown global e por alvo.
- Relatórios persistentes.
- RPCs: `rt83_attack_world_monster`, `rt83_interact_world_node` e helpers RT83.
- Tabelas: `rt83_pve_battle_reports`, `rt83_world_action_cooldowns`.
- Gate Windows/Edge: `RT83 Real World Combat Regression` (14/14 na integração RT83).

## Ruínas / santuários / altares / caravanas / mercadores / portos RT84 — IMPLEMENTADO
- Suprimentos obrigatórios por nível e distância.
- 20 s entre expedições/interações mundiais.
- Cooldown individual por alvo.
- Limite diário de 30 ações por jogador/mundo.
- Ruínas e santuários podem fracassar; falha consome suprimento e não concede prêmio.
- Comércio cobra Coroas e também custo de expedição.
- Recompensas de recurso respeitam Armazém.
- Log persistente: `rt84_world_interaction_log`.
- RPC autoritativo: `rt84_interact_world_node`.
- `rt60_interact_world_node` foi transformado em dispatcher seguro e não burla RT83/RT84.
- Offline: `rt84-world-actions.js` com as mesmas classes de limite/custo/cooldown.
- Gate: `.github/workflows/rt84-world-actions-regression.yml`.

## Administração — IMPLEMENTADO
- Renderer administrativo real com 15 painéis, editores de jogador/aldeia/eventos/bosses, mercado/ranked/tribos/segurança/auditoria.
- Gate: `RT80 Admin Visual Regression`.

## Autoridade online — IMPLEMENTADA NOS SISTEMAS COMPETITIVOS ACIMA
- RT81/RT82 endureceram mutações competitivas.
- RT83/RT84 movem combate/interações do mundo para RPC transacional.
- O cliente não é fonte autoritativa para recompensa PvE online.

## Regra de regressão
Nenhum item acima deve ser rebaixado para lógica local ou recompensa direta sem custo. Qualquer alteração em combate mundial/interações deve passar os gates RT83/RT84 e os gates funcionais/visuais existentes antes de merge.