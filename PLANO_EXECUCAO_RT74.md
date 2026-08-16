# PLANO DE EXECUÇÃO — REINOS TRIBAIS RT74

## Objetivo
Consolidar a execução solicitada sem reconstruir o jogo: Ranked, eventos sazonais/periódicos, save local, polimento visual e conteúdo exclusivo de monstros/eventos.

## Passo a passo
1. **Inventário mestre** — manter como referência a lista histórica de 714 requisitos e não transformar auditoria histórica em prova da build atual.
2. **Regressões atuais** — bloquear carregamento infinito, aldeia vazia, prédio fullscreen, versões visuais misturadas e falhas de save.
3. **Save local** — chave `_local` obrigatória ao entrar offline, limpeza de estado de mundo online, teste de localStorage, backup redundante e autosave a cada 15 s.
4. **Ranked** — matchmaking/pontuação existentes + tabela de prêmios visível + finalização automática + recompensa pendente sem duplicidade.
5. **Eventos sazonais obrigatórios** — Festival da Grande Colheita e Solstício de Inverno agendados anualmente; registros 2026/2027 criados.
6. **Eventos periódicos** — servidor mantém janela rolante semanal com Feira, Horda, Paladinos, Besta, Domínio, Colosso, Assalto, Fronteiras e Torneio.
7. **Monstros de evento** — trigger real na ativação; seleção por `event_tags`; copiar template_key, nome, família, HP, descrição, habilidades e recompensas.
8. **Exclusivos** — Guarda Real, segundo Paladino temporário, Coroa Dourada, títulos e itens exclusivos entram nos fluxos de resgate.
9. **UI de Eventos** — calendário, status, data, participação/Top3/Top1, habilidades e drops legíveis.
10. **UI Ranked** — mostrar participação, Top10, Top3, 1º e término da temporada.
11. **Polimento visual leve** — cards, badges, hierarquia e indicador de save; sem novo layout massivo.
12. **Validação estática** — dois HTMLs idênticos, versão RT74, JavaScript validado pelo Node e marcadores obrigatórios.
13. **Backend** — verificar migration, trigger, calendário, active/scheduled/finished, Edge rt-world v5 e premiação da temporada.
14. **Windows** — instalador único baixa a build publicada, preserva backup, valida SHA/marcadores e abre o arquivo local correto.
15. **Regressão contínua** — qualquer erro de runtime no Windows é FAIL; não converter screenshot/asset opcional em falso PASS funcional.
