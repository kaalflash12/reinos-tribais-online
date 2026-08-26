# RT80 Mobile E2E Checkpoint

Gate canônico: `.github/workflows/rt79-public-pages-regression.yml`.

O runner `tools/rt79_edge_public_regression.py` deve provar em GitHub Pages, viewport 390×844:

- navegação mobile pelas telas principais;
- construção e persistência após reload;
- criação automática de jogador temporário no backend Deno/Turso;
- login pela interface pública;
- bridge RT85 ativa e tráfego legado Supabase bloqueado/interceptado;
- health de produção;
- save + load do mesmo marcador no Mundo 1;
- screenshots antes/depois do reload e da sessão online.

Somente um run público verde fecha este checkpoint.
