# RT87 — Normal Cold Boot

Estado aplicado na branch de validação:

- `index.html` e `JOGAR_REINOS_TRIBAIS.html` continuam sendo o mesmo cliente completo.
- Os nove módulos externos RT76/RT79 são carregados com `defer`, preservando ordem e permitindo download paralelo sem bloquear o parser.
- `rt76-master-core.js` não executa o scheduler estratégico enquanto não existe estado de jogo.
- O gate `RT87 Normal Cold Boot` abre a URL normal, com cache frio e sem `?fast=1`, verifica a entrada online e o bridge RT85.
- RT86 AI Director e os agentes NPC permanecem server-side e independentes do carregamento do navegador.
