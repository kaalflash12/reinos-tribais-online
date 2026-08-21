-- RT84 - Interações mundiais sem recompensas grátis/spam.
-- Aplicada em produção no projeto Supabase rlyiwlwzrdgvcwawrnpl como
-- rt84_world_interactions_limits_and_logs.

create table if not exists public.rt84_world_interaction_log(
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null,
  user_id uuid not null,
  village_id uuid not null,
  node_id uuid not null,
  node_type text not null,
  action text not null,
  success boolean not null,
  supply_cost jsonb not null default '{}'::jsonb,
  reward jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists rt84_world_log_user_day_idx on public.rt84_world_interaction_log(world_id,user_id,created_at desc);
create index if not exists rt84_world_log_node_idx on public.rt84_world_interaction_log(world_id,user_id,node_id,created_at desc);
alter table public.rt84_world_interaction_log enable row level security;
drop policy if exists rt84_world_log_select_own on public.rt84_world_interaction_log;
create policy rt84_world_log_select_own on public.rt84_world_interaction_log for select to authenticated using(user_id=auth.uid());

create or replace function public.rt84_interact_world_node(p_world_id uuid,p_node_id uuid,p_action text default 'main',p_village_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare
  uid uuid:=auth.uid(); n public.world_nodes%rowtype; v public.villages%rowtype; pw public.player_worlds%rowtype;
  res jsonb; inv jsonb; reward jsonb:='{}'::jsonb; cost jsonb; item_id text; price int:=0; lvl int; dist numeric; woodc bigint; clayc bigint; ironc bigint;
  cap bigint; amount bigint; spy int:=0; total_units bigint:=0; chance numeric:=1; roll numeric:=random(); success boolean:=true; daily_count int:=0; cd interval:=interval '45 minutes';
begin
  if uid is null then raise exception 'Sessão inválida'; end if;
  if not exists(select 1 from public.player_worlds where world_id=p_world_id and user_id=uid and not is_suspended) then raise exception 'Jogador não participa deste mundo'; end if;
  select * into n from public.world_nodes where id=p_node_id and world_id=p_world_id for update;
  if n.id is null then raise exception 'Ponto mundial não encontrado'; end if;
  if n.type in ('monsters','world_boss','bandit_camp','forest','quarry','iron_mine','farmstead','fort','abandoned_tower') then raise exception 'Este ponto exige o sistema RT83 com formação explícita'; end if;
  if not n.available or (n.respawn_at is not null and n.respawn_at>now()) then raise exception 'Ponto indisponível'; end if;
  perform public.rt83_check_cooldown(p_world_id,uid,'interaction',n.id);
  select count(*) into daily_count from public.rt84_world_interaction_log where world_id=p_world_id and user_id=uid and created_at>=date_trunc('day',now());
  if daily_count>=30 then raise exception 'Limite diário de 30 expedições/interações mundiais atingido'; end if;
  if p_village_id is not null then select * into v from public.villages where id=p_village_id and world_id=p_world_id and owner_user_id=uid for update; end if;
  if v.id is null then select * into v from public.villages where world_id=p_world_id and owner_user_id=uid order by points desc limit 1 for update; end if;
  if v.id is null then raise exception 'Aldeia online não encontrada'; end if;
  select * into pw from public.player_worlds where world_id=p_world_id and user_id=uid for update;
  lvl:=greatest(1,coalesce(n.level,1)); dist:=sqrt(power(n.x-v.x,2)+power(n.y-v.y,2));
  woodc:=greatest(80,round(80+lvl*28+dist*14)); clayc:=greatest(60,round(60+lvl*22+dist*10)); ironc:=greatest(40,round(40+lvl*18+dist*8));
  if n.type in ('merchant','caravan','trade_port') then woodc:=greatest(60,round(woodc*.65)); clayc:=greatest(40,round(clayc*.55)); ironc:=greatest(30,round(ironc*.45)); end if;
  cost:=jsonb_build_object('wood',woodc,'clay',clayc,'iron',ironc);
  res:=coalesce(v.resources,'{}'::jsonb); inv:=coalesce(pw.inventory,'{}'::jsonb);
  if public.rt_jsonb_num(res,'wood')<woodc or public.rt_jsonb_num(res,'clay')<clayc or public.rt_jsonb_num(res,'iron')<ironc then raise exception 'Suprimentos insuficientes para a expedição'; end if;
  res:=jsonb_set(res,'{wood}',to_jsonb(public.rt_jsonb_num(res,'wood')-woodc),true);
  res:=jsonb_set(res,'{clay}',to_jsonb(public.rt_jsonb_num(res,'clay')-clayc),true);
  res:=jsonb_set(res,'{iron}',to_jsonb(public.rt_jsonb_num(res,'iron')-ironc),true);
  spy:=coalesce((v.units->>'spy')::int,0); select coalesce(sum((value)::bigint),0) into total_units from jsonb_each_text(coalesce(v.units,'{}'::jsonb));
  if n.type in ('ruins','rare_ruins') then chance:=least(.92,greatest(.35,.62 + least(.20,spy/500.0) + least(.10,total_units/5000.0) - lvl*.025)); success:=roll<=chance; cd:=case when n.type='rare_ruins' then interval '75 minutes' else interval '50 minutes' end;
  elsif n.type in ('shrine','altar') then chance:=least(.95,greatest(.55,.78 + least(.12,spy/800.0)-lvl*.015)); success:=roll<=chance; cd:=case when n.type='altar' then interval '90 minutes' else interval '60 minutes' end;
  elsif n.type in ('merchant','caravan','trade_port') then success:=true; cd:=interval '40 minutes';
  else chance:=.70; success:=roll<=chance; end if;
  if success then
    cap:=public.rt79_storage_capacity(coalesce((v.buildings->>'warehouse')::int,0));
    if n.type in ('merchant','caravan','trade_port') then
      item_id:=coalesce(n.state->>'itemId',case (abs(n.x+n.y+lvl)%7) when 0 then 'resource_chest' when 1 then 'spyglass' when 2 then 'production_banner' when 3 then 'war_banner' when 4 then 'construction_scroll' when 5 then 'recruitment_scroll' else 'loyalty_seal' end);
      price:=greatest(20,coalesce((n.state->>'price')::int,70+lvl*12));
      if p_action in ('trade','buy','main') then
        if coalesce(pw.crowns,0)<price then raise exception 'Coroas insuficientes para esta oferta'; end if;
        inv:=jsonb_set(inv,array[item_id],to_jsonb(coalesce((inv->>item_id)::int,0)+1),true);
        update public.player_worlds set crowns=crowns-price,inventory=inv,updated_at=now() where world_id=p_world_id and user_id=uid;
        reward:=jsonb_build_object('kind','item','item_id',item_id,'price',price,'label','Negociação concluída');
      else
        amount:=least(1200+lvl*120,greatest(0,cap-public.rt_jsonb_num(res,'wood'))::bigint);
        res:=jsonb_set(res,'{wood}',to_jsonb(public.rt_jsonb_num(res,'wood')+amount),true);
        reward:=jsonb_build_object('kind','escort','wood',amount,'label','Escolta concluída');
      end if;
    elsif n.type in ('ruins','rare_ruins') then
      amount:=600+lvl*350;
      res:=jsonb_set(res,'{wood}',to_jsonb(least(cap,public.rt_jsonb_num(res,'wood')+amount)),true);
      res:=jsonb_set(res,'{clay}',to_jsonb(least(cap,public.rt_jsonb_num(res,'clay')+round(amount*.8))),true);
      res:=jsonb_set(res,'{iron}',to_jsonb(least(cap,public.rt_jsonb_num(res,'iron')+round(amount*.7))),true);
      item_id:=case when n.type='rare_ruins' then 'scouting_pack' else 'resource_chest' end;
      inv:=jsonb_set(inv,array[item_id],to_jsonb(coalesce((inv->>item_id)::int,0)+1),true);
      update public.player_worlds set crowns=crowns+(8+lvl*3),inventory=inv,updated_at=now() where world_id=p_world_id and user_id=uid;
      reward:=jsonb_build_object('kind','treasure','item_id',item_id,'crowns',8+lvl*3,'label','Expedição bem-sucedida');
    elsif n.type in ('shrine','altar') then
      update public.player_worlds set crowns=crowns+(5+lvl*2),updated_at=now() where world_id=p_world_id and user_id=uid;
      reward:=jsonb_build_object('kind','blessing','crowns',5+lvl*2,'label','Bênção recebida');
    else reward:=jsonb_build_object('kind','success','label','Interação concluída'); end if;
  else
    reward:=jsonb_build_object('kind','failed','label','Expedição fracassou','chance',round(chance*100));
  end if;
  update public.villages set resources=res,updated_at=now() where id=v.id;
  update public.world_nodes set available=false,respawn_at=now()+cd,updated_at=now() where id=n.id;
  insert into public.rt83_world_action_cooldowns(world_id,user_id,target_kind,target_id,available_at,last_action_at) values(p_world_id,uid,'interaction',n.id,now()+cd,now()) on conflict(world_id,user_id,target_kind,target_id) do update set available_at=excluded.available_at,last_action_at=now();
  insert into public.rt84_world_interaction_log(world_id,user_id,village_id,node_id,node_type,action,success,supply_cost,reward) values(p_world_id,uid,v.id,n.id,n.type,coalesce(p_action,'main'),success,cost,reward);
  return reward||jsonb_build_object('success',success,'node_id',n.id,'type',n.type,'supply_cost',cost,'cooldown_until',now()+cd,'daily_used',daily_count+1,'daily_limit',30,'chance',round(chance*100));
end $function$;

create or replace function public.rt60_interact_world_node(p_world_id uuid,p_node_id uuid,p_action text default 'main')
returns jsonb language plpgsql security definer set search_path to 'public','auth','pg_temp' as $function$
declare n public.world_nodes%rowtype;
begin
 select * into n from public.world_nodes where id=p_node_id and world_id=p_world_id;
 if n.id is null then raise exception 'Ponto mundial não encontrado'; end if;
 if n.type in ('monsters','world_boss','bandit_camp','forest','quarry','iron_mine','farmstead','fort','abandoned_tower') then raise exception 'Use o sistema RT83 com formação explícita'; end if;
 return public.rt84_interact_world_node(p_world_id,p_node_id,p_action,null);
end $function$;

revoke all on function public.rt84_interact_world_node(uuid,uuid,text,uuid) from public,anon;
grant execute on function public.rt84_interact_world_node(uuid,uuid,text,uuid) to authenticated;
revoke all on function public.rt60_interact_world_node(uuid,uuid,text) from public,anon;
grant execute on function public.rt60_interact_world_node(uuid,uuid,text) to authenticated;
