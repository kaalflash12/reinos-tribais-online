# RT76 — Benchmark técnico de engines, scripts e automação

Estas referências passam a ser usadas como **benchmark funcional e de UX**, não como dependência obrigatória e não como autorização para copiar assets proprietários. O objetivo é trazer para o Reinos Tribais, de forma nativa e controlada pelo próprio servidor/jogo, as ideias úteis de planejamento, automação, gerenciamento multi-aldeia, mapa, mercado, guerra, eventos, filas, alertas e testes.

## 1. Tribal Wars — scripts, planejamento e automação

Referências fornecidas:
- https://github.com/victorgare/tribalwars
- https://github.com/selcukeraslan/tribalwarsMarketBot
- https://github.com/filipkowal/tribalwars-bot
- https://github.com/topics/tribal-wars
- https://github.com/shinko-to-kuma/tribalwars
- https://github.com/ExtremeGTX/TribalWars-Scripts
- https://github.com/ibratabian17/TribalWarsBot
- https://github.com/torridity/twtactics
- https://github.com/TribalWars-Scripts/TribalWars-Scripts
- https://github.com/MagusTilus/TribalWarsMap

### Padrões a incorporar nativamente
1. Assistente de saque com modelos A/B/C configuráveis.
2. Localizador e ordenação de aldeias bárbaras por distância/risco/último saque.
3. Planejador de ataques e fakes em lote.
4. Planejamento por horário de chegada com cálculo inverso do horário de saída.
5. Identificação/inteligência de ataques chegando.
6. Filtros de mapa e informação avançada no hover/inspector.
7. Recrutamento contínuo por meta.
8. Coleta automática por regras configuráveis.
9. Envio/pedido inteligente de recursos entre aldeias.
10. Automação de mercado com limites, preços-alvo e segurança de estoque.
11. Gestão multi-aldeia e atalhos de navegação.
12. Histórico e métricas de farm/ataque para escolher o próximo alvo.

### Estado no RT75/RT76 antes da próxima rodada
- EXISTE: planejador de ataque/fake.
- EXISTE: localizador de bárbaras.
- EXISTE: Assistente de Saque A/B/C.
- EXISTE: Gerente de Conta para construção/recrutamento por metas.
- EXISTE: coleta, mercado, remessas, mapa com filtros/zoom/minimapa.
- PARCIAL: planejamento em lote ainda não possui fila operacional completa com horário de chegada.
- PARCIAL: inteligência de ataques chegando existe via Torre de Vigia/comandos, mas precisa virar painel tático comparável às ferramentas de TW.
- PARCIAL: mercado não possui ainda motor automático configurável de preço/estoque/rotas.
- PARCIAL: farm ainda precisa memória por alvo, resultado anterior, lotação do saque, muralha e sugestão automática de modelo.

## 2. Travian — engines, filas, mundo e servidor

Referências fornecidas:
- https://github.com/Shadowss/TravianZ
- https://github.com/yi12345/TravianZ
- https://github.com/topics/travian
- https://github.com/Erol444/TravianBot
- https://github.com/stefanpejcic/Travian-Bot
- https://github.com/brainfoolong/travian-tactics
- https://github.com/dominikb/travian-bot

### Padrões a incorporar
1. Engine de filas por tempo para construção, tropas, pesquisa e eventos.
2. Regras de mundo configuráveis por servidor.
3. Alianças, mensagens, relatórios e mapa como sistemas persistentes, não mockups.
4. Eventos de servidor e tarefas agendadas idempotentes.
5. Painel administrativo para controlar mundo, jogadores, eventos e conteúdo.
6. Cálculo preciso de distância, velocidade e horário de chegada.
7. Separação clara entre estado persistido, simulação e interface.

## 3. OGame — engine moderna, tarefas e testes

Referências fornecidas:
- https://github.com/lanedirt/OGameX
- https://github.com/jkroepke/2Moons
- https://github.com/xmke/xnova
- https://github.com/steemnova/steemnova
- https://github.com/alaingilbert/ogame
- https://github.com/mariobros242/ogame-bot
- https://github.com/SorrowSky/OGame-Automizer
- https://github.com/mats-t/ogame-universe-view

### Padrões a incorporar
1. Testes unitários/funcionais e regressão automática a cada build.
2. Task runner interno para tarefas periódicas, sem depender do navegador ficar em primeiro plano.
3. Detecção de ataque/ameaça e alertas operacionais.
4. Funções centrais reutilizáveis para tempo de construção, distância, velocidade e filas.
5. Cache/estado sincronizado com backend como fonte de verdade no online.
6. Observabilidade: histórico de comandos, falhas, execução e auditoria.

## 4. Ikariam / Grepolis — gestão multi-cidade e melhoria de interface

Referências fornecidas:
- https://github.com/Ikabot-Collective/ikabot
- https://github.com/verza22/glarium
- https://github.com/advocaite/ikariam
- https://github.com/topics/grepolis
- https://github.com/Dio-David/Dio-Tools
- https://github.com/Quackmaster/Grepolis-Quack-Toolsammlung
- https://github.com/The-Hyted/Grepolis-Bot
- https://github.com/The-EG/ikariam-scripts
- https://github.com/badkaktus/Ikariam-bot

### Padrões a incorporar
1. Gestão multi-cidade/aldeia a partir de uma única tela.
2. Alertas e resumo operacional sem trocar de tela dezenas de vezes.
3. Transporte/redistribuição de recursos por necessidade.
4. Ferramentas de guerra, apoio e logística em lote.
5. Widgets compactos que melhoram a UI sem cobrir o mapa/jogo.
6. Configurações persistentes por usuário.

## 5. Engines clássicas

Referência:
- https://github.com/bataru/devana

Uso: somente como referência histórica de arquitetura de browser strategy. Não copiar código/arte sem confirmar licença e adequação técnica.

## 6. Regras de implementação no Reinos Tribais

- As automações serão **funções nativas do nosso próprio jogo**, sujeitas a regras do mundo, cooldown, custo, permissões e logs.
- Nenhuma automação dependerá de Tampermonkey/Selenium para o jogador usar o Reinos Tribais.
- O online usa o backend como fonte de verdade para ações competitivas.
- Automação não pode gerar recursos/tropas do nada: somente executar ações que o jogador poderia executar manualmente e que satisfaçam custo/pré-requisitos.
- Todas as ações em lote precisam de limites, cancelamento e histórico.
- Toda feature crítica deve receber teste E2E real em Chromium e, quando online, teste transacional no Supabase.
- Não copiar assets proprietários de Tribal Wars, Travian, OGame, Ikariam ou Grepolis.

## 7. Fila RT76 derivada destas referências

### P0 — corretude e prova
- Regressão Chromium desktop/mobile de todas as telas.
- 19 prédios clicáveis e quatro tiers visuais reais.
- Save local/reload.
- Construção, recrutamento, pesquisa, combate, mercado e Paladino E2E.
- Ranked/eventos/monstros/inventário transacionais no Supabase.

### P1 — Central de Guerra
- Planejador em lote.
- Ataques/fakes por horário de chegada.
- Classificador de incoming e painel de inteligência.
- Cálculo de distância/tempo/velocidade visível antes do envio.
- Histórico por alvo.

### P1 — Assistente de Farm
- Templates editáveis.
- Resultado anterior por bárbara.
- Indicador de saque cheio/parcial/vazio.
- Muralha/risco/última visita.
- Próximo alvo recomendado.
- Lote com limite de comandos por ciclo.

### P1 — Gerente de Conta 2.0
- Metas por aldeia/grupo.
- Construção e recrutamento contínuos.
- Pesquisa por prioridade.
- Redistribuição inteligente de recursos.
- Coleta automática opcional.
- Histórico de decisões do gerente.

### P1 — Mercado 2.0
- Estoque mínimo por recurso.
- Preço/razão-alvo.
- Rotas entre aldeias.
- Equalização automática configurável.
- Limites por ciclo e log.

### P2 — UX estratégica
- Visão geral multi-aldeia compacta.
- Notas/etiquetas por aldeia.
- Favoritos e grupos.
- Alertas de fila vazia, armazém cheio, ataque chegando, tropas paradas e evento prestes a iniciar.
- Widgets reposicionáveis apenas se não degradarem responsividade.

## 8. Critério de conclusão

Nenhum item acima será marcado como PASS apenas por existir uma função ou texto. PASS = interface conectada + estado real + persistência + execução + teste correspondente.
