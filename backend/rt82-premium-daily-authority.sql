create or replace function public.rt82_activate_premium_service(p_world_id uuid, p_service text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  uid uuid:=auth.uid(); pw public.player_worlds%rowtype; p jsonb; inv jsonb; price bigint; addms bigint:=604800000;
  nowms bigint:=floor(extract(epoch from clock_timestamp())*1000)::bigint; own_count int; boost_key text;
begin
  if uid is null then raise exception 'Sessão inválida'; end if;
  select * into pw from public.player_worlds where world_id=p_world_id and user_id=uid for update;
  if pw.id is null then raise exception 'Jogador não participa deste mundo'; end if;
  price:=case p_service when 'standard' then 200 when 'manager' then 300 when 'farm' then 160 when 'wood20' then 120 when 'clay20' then 120 when 'iron20' then 120 when 'market35' then 150 when 'gather25' then 140 when 'heroReset' then 180 when 'explorePack' then 160 else null end;
  if price is null then raise exception 'Serviço Premium inválido'; end if;
  if coalesce(pw.crowns,0)<price then raise exception 'Pontos Premium insuficientes'; end if;
  p:=coalesce(pw.premium,'{}'::jsonb); inv:=coalesce(pw.inventory,'{}'::jsonb);
  if p_service='manager' then
    select count(*) into own_count from public.villages where world_id=p_world_id and owner_user_id=uid;
    if own_count<5 then raise exception 'O Gerente de Conta exige pelo menos 5 aldeias'; end if;
    if coalesce((p->>'standardUntil')::bigint,0)<=nowms then raise exception 'Ative primeiro a Conta Premium'; end if;
  end if;
  if p_service='standard' then p:=jsonb_set(p,'{standardUntil}',to_jsonb(greatest(nowms,coalesce((p->>'standardUntil')::bigint,0))+addms),true);
  elsif p_service='manager' then p:=jsonb_set(p,'{managerUntil}',to_jsonb(greatest(nowms,coalesce((p->>'managerUntil')::bigint,0))+addms),true);
  elsif p_service='farm' then p:=jsonb_set(p,'{farmAssistantUntil}',to_jsonb(greatest(nowms,coalesce((p->>'farmAssistantUntil')::bigint,0))+addms),true);
  elsif p_service in ('wood20','clay20','iron20') then
    boost_key:=case p_service when 'wood20' then 'wood' when 'clay20' then 'clay' else 'iron' end;
    p:=jsonb_set(p,array['resourceBoostUntil',boost_key],to_jsonb(greatest(nowms,coalesce((p#>>array['resourceBoostUntil',boost_key])::bigint,0))+addms),true);
  elsif p_service='market35' then p:=jsonb_set(p,'{tradeLicense}','true'::jsonb,true);
  elsif p_service='gather25' then p:=jsonb_set(p,'{gatherUntil}',to_jsonb(greatest(nowms,coalesce((p->>'gatherUntil')::bigint,0))+addms),true);
  elsif p_service='heroReset' then inv:=jsonb_set(inv,'{hero_reset}',to_jsonb(coalesce((inv->>'hero_reset')::int,0)+1),true);
  elsif p_service='explorePack' then inv:=jsonb_set(inv,'{scouting_pack}',to_jsonb(coalesce((inv->>'scouting_pack')::int,0)+1),true);
  end if;
  p:=jsonb_set(p,'{crowns}',to_jsonb(coalesce(pw.crowns,0)-price),true);
  update public.player_worlds set crowns=coalesce(crowns,0)-price,premium=p,inventory=inv,updated_at=now() where id=pw.id;
  return jsonb_build_object('service',p_service,'price',price,'crowns',coalesce(pw.crowns,0)-price,'premium',p,'inventory',inv);
end $$;

create or replace function public.rt82_claim_daily_reward(p_world_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
 uid uuid:=auth.uid(); pw public.player_worlds%rowtype; p jsonb; inv jsonb; nowms bigint:=floor(extract(epoch from clock_timestamp())*1000)::bigint; lastms bigint; cooldown bigint:=72000000;
begin
 if uid is null then raise exception 'Sessão inválida'; end if;
 select * into pw from public.player_worlds where world_id=p_world_id and user_id=uid for update;
 if pw.id is null then raise exception 'Jogador não participa deste mundo'; end if;
 p:=coalesce(pw.premium,'{}'::jsonb); inv:=coalesce(pw.inventory,'{}'::jsonb); lastms:=coalesce((p->>'lastDailyClaim')::bigint,0);
 if nowms-lastms<cooldown then raise exception 'A recompensa diária ainda não está disponível'; end if;
 p:=jsonb_set(p,'{lastDailyClaim}',to_jsonb(nowms),true);
 p:=jsonb_set(p,'{crowns}',to_jsonb(coalesce(pw.crowns,0)+75),true);
 inv:=jsonb_set(inv,'{resource_chest}',to_jsonb(coalesce((inv->>'resource_chest')::int,0)+1),true);
 update public.player_worlds set crowns=coalesce(crowns,0)+75,premium=p,inventory=inv,updated_at=now() where id=pw.id;
 return jsonb_build_object('crowns',coalesce(pw.crowns,0)+75,'premium',p,'inventory',inv,'claimed_at',nowms);
end $$;

revoke all on function public.rt82_activate_premium_service(uuid,text) from public,anon;
grant execute on function public.rt82_activate_premium_service(uuid,text) to authenticated;
revoke all on function public.rt82_claim_daily_reward(uuid) from public,anon;
grant execute on function public.rt82_claim_daily_reward(uuid) to authenticated;
