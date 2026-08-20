-- RT82.1 — player_worlds: manter somente campos ainda não migrados para RPC.
-- Campos competitivos já autoritativos (crowns, premium, flags_inventory)
-- deixam de aceitar UPDATE direto do cliente autenticado.

revoke insert, delete, truncate, references, trigger on table public.player_worlds from anon, authenticated;
revoke update on table public.player_worlds from anon, authenticated;
grant select on table public.player_worlds to authenticated;

grant update (player_name, hero, inventory, last_seen_at, updated_at)
on table public.player_worlds to authenticated;

-- Intencionalmente NÃO concedidos:
-- crowns          -> RT82 Premium/diária e demais RPCs autoritativas
-- premium         -> RT82 Premium/diária
-- flags_inventory -> RT82 assign/combine/remove flag
-- points          -> derivado das aldeias pelo servidor
-- academy_coins   -> RT82 mint/recruit nobre
-- research        -> RT82 pesquisas server-side
