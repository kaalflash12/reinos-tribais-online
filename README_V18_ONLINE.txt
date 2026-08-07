REINOS TRIBAIS V18 ONLINE — SUPABASE + GITHUB PAGES

BACKEND JA CONFIGURADO
Projeto Supabase: rlyiwlwzrdgvcwawrnpl
Regiao: Sao Paulo (sa-east-1)
Mundo online: Mundo 1

O QUE ESTA ONLINE NESTA VERSAO
- Cadastro/login por e-mail e senha no Supabase Auth.
- Save completo por conta no Supabase.
- O mesmo reino pode ser carregado em outro computador/navegador depois do login.
- Save local continua como seguranca/fallback.
- Migracao automatica do save local da V17 para V18.
- Resumo do jogador sincronizado no banco.
- Estrutura SQL preparada para mundos, jogadores, aldeias, comandos, relatorios, mensagens, tribos, mercado e pontos do mundo.

PUBLICAR NA INTERNET DE GRACA
Execute PUBLICAR_ONLINE_GRATIS.cmd. O script instala Git/GitHub CLI se necessario, pede autorizacao no GitHub, cria um repositorio publico e ativa GitHub Pages. Ao final ele mostra o endereco https://SEUUSUARIO.github.io/reinos-tribais-online/

IMPORTANTE
A V18 ja resolve conta + save na nuvem + acesso do mesmo reino de qualquer lugar. O PvP totalmente autoritativo em servidor e a simulacao global enquanto nenhum navegador esta aberto sao uma etapa adicional; a logica principal ainda roda no cliente, como na V17.

PUBLICACAO SEM INSTALAR CLI
---------------------------
O arquivo PUBLICAR_ONLINE_GRATIS.ps1 nao usa Git, GitHub CLI, winget nem Node.
Ele publica diretamente pela API do GitHub usando apenas o PowerShell do Windows.
Na primeira execucao, o navegador abre para voce criar um token classico com escopo repo. Depois basta colar o token na janela do PowerShell.
