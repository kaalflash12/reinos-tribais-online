-- RT83 — combate mundial real, reproduzível a partir do estado de produção validado.
-- Fonte de verdade: Supabase public schema em 2026-08-21.

create table if not exists public.rt83_world_action_cooldowns(
  world_id uuid not null references public.worlds(id) on delete cascade,
  user_id uuid not null,
  target_kind text not null,
  target_id uuid not null,
  available_at timestamptz not null,
  last_action_at timestamptz not null default now(),
  primary key(world_id,user_id,target_kind,target_id)
);
create index if not exists rt83_world_action_cooldowns_user_idx on public.rt83_world_action_cooldowns(world_id,user_id,last_action_at desc);
alter table public.rt83_world_action_cooldowns enable row level security;

create table if not exists public.rt83_pve_battle_reports(
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  user_id uuid not null,
  village_id uuid not null references public.villages(id) on delete cascade,
  target_kind text not null,
  target_id uuid not null,
  target_name text not null default '',
  victory boolean not null,
  damage bigint not null default 0,
  enemy_hp_before bigint not null default 0,
  enemy_hp_after bigint not null default 0,
  player_power bigint not null default 0,
  enemy_power bigint not null default 0,
  troops_committed jsonb not null default '{}'::jsonb,
  losses jsonb not null default '{}'::jsonb,
  survivors jsonb not null default '{}'::jsonb,
  supply_cost jsonb not null default '{}'::jsonb,
  loot jsonb not null default '{}'::jsonb,
  crowns bigint not null default 0,
  cooldown_until timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists rt83_pve_battle_reports_user_idx on public.rt83_pve_battle_reports(world_id,user_id,created_at desc);
alter table public.rt83_pve_battle_reports enable row level security;
drop policy if exists rt83_reports_select_own on public.rt83_pve_battle_reports;
create policy rt83_reports_select_own on public.rt83_pve_battle_reports for select to authenticated using(user_id=auth.uid());

create or replace function public.rt83_troop_count(p_troops jsonb)
returns bigint language sql immutable set search_path to 'pg_catalog' as $$
 select coalesce(sum(greatest(0,value::bigint)),0)::bigint from jsonb_each_text(coalesce(p_troops,'{}'::jsonb));
$$;

create or replace function public.rt83_validate_troops(p_available jsonb,p_selected jsonb)
returns boolean language plpgsql immutable set search_path to 'pg_catalog' as $$
declare r record; total bigint:=0;
begin
 for r in select key,value::bigint qty from jsonb_each_text(coalesce(p_selected,'{}'::jsonb)) loop
   if r.qty<0 then return false; end if;
   if r.qty=0 then continue; end if;
   if r.key in ('militia','spy') then return false; end if;
   if r.qty>coalesce((p_available->>r.key)::bigint,0) then return false; end if;
   total:=total+r.qty;
 end loop;
 return total>0;
end $$;

create or replace function public.rt83_losses(p_troops jsonb,p_ratio numeric)
returns jsonb language plpgsql immutable set search_path to 'pg_catalog' as $$
declare r record; outj jsonb:='{}'::jsonb; l bigint; total bigint:=0; first_key text:=null; first_qty bigint:=0; ratio numeric:=least(.95,greatest(0,coalesce(p_ratio,0)));
begin
 for r in select key,value::bigint qty from jsonb_each_text(coalesce(p_troops,'{}'::jsonb)) where value::bigint>0 loop
   if first_key is null then first_key:=r.key; first_qty:=r.qty; end if;
   l:=least(r.qty,floor(r.qty*ratio)::bigint);
   if l>0 then outj:=jsonb_set(outj,array[r.key],to_jsonb(l),true); total:=total+l; end if;
 end loop;
 if total=0 and first_key is not null and first_qty>0 and ratio>0 then outj:=jsonb_set(outj,array[first_key],to_jsonb(1),true); end if;
 return outj;
end $$;

create or replace function public.rt83_survivors(p_selected jsonb,p_losses jsonb)
returns jsonb language plpgsql immutable set search_path to 'pg_catalog' as $$
declare r record; outj jsonb:='{}'::jsonb; q bigint;
begin
 for r in select key,value::bigint qty from jsonb_each_text(coalesce(p_selected,'{}'::jsonb)) loop
   q:=greatest(0,r.qty-coalesce((p_losses->>r.key)::bigint,0));
   if q>0 then outj:=jsonb_set(outj,array[r.key],to_jsonb(q),true); end if;
 end loop;
 return outj;
end $$;

create or replace function public.rt83_subtract_troops(p_available jsonb,p_losses jsonb)
returns jsonb language plpgsql immutable set search_path to 'pg_catalog' as $$
declare r record; outj jsonb:=coalesce(p_available,'{}'::jsonb); q bigint;
begin
 for r in select key,value::bigint qty from jsonb_each_text(coalesce(p_losses,'{}'::jsonb)) loop
   q:=greatest(0,coalesce((outj->>r.key)::bigint,0)-greatest(0,r.qty));
   outj:=jsonb_set(outj,array[r.key],to_jsonb(q),true);
 end loop;
 return outj;
end $$;

create or replace function public.rt83_check_cooldown(p_world_id uuid,p_user_id uuid,p_kind text,p_target_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare until_at timestamptz;
begin
 if exists(select 1 from public.rt83_world_action_cooldowns where world_id=p_world_id and user_id=p_user_id and last_action_at>now()-interval '20 seconds') then
   raise exception 'Aguarde 20 segundos entre expedições mundiais';
 end if;
 select available_at into until_at from public.rt83_world_action_cooldowns where world_id=p_world_id and user_id=p_user_id and target_kind=p_kind and target_id=p_target_id;
 if until_at is not null and until_at>now() then raise exception 'Este alvo está em recarga até %',until_at; end if;
end $$;

create or replace function public.rt83_interact_world_node(p_world_id uuid,p_node_id uuid,p_action text default 'main',p_village_id uuid default null,p_troops jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
 uid uuid:=auth.uid(); nd public.world_nodes%rowtype; v public.villages%rowtype; cnt bigint; pp bigint; ep bigint; maxhp bigint; before_hp bigint; after_hp bigint; dmg bigint; victory boolean; dist numeric; ratio numeric; losses jsonb; survivors jsonb; supply bigint; sw bigint; sc bigint; si bigint; res jsonb; cap bigint; carry numeric; amount bigint:=0; lw bigint:=0; lc bigint:=0; li bigint:=0; cd_seconds int; cd_until timestamptz; resource text;
begin
 if uid is null then raise exception 'Sessão inválida'; end if;
 if exists(select 1 from public.rt_player_controls where world_id=p_world_id and user_id=uid and status<>'active') then raise exception 'Conta bloqueada neste mundo'; end if;
 select * into nd from public.world_nodes where id=p_node_id and world_id=p_world_id for update;
 if nd.id is null then raise exception 'Ponto mundial não encontrado'; end if;
 if nd.type not in ('monsters','bandit_camp','forest','quarry','iron_mine','farmstead','fort','abandoned_tower') then raise exception 'Este tipo de ponto não usa combate RT83'; end if;
 if not nd.available and nd.respawn_at is not null and nd.respawn_at>now() then raise exception 'Ponto indisponível até %',nd.respawn_at; end if;
 if p_village_id is null then select * into v from public.villages where world_id=p_world_id and owner_user_id=uid order by points desc limit 1 for update;
 else select * into v from public.villages where id=p_village_id and world_id=p_world_id and owner_user_id=uid for update; end if;
 if v.id is null then raise exception 'Aldeia do jogador não encontrada'; end if;
 if not public.rt83_validate_troops(v.units,p_troops) then raise exception 'Formação inválida ou tropas indisponíveis'; end if;
 perform public.rt83_check_cooldown(p_world_id,uid,'node',nd.id);
 cnt:=public.rt83_troop_count(p_troops); pp:=public.rt50_unit_power(p_troops); if pp<=0 then raise exception 'A formação não possui poder de combate'; end if;
 dist:=sqrt(power(v.x-nd.x,2)+power(v.y-nd.y,2)); supply:=ceil(cnt*(1.3+dist*.08)+greatest(1,nd.level)*15); sw:=ceil(supply*.45); sc:=ceil(supply*.25); si:=greatest(0,supply-sw-sc);
 res:=coalesce(v.resources,'{}'::jsonb); if public.rt_jsonb_num(res,'wood')<sw or public.rt_jsonb_num(res,'clay')<sc or public.rt_jsonb_num(res,'iron')<si then raise exception 'Suprimentos insuficientes: madeira %, argila %, ferro %',sw,sc,si; end if;
 res:=jsonb_set(res,'{wood}',to_jsonb(public.rt_jsonb_num(res,'wood')-sw),true); res:=jsonb_set(res,'{clay}',to_jsonb(public.rt_jsonb_num(res,'clay')-sc),true); res:=jsonb_set(res,'{iron}',to_jsonb(public.rt_jsonb_num(res,'iron')-si),true);
 maxhp:=case when nd.type='monsters' then greatest(2500,coalesce((nd.state->>'max_hp')::bigint,nd.level*5200)) when nd.type='bandit_camp' then greatest(1800,coalesce((nd.state->>'max_hp')::bigint,nd.level*3900)) else greatest(900,round(nd.level*1700*case when nd.type in ('fort','abandoned_tower') then 1.55 else 1 end)::bigint) end;
 before_hp:=coalesce((nd.state->>'rt83_guard_hp')::bigint,coalesce((nd.state->>'hp')::bigint,maxhp)); if before_hp<=0 and (nd.respawn_at is null or nd.respawn_at<=now()) then before_hp:=maxhp; end if;
 ep:=case when nd.type='monsters' then round(nd.level*1050+maxhp/38)::bigint when nd.type='bandit_camp' then round(nd.level*880+maxhp/42)::bigint else round((nd.level*620+maxhp/48)*case when nd.type in ('fort','abandoned_tower') then 1.55 else 1 end)::bigint end;
 dmg:=greatest(1,round(pp*(.075+random()*.045))::bigint); after_hp:=greatest(0,before_hp-dmg); victory:=after_hp=0;
 ratio:=least(.90,greatest(.015,(ep::numeric/(pp+ep))*case when victory then .13 else .32 end*(.86+random()*.28))); if pp*(.88+random()*.24)<ep*(.88+random()*.24) then ratio:=least(.92,ratio*1.45); end if;
 losses:=public.rt83_losses(p_troops,ratio); survivors:=public.rt83_survivors(p_troops,losses); cap:=public.rt79_storage_capacity(coalesce((v.buildings->>'warehouse')::int,0)); carry:=public.rt_carry_capacity(survivors);
 if victory then
   amount:=least(floor(carry)::bigint,greatest(200,nd.level*900)); resource:=case nd.type when 'forest' then 'wood' when 'quarry' then 'clay' when 'iron_mine' then 'iron' else null end;
   if resource='wood' then lw:=least(amount,greatest(0,cap-public.rt_jsonb_num(res,'wood')::bigint)); elsif resource='clay' then lc:=least(amount,greatest(0,cap-public.rt_jsonb_num(res,'clay')::bigint)); elsif resource='iron' then li:=least(amount,greatest(0,cap-public.rt_jsonb_num(res,'iron')::bigint)); else lw:=least(floor(amount/3.0)::bigint,greatest(0,cap-public.rt_jsonb_num(res,'wood')::bigint)); lc:=least(floor(amount/3.0)::bigint,greatest(0,cap-public.rt_jsonb_num(res,'clay')::bigint)); li:=least(greatest(0,amount-lw-lc),greatest(0,cap-public.rt_jsonb_num(res,'iron')::bigint)); end if;
   res:=jsonb_set(res,'{wood}',to_jsonb(public.rt_jsonb_num(res,'wood')+lw),true); res:=jsonb_set(res,'{clay}',to_jsonb(public.rt_jsonb_num(res,'clay')+lc),true); res:=jsonb_set(res,'{iron}',to_jsonb(public.rt_jsonb_num(res,'iron')+li),true);
 end if;
 update public.villages set units=public.rt83_subtract_troops(units,losses),resources=res,updated_at=now() where id=v.id;
 if victory then update public.world_nodes set owner_user_id=uid,available=false,respawn_at=now()+interval '45 minutes',state=coalesce(state,'{}'::jsonb)||jsonb_build_object('rt83_guard_hp',0,'rt83_guard_max_hp',maxhp,'rt83_last_damage',dmg,'rt83_last_attacker',uid),updated_at=now() where id=nd.id;
 else update public.world_nodes set state=coalesce(state,'{}'::jsonb)||jsonb_build_object('rt83_guard_hp',after_hp,'rt83_guard_max_hp',maxhp,'rt83_last_damage',dmg,'rt83_last_attacker',uid),updated_at=now() where id=nd.id; end if;
 cd_seconds:=greatest(60,round(60+dist*12+nd.level*10)::int); cd_until:=now()+make_interval(secs=>cd_seconds);
 insert into public.rt83_world_action_cooldowns(world_id,user_id,target_kind,target_id,available_at,last_action_at) values(p_world_id,uid,'node',nd.id,cd_until,now()) on conflict(world_id,user_id,target_kind,target_id) do update set available_at=excluded.available_at,last_action_at=excluded.last_action_at;
 insert into public.rt83_pve_battle_reports(world_id,user_id,village_id,target_kind,target_id,target_name,victory,damage,enemy_hp_before,enemy_hp_after,player_power,enemy_power,troops_committed,losses,survivors,supply_cost,loot,cooldown_until)
 values(p_world_id,uid,v.id,'node',nd.id,nd.type,victory,dmg,before_hp,after_hp,pp,ep,p_troops,losses,survivors,jsonb_build_object('wood',sw,'clay',sc,'iron',si),jsonb_build_object('wood',lw,'clay',lc,'iron',li),cd_until);
 return jsonb_build_object('victory',victory,'damage',dmg,'enemy_hp_before',before_hp,'enemy_hp_after',after_hp,'enemy_max_hp',maxhp,'player_power',pp,'enemy_power',ep,'losses',losses,'survivors',survivors,'supply_cost',jsonb_build_object('wood',sw,'clay',sc,'iron',si),'loot',jsonb_build_object('wood',lw,'clay',lc,'iron',li),'crowns',0,'cooldown_until',cd_until,'node_id',nd.id,'type',nd.type);
end $$;

create or replace function public.rt83_attack_world_monster(p_world_id uuid,p_monster_id uuid,p_village_id uuid default null,p_troops jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
 uid uuid:=auth.uid(); m public.world_monsters%rowtype; v public.villages%rowtype;
 cnt bigint; pp bigint; ep bigint; dmg bigint; before_hp bigint; after_hp bigint; killed boolean; dist numeric; ratio numeric; losses jsonb; survivors jsonb;
 supply bigint; sw bigint; sc bigint; si bigint; res jsonb; cap bigint; carry numeric; base_loot bigint; lw bigint:=0; lc bigint:=0; li bigint:=0; crown_gain bigint:=0; cd_seconds int; cd_until timestamptz;
begin
 if uid is null then raise exception 'Sessão inválida'; end if;
 if exists(select 1 from public.rt_player_controls where world_id=p_world_id and user_id=uid and status<>'active') then raise exception 'Conta bloqueada neste mundo'; end if;
 select * into m from public.world_monsters where id=p_monster_id and world_id=p_world_id for update;
 if m.id is null or m.status<>'active' then raise exception 'Monstro indisponível'; end if;
 if m.despawn_at is not null and m.despawn_at<=now() then raise exception 'Este monstro já deixou o mapa'; end if;
 if p_village_id is null then select * into v from public.villages where world_id=p_world_id and owner_user_id=uid order by points desc limit 1 for update;
 else select * into v from public.villages where id=p_village_id and world_id=p_world_id and owner_user_id=uid for update; end if;
 if v.id is null then raise exception 'Aldeia do jogador não encontrada'; end if;
 if not public.rt83_validate_troops(v.units,p_troops) then raise exception 'Formação inválida ou tropas indisponíveis'; end if;
 perform public.rt83_check_cooldown(p_world_id,uid,'monster',m.id);
 cnt:=public.rt83_troop_count(p_troops); pp:=public.rt50_unit_power(p_troops); if pp<=0 then raise exception 'A formação não possui poder de combate'; end if;
 dist:=sqrt(power(v.x-m.x,2)+power(v.y-m.y,2)); supply:=ceil(cnt*(1.3+dist*.08)+greatest(1,m.level)*15); sw:=ceil(supply*.45); sc:=ceil(supply*.25); si:=greatest(0,supply-sw-sc);
 res:=coalesce(v.resources,'{}'::jsonb); if public.rt_jsonb_num(res,'wood')<sw or public.rt_jsonb_num(res,'clay')<sc or public.rt_jsonb_num(res,'iron')<si then raise exception 'Suprimentos insuficientes: madeira %, argila %, ferro %',sw,sc,si; end if;
 res:=jsonb_set(res,'{wood}',to_jsonb(public.rt_jsonb_num(res,'wood')-sw),true); res:=jsonb_set(res,'{clay}',to_jsonb(public.rt_jsonb_num(res,'clay')-sc),true); res:=jsonb_set(res,'{iron}',to_jsonb(public.rt_jsonb_num(res,'iron')-si),true);
 before_hp:=greatest(0,m.hp); ep:=greatest(100,m.level*2400+greatest(1,m.max_hp)/42); dmg:=greatest(1,round(pp*(.075+random()*.045))::bigint); after_hp:=greatest(0,before_hp-dmg); killed:=after_hp=0;
 ratio:=least(.90,greatest(.015,(ep::numeric/(pp+ep))*case when killed then .13 else .32 end*(.86+random()*.28))); if pp*(.88+random()*.24)<ep*(.88+random()*.24) then ratio:=least(.92,ratio*1.45); end if;
 losses:=public.rt83_losses(p_troops,ratio); survivors:=public.rt83_survivors(p_troops,losses); cap:=public.rt79_storage_capacity(coalesce((v.buildings->>'warehouse')::int,0)); carry:=public.rt_carry_capacity(survivors);
 if killed then
   base_loot:=least(floor(carry)::bigint,greatest(0,m.level*5400));
   lw:=least(floor(base_loot/3.0)::bigint,greatest(0,cap-(public.rt_jsonb_num(res,'wood'))::bigint)); lc:=least(floor(base_loot/3.0)::bigint,greatest(0,cap-(public.rt_jsonb_num(res,'clay'))::bigint)); li:=least(greatest(0,base_loot-lw-lc),greatest(0,cap-(public.rt_jsonb_num(res,'iron'))::bigint));
   res:=jsonb_set(res,'{wood}',to_jsonb(public.rt_jsonb_num(res,'wood')+lw),true); res:=jsonb_set(res,'{clay}',to_jsonb(public.rt_jsonb_num(res,'clay')+lc),true); res:=jsonb_set(res,'{iron}',to_jsonb(public.rt_jsonb_num(res,'iron')+li),true); crown_gain:=greatest(20,m.level*12);
 end if;
 update public.villages set units=public.rt83_subtract_troops(units,losses),resources=res,updated_at=now() where id=v.id;
 update public.world_monsters set hp=after_hp,status=case when killed then 'defeated' else status end,updated_at=now() where id=m.id;
 insert into public.world_monster_hits(monster_id,world_id,user_id,village_id,damage) values(m.id,p_world_id,uid,v.id,dmg);
 if killed and crown_gain>0 then update public.player_worlds set crowns=coalesce(player_worlds.crowns,0)+crown_gain,updated_at=now() where world_id=p_world_id and user_id=uid; end if;
 cd_seconds:=greatest(90,round((90+dist*12+m.level*10)*1.7)::int); cd_until:=now()+make_interval(secs=>cd_seconds);
 insert into public.rt83_world_action_cooldowns(world_id,user_id,target_kind,target_id,available_at,last_action_at) values(p_world_id,uid,'monster',m.id,cd_until,now()) on conflict(world_id,user_id,target_kind,target_id) do update set available_at=excluded.available_at,last_action_at=excluded.last_action_at;
 insert into public.rt83_pve_battle_reports(world_id,user_id,village_id,target_kind,target_id,target_name,victory,damage,enemy_hp_before,enemy_hp_after,player_power,enemy_power,troops_committed,losses,survivors,supply_cost,loot,crowns,cooldown_until)
 values(p_world_id,uid,v.id,'monster',m.id,m.name,killed,dmg,before_hp,after_hp,pp,ep,p_troops,losses,survivors,jsonb_build_object('wood',sw,'clay',sc,'iron',si),jsonb_build_object('wood',lw,'clay',lc,'iron',li),crown_gain,cd_until);
 return jsonb_build_object('victory',killed,'killed',killed,'damage',dmg,'enemy_hp_before',before_hp,'enemy_hp_after',after_hp,'enemy_max_hp',m.max_hp,'player_power',pp,'enemy_power',ep,'losses',losses,'survivors',survivors,'supply_cost',jsonb_build_object('wood',sw,'clay',sc,'iron',si),'loot',jsonb_build_object('wood',lw,'clay',lc,'iron',li),'crowns',crown_gain,'cooldown_until',cd_until,'name',m.name,'level',m.level);
end $$;

revoke all on function public.rt83_attack_world_monster(uuid,uuid,uuid,jsonb) from public,anon;
revoke all on function public.rt83_interact_world_node(uuid,uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.rt83_attack_world_monster(uuid,uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.rt83_interact_world_node(uuid,uuid,text,uuid,jsonb) to authenticated,service_role;
