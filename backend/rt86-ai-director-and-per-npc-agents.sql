-- RT86 — AI Director administrativo + um agente persistente por jogador NPC.
-- Produção: Supabase rlyiwlwzrdgvcwawrnpl.
-- A conta ai_director recebe senha aleatória desconhecida e não é destinada a login humano.

create table if not exists public.rt86_ai_director_state(
  world_id uuid primary key references public.worlds(id) on delete cascade,
  principal_admin_id uuid references public.rt_admin_accounts(id) on delete set null,
  enabled boolean not null default true,
  mode text not null default 'adaptive',
  target_difficulty numeric not null default 1.00,
  pace_multiplier numeric not null default 1.00,
  event_pressure integer not null default 5,
  monster_pressure integer not null default 5,
  player_median_points numeric not null default 0,
  npc_median_points numeric not null default 0,
  last_tick timestamptz,
  next_tick timestamptz not null default now(),
  state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint rt86_director_target_chk check(target_difficulty between 0.65 and 1.50),
  constraint rt86_director_pace_chk check(pace_multiplier between 0.60 and 1.50),
  constraint rt86_director_pressure_chk check(event_pressure between 1 and 10 and monster_pressure between 1 and 10)
);

create table if not exists public.rt86_npc_ai_agents(
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  npc_key text not null,
  display_name text not null,
  personality text not null,
  traits jsonb not null default '{}'::jsonb,
  memory jsonb not null default '{}'::jsonb,
  goals jsonb not null default '{}'::jsonb,
  metrics jsonb not null default '{}'::jsonb,
  cycles bigint not null default 0,
  last_action text,
  last_tick timestamptz,
  next_tick timestamptz not null default now(),
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  unique(world_id,npc_key),
  unique(world_id,display_name)
);

create table if not exists public.rt86_ai_orders(
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references public.worlds(id) on delete cascade,
  agent_id uuid not null references public.rt86_npc_ai_agents(id) on delete cascade,
  source_village_id uuid not null references public.villages(id) on delete cascade,
  target_village_id uuid not null references public.villages(id) on delete cascade,
  command_id uuid references public.commands(id) on delete set null,
  kind text not null default 'attack',
  troops jsonb not null default '{}'::jsonb,
  survivors jsonb not null default '{}'::jsonb,
  loot jsonb not null default '{}'::jsonb,
  status text not null default 'outbound',
  started_at timestamptz not null default now(),
  arrives_at timestamptz not null,
  returns_at timestamptz,
  resolved_at timestamptz,
  outcome jsonb not null default '{}'::jsonb,
  constraint rt86_ai_orders_status_chk check(status in ('outbound','returning','complete','cancelled'))
);

create table if not exists public.rt86_ai_decision_log(
  id bigint generated always as identity primary key,
  world_id uuid not null references public.worlds(id) on delete cascade,
  agent_id uuid references public.rt86_npc_ai_agents(id) on delete set null,
  actor text not null,
  category text not null,
  action text not null,
  target jsonb not null default '{}'::jsonb,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.rt86_monster_balance(
  monster_id uuid primary key references public.world_monsters(id) on delete cascade,
  world_id uuid not null references public.worlds(id) on delete cascade,
  base_level integer not null,
  base_hp bigint not null,
  balanced_level integer not null,
  balanced_hp bigint not null,
  player_median_points numeric not null default 0,
  balanced_at timestamptz not null default now()
);

create index if not exists rt86_agents_due_idx on public.rt86_npc_ai_agents(world_id,next_tick) where enabled;
create index if not exists rt86_orders_due_idx on public.rt86_ai_orders(world_id,status,arrives_at,returns_at);
create index if not exists rt86_orders_target_idx on public.rt86_ai_orders(world_id,target_village_id,status);
create index if not exists rt86_decision_world_time_idx on public.rt86_ai_decision_log(world_id,created_at desc);

alter table public.rt86_ai_director_state enable row level security;
alter table public.rt86_npc_ai_agents enable row level security;
alter table public.rt86_ai_orders enable row level security;
alter table public.rt86_ai_decision_log enable row level security;
alter table public.rt86_monster_balance enable row level security;
revoke all on public.rt86_ai_director_state,public.rt86_npc_ai_agents,public.rt86_ai_orders,public.rt86_ai_decision_log,public.rt86_monster_balance from anon,authenticated;

insert into public.rt_admin_accounts(username,password_hash,role,active,display_name,updated_at)
values('ai_director',extensions.crypt(gen_random_uuid()::text,extensions.gen_salt('bf',12)),'ai_director',true,'Diretor IA • Nivelador Global',now())
on conflict(username) do update set role='ai_director',active=true,display_name='Diretor IA • Nivelador Global',updated_at=now();

create or replace function public.rt86_seed_npc_agents(p_world_id uuid)
returns integer language plpgsql security definer set search_path='public','pg_temp' as $$
declare n integer:=0;
begin
  insert into public.rt86_npc_ai_agents(world_id,npc_key,display_name,personality,traits,memory,goals,metrics,next_tick)
  select p_world_id,'npc_'||substr(md5(v.owner_name),1,12),v.owner_name,
    (array['raider','warden','merchant','scholar','opportunist','conqueror','diplomat','builder'])[1+mod(abs(hashtext(v.owner_name)::bigint),8)],
    jsonb_build_object('aggression',20+mod(abs(hashtext(v.owner_name||':agg')::bigint),81),'risk',15+mod(abs(hashtext(v.owner_name||':risk')::bigint),76),'economy',25+mod(abs(hashtext(v.owner_name||':eco')::bigint),76),'defense',20+mod(abs(hashtext(v.owner_name||':def')::bigint),81),'research',20+mod(abs(hashtext(v.owner_name||':res')::bigint),81),'diplomacy',10+mod(abs(hashtext(v.owner_name||':dip')::bigint),91),'expansion',15+mod(abs(hashtext(v.owner_name||':exp')::bigint),86)),
    jsonb_build_object('known_targets','{}'::jsonb,'recent_losses',0,'recent_wins',0,'last_enemy',null),
    jsonb_build_object('economy','grow','army','balanced','research','adaptive','territory','hold'),
    jsonb_build_object('villages',count(*),'points',sum(v.points)),now()+make_interval(secs=>mod(abs(hashtext(v.owner_name||':tick')::bigint),300)::int)
  from public.villages v where v.world_id=p_world_id and v.owner_kind='ai' group by v.owner_name
  on conflict(world_id,npc_key) do update set display_name=excluded.display_name,metrics=excluded.metrics,updated_at=now();
  get diagnostics n=row_count; return n;
end $$;

create or replace function public.rt86_sub_troops(p_base jsonb,p_take jsonb)
returns jsonb language plpgsql immutable set search_path='public','pg_temp' as $$
declare r record; outj jsonb:=coalesce(p_base,'{}'::jsonb); cur bigint; q bigint;
begin
  for r in select key,(value::text)::bigint qty from jsonb_each_text(coalesce(p_take,'{}'::jsonb)) loop
    cur:=coalesce((outj->>r.key)::bigint,0); q:=greatest(0,r.qty);
    if q>cur then raise exception 'Tropa indisponivel: %',r.key; end if;
    outj:=jsonb_set(outj,array[r.key],to_jsonb(cur-q),true);
  end loop; return outj;
end $$;

create or replace function public.rt86_attack_detachment(p_units jsonb,p_ratio numeric)
returns jsonb language sql immutable set search_path='public','pg_temp' as $$
select coalesce(jsonb_object_agg(key,to_jsonb(greatest(0,floor((value::text)::numeric*greatest(0.08,least(0.45,p_ratio)))::bigint))) filter(where floor((value::text)::numeric*greatest(0.08,least(0.45,p_ratio)))>=1),'{}'::jsonb)
from jsonb_each_text(coalesce(p_units,'{}'::jsonb)) where key in ('spear','sword','axe','archer','light','marcher','heavy','ram','catapult','paladin')
$$;

create or replace function public.rt86_ai_schedule_order(p_agent_id uuid,p_source_village_id uuid,p_target_village_id uuid,p_troops jsonb,p_kind text default 'attack')
returns uuid language plpgsql security definer set search_path='public','pg_temp' as $$
declare ag public.rt86_npc_ai_agents%rowtype; s public.villages%rowtype; t public.villages%rowtype; oid uuid; cid uuid; d numeric; travel_seconds int;
begin
  select * into ag from public.rt86_npc_ai_agents where id=p_agent_id and enabled for update;
  if ag.id is null then raise exception 'Agente IA invalido'; end if;
  if exists(select 1 from public.rt86_ai_orders where agent_id=ag.id and status in('outbound','returning')) then raise exception 'Agente ja possui ordem em transito'; end if;
  select * into s from public.villages where id=p_source_village_id and world_id=ag.world_id for update;
  select * into t from public.villages where id=p_target_village_id and world_id=ag.world_id;
  if s.id is null or t.id is null or s.owner_kind<>'ai' or s.owner_name<>ag.display_name or s.id=t.id then raise exception 'Origem ou alvo IA invalido'; end if;
  if coalesce(public.rt_attack_power(p_troops),0)<=0 then raise exception 'Formacao IA sem poder de ataque'; end if;
  update public.villages set units=public.rt86_sub_troops(units,p_troops),updated_at=now() where id=s.id;
  d:=sqrt(power(s.x-t.x,2)+power(s.y-t.y,2)); travel_seconds:=greatest(180,least(5400,ceil(greatest(1,d)*90)::int));
  insert into public.rt86_ai_orders(world_id,agent_id,source_village_id,target_village_id,kind,troops,status,started_at,arrives_at)
  values(ag.world_id,ag.id,s.id,t.id,coalesce(nullif(p_kind,''),'attack'),p_troops,'outbound',now(),now()+make_interval(secs=>travel_seconds)) returning id into oid;
  insert into public.commands(world_id,source_village_id,target_village_id,owner_user_id,kind,phase,troops,loot,payload,started_at,arrives_at)
  values(ag.world_id,s.id,t.id,null,'attack','rt86_ai_outbound',p_troops,jsonb_build_object('wood',0,'clay',0,'iron',0),jsonb_build_object('rt86_ai',true,'rt86_order_id',oid,'agent_id',ag.id,'npc',ag.display_name,'travel_seconds',travel_seconds),now(),now()+make_interval(secs=>travel_seconds)) returning id into cid;
  update public.rt86_ai_orders set command_id=cid where id=oid;
  insert into public.rt86_ai_decision_log(world_id,agent_id,actor,category,action,target,data)
  values(ag.world_id,ag.id,ag.display_name,'war','schedule_attack',jsonb_build_object('village_id',t.id,'name',t.name,'owner_kind',t.owner_kind,'owner_name',t.owner_name),jsonb_build_object('order_id',oid,'command_id',cid,'distance',round(d,2),'troops',p_troops,'arrives_at',now()+make_interval(secs=>travel_seconds)));
  return oid;
end $$;

create or replace function public.rt86_ai_resolve_orders(p_world_id uuid)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare o public.rt86_ai_orders%rowtype; s public.villages%rowtype; t public.villages%rowtype; ag public.rt86_npc_ai_agents%rowtype; atk numeric; def numeric; wall int; roll numeric; win boolean; af numeric; df numeric; surv jsonb; defsurv jsonb; carry bigint; lw bigint; lc bigint; li bigint; tr jsonb; sr jsonb; cap bigint; resolved int:=0; returned int:=0; target_uid uuid;
begin
  for o in select * from public.rt86_ai_orders where world_id=p_world_id and status='outbound' and arrives_at<=now() order by arrives_at for update skip locked loop
    select * into s from public.villages where id=o.source_village_id;
    select * into t from public.villages where id=o.target_village_id for update;
    select * into ag from public.rt86_npc_ai_agents where id=o.agent_id for update;
    if s.id is null or t.id is null then update public.rt86_ai_orders set status='cancelled',resolved_at=now(),outcome=jsonb_build_object('error','missing_village') where id=o.id; continue; end if;
    atk:=public.rt_attack_power(o.troops); wall:=coalesce((t.buildings->>'wall')::int,0); def:=public.rt_defense_power(t.units)*(1+wall*0.05); roll:=0.92+random()*0.16; win:=atk*roll>greatest(def,1);
    if win then af:=greatest(0.18,least(0.92,1-(def/greatest(atk,1))*0.55)); df:=greatest(0.00,least(0.25,1-(atk/greatest(def,1))*0.90)); else af:=greatest(0.00,least(0.25,1-(def/greatest(atk,1))*0.90)); df:=greatest(0.18,least(0.92,1-(atk/greatest(def,1))*0.55)); end if;
    surv:=public.rt_scale_troops(o.troops,af); defsurv:=public.rt_scale_troops(t.units,df); tr:=coalesce(t.resources,'{}'::jsonb); lw:=0;lc:=0;li:=0;
    if win then
      carry:=floor(public.rt_carry_capacity(surv));
      lw:=least(floor(coalesce((tr->>'wood')::numeric,0))::bigint,floor(carry/3.0)::bigint,floor(coalesce((tr->>'wood')::numeric,0)*0.25)::bigint);
      lc:=least(floor(coalesce((tr->>'clay')::numeric,0))::bigint,floor(carry/3.0)::bigint,floor(coalesce((tr->>'clay')::numeric,0)*0.25)::bigint);
      li:=least(floor(coalesce((tr->>'iron')::numeric,0))::bigint,greatest(0,carry-lw-lc),floor(coalesce((tr->>'iron')::numeric,0)*0.25)::bigint);
      tr:=jsonb_set(tr,'{wood}',to_jsonb(coalesce((tr->>'wood')::numeric,0)-lw),true); tr:=jsonb_set(tr,'{clay}',to_jsonb(coalesce((tr->>'clay')::numeric,0)-lc),true); tr:=jsonb_set(tr,'{iron}',to_jsonb(coalesce((tr->>'iron')::numeric,0)-li),true);
    end if;
    update public.villages set units=defsurv,resources=tr,updated_at=now() where id=t.id;
    update public.rt86_ai_orders set survivors=surv,loot=jsonb_build_object('wood',lw,'clay',lc,'iron',li),status='returning',returns_at=now()+greatest(interval '3 minutes',arrives_at-started_at),resolved_at=now(),outcome=jsonb_build_object('win',win,'attack_power',round(atk),'defense_power',round(def),'wall',wall,'roll',round(roll,3)) where id=o.id;
    update public.commands set phase='rt86_ai_returning',loot=jsonb_build_object('wood',lw,'clay',lc,'iron',li),returns_at=now()+greatest(interval '3 minutes',o.arrives_at-o.started_at),resolved_at=now(),payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('rt86_outcome',case when win then 'attacker_won' else 'defender_won' end,'survivors',surv) where id=o.command_id;
    update public.rt86_npc_ai_agents set memory=coalesce(memory,'{}'::jsonb)||jsonb_build_object('last_enemy',t.owner_name,'last_result',case when win then 'win' else 'loss' end,'last_battle_at',now(),'recent_wins',coalesce((memory->>'recent_wins')::int,0)+case when win then 1 else 0 end,'recent_losses',coalesce((memory->>'recent_losses')::int,0)+case when win then 0 else 1 end),last_action=case when win then 'attack_win' else 'attack_loss' end,updated_at=now() where id=ag.id;
    insert into public.rt86_ai_decision_log(world_id,agent_id,actor,category,action,target,data) values(p_world_id,ag.id,ag.display_name,'war',case when win then 'battle_win' else 'battle_loss' end,jsonb_build_object('village_id',t.id,'name',t.name,'owner_kind',t.owner_kind,'owner_name',t.owner_name),jsonb_build_object('order_id',o.id,'attack_power',round(atk),'defense_power',round(def),'survivors',surv,'defender_survivors',defsurv,'loot',jsonb_build_object('wood',lw,'clay',lc,'iron',li)));
    target_uid:=t.owner_user_id;
    if target_uid is not null then insert into public.reports(world_id,user_id,category,title,body,icon) values(p_world_id,target_uid,'Combate',case when win then 'Ataque de NPC: sua aldeia foi saqueada' else 'Defesa contra NPC bem-sucedida' end,format('%s atacou %s. Poder atacante %s, defesa %s. Suas tropas restantes: %s. Recursos perdidos: %s madeira, %s argila, %s ferro.',ag.display_name,t.name,round(atk),round(def),defsurv::text,lw,lc,li),'⚔️'); end if;
    resolved:=resolved+1;
  end loop;
  for o in select * from public.rt86_ai_orders where world_id=p_world_id and status='returning' and returns_at<=now() order by returns_at for update skip locked loop
    select * into s from public.villages where id=o.source_village_id for update;
    if s.id is null then update public.rt86_ai_orders set status='cancelled' where id=o.id; continue; end if;
    sr:=coalesce(s.resources,'{}'::jsonb); cap:=public.rt79_storage_capacity(coalesce((s.buildings->>'warehouse')::int,0));
    sr:=jsonb_set(sr,'{wood}',to_jsonb(least(cap,coalesce((sr->>'wood')::numeric,0)+coalesce((o.loot->>'wood')::numeric,0))),true); sr:=jsonb_set(sr,'{clay}',to_jsonb(least(cap,coalesce((sr->>'clay')::numeric,0)+coalesce((o.loot->>'clay')::numeric,0))),true); sr:=jsonb_set(sr,'{iron}',to_jsonb(least(cap,coalesce((sr->>'iron')::numeric,0)+coalesce((o.loot->>'iron')::numeric,0))),true);
    update public.villages set units=public.rt_add_troops(units,o.survivors),resources=sr,updated_at=now() where id=s.id;
    update public.rt86_ai_orders set status='complete' where id=o.id; update public.commands set phase='complete',returns_at=now(),payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('rt86_returned',true) where id=o.command_id; returned:=returned+1;
  end loop;
  return jsonb_build_object('resolved',resolved,'returned',returned);
end $$;

-- RT86.1 é a versão final do agente: personalidade altera agressão e tolerância de risco,
-- e o alvo só é escolhido quando a defesa estimada cabe no risco aceito pelo NPC.
create or replace function public.rt86_ai_agents_tick(p_world_id uuid,p_limit integer default 20)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare ag public.rt86_npc_ai_agents%rowtype; v public.villages%rowtype; tgt public.villages%rowtype; ds public.rt86_ai_director_state%rowtype; r jsonb; b jsonb; u jsonb; ur jsonb; cap bigint; elapsed numeric; pace numeric; build_key text; build_lvl int; build_cost bigint; unit_key text; qty int; rw bigint; rc bigint; ri bigint; research_key text; research_lvl int; research_cost bigint; aggression int; effective_aggression int; risk_trait int; risk_limit numeric; ratio numeric; troops jsonb; attack_est numeric; oid uuid; acted text; n int:=0; built int:=0; recruited int:=0; researched int:=0; attacked int:=0; aborted int:=0;
begin
  select * into ds from public.rt86_ai_director_state where world_id=p_world_id; pace:=coalesce(ds.pace_multiplier,1.0);
  for ag in select * from public.rt86_npc_ai_agents where world_id=p_world_id and enabled and next_tick<=now() order by next_tick limit greatest(1,least(60,p_limit)) for update skip locked loop
    select * into v from public.villages where world_id=p_world_id and owner_kind='ai' and owner_name=ag.display_name order by points asc,updated_at asc limit 1 for update;
    if v.id is null then update public.rt86_npc_ai_agents set enabled=false,updated_at=now() where id=ag.id; continue; end if;
    r:=coalesce(v.resources,'{}'::jsonb); b:=coalesce(v.buildings,'{}'::jsonb); u:=coalesce(v.units,'{}'::jsonb); ur:=coalesce(v.unit_research,'{}'::jsonb); cap:=public.rt79_storage_capacity(coalesce((b->>'warehouse')::int,0)); elapsed:=greatest(5,least(60,extract(epoch from (now()-coalesce(ag.last_tick,now()-interval '10 minutes')))/60));
    r:=jsonb_set(r,'{wood}',to_jsonb(least(cap,coalesce((r->>'wood')::numeric,0)+round((70+coalesce((b->>'timber')::int,0)*42)*elapsed/10*pace))),true); r:=jsonb_set(r,'{clay}',to_jsonb(least(cap,coalesce((r->>'clay')::numeric,0)+round((70+coalesce((b->>'clay')::int,0)*42)*elapsed/10*pace))),true); r:=jsonb_set(r,'{iron}',to_jsonb(least(cap,coalesce((r->>'iron')::numeric,0)+round((65+coalesce((b->>'iron')::int,0)*40)*elapsed/10*pace))),true); acted:='produce';
    build_key:=case ag.personality when 'raider' then (array['barracks','stable','smith','farm','warehouse'])[1+mod(ag.cycles,5)] when 'warden' then (array['wall','farm','warehouse','barracks','smith'])[1+mod(ag.cycles,5)] when 'merchant' then (array['market','warehouse','timber','clay','iron'])[1+mod(ag.cycles,5)] when 'scholar' then (array['smith','academy','warehouse','farm','market'])[1+mod(ag.cycles,5)] when 'conqueror' then (array['barracks','stable','garage','academy','farm'])[1+mod(ag.cycles,5)] when 'builder' then (array['timber','clay','iron','farm','warehouse','main'])[1+mod(ag.cycles,6)] else (array['timber','clay','iron','barracks','market','smith'])[1+mod(ag.cycles,6)] end; build_lvl:=coalesce((b->>build_key)::int,0); build_cost:=220+(build_lvl+1)*180;
    if build_lvl<25 and coalesce((r->>'wood')::numeric,0)>=build_cost and coalesce((r->>'clay')::numeric,0)>=build_cost and coalesce((r->>'iron')::numeric,0)>=round(build_cost*.7) then r:=jsonb_set(r,'{wood}',to_jsonb(coalesce((r->>'wood')::numeric,0)-build_cost),true); r:=jsonb_set(r,'{clay}',to_jsonb(coalesce((r->>'clay')::numeric,0)-build_cost),true); r:=jsonb_set(r,'{iron}',to_jsonb(coalesce((r->>'iron')::numeric,0)-round(build_cost*.7)),true); b:=jsonb_set(b,array[build_key],to_jsonb(build_lvl+1),true); built:=built+1; acted:='build:'||build_key; end if;
    unit_key:=case ag.personality when 'raider' then case when mod(ag.cycles,3)=0 then 'light' else 'axe' end when 'warden' then case when mod(ag.cycles,2)=0 then 'spear' else 'sword' end when 'conqueror' then case when mod(ag.cycles,4)=0 then 'ram' else 'axe' end when 'scholar' then case when mod(ag.cycles,3)=0 then 'spy' else 'spear' end else case when mod(ag.cycles,3)=0 then 'light' when mod(ag.cycles,2)=0 then 'axe' else 'spear' end end; qty:=greatest(1,least(20,round((3+greatest(v.points,1)/1800.0)*pace)::int)); rw:=case unit_key when 'light' then 125 when 'ram' then 300 when 'spy' then 50 when 'sword' then 30 when 'axe' then 60 else 50 end*qty; rc:=case unit_key when 'light' then 100 when 'ram' then 200 when 'spy' then 50 when 'sword' then 30 when 'axe' then 30 else 30 end*qty; ri:=case unit_key when 'light' then 250 when 'ram' then 200 when 'spy' then 20 when 'sword' then 70 when 'axe' then 40 else 10 end*qty;
    if coalesce((r->>'wood')::numeric,0)>=rw and coalesce((r->>'clay')::numeric,0)>=rc and coalesce((r->>'iron')::numeric,0)>=ri then r:=jsonb_set(r,'{wood}',to_jsonb(coalesce((r->>'wood')::numeric,0)-rw),true); r:=jsonb_set(r,'{clay}',to_jsonb(coalesce((r->>'clay')::numeric,0)-rc),true); r:=jsonb_set(r,'{iron}',to_jsonb(coalesce((r->>'iron')::numeric,0)-ri),true); u:=jsonb_set(u,array[unit_key],to_jsonb(coalesce((u->>unit_key)::int,0)+qty),true); recruited:=recruited+1; acted:=acted||'+recruit:'||unit_key; end if;
    if coalesce((b->>'smith')::int,0)>=1 and mod(ag.cycles,3)=0 then research_key:=case ag.personality when 'raider' then 'axe' when 'warden' then 'spear' when 'conqueror' then 'light' when 'scholar' then 'spy' else 'sword' end; research_lvl:=coalesce((ur->>research_key)::int,0); research_cost:=450*(research_lvl+1); if research_lvl<3 and coalesce((r->>'wood')::numeric,0)>=research_cost and coalesce((r->>'clay')::numeric,0)>=round(research_cost*.8) and coalesce((r->>'iron')::numeric,0)>=round(research_cost*1.15) then r:=jsonb_set(r,'{wood}',to_jsonb(coalesce((r->>'wood')::numeric,0)-research_cost),true); r:=jsonb_set(r,'{clay}',to_jsonb(coalesce((r->>'clay')::numeric,0)-round(research_cost*.8)),true); r:=jsonb_set(r,'{iron}',to_jsonb(coalesce((r->>'iron')::numeric,0)-round(research_cost*1.15)),true); ur:=jsonb_set(ur,array[research_key],to_jsonb(research_lvl+1),true); researched:=researched+1; acted:=acted||'+research:'||research_key; end if; end if;
    update public.villages set resources=r,buildings=b,units=u,unit_research=ur,points=points+greatest(1,case when acted like '%build:%' then 3 else 1 end),updated_at=now() where id=v.id;
    aggression:=coalesce((ag.traits->>'aggression')::int,50); risk_trait:=coalesce((ag.traits->>'risk')::int,50); effective_aggression:=greatest(0,least(100,aggression+case ag.personality when 'raider' then 25 when 'conqueror' then 20 when 'opportunist' then 10 when 'warden' then -10 when 'merchant' then -20 when 'scholar' then -10 when 'diplomat' then -25 when 'builder' then -15 else 0 end)); risk_limit:=greatest(.70,least(1.25,.72+risk_trait/220.0+case ag.personality when 'conqueror' then .12 when 'raider' then .08 when 'warden' then -.08 when 'diplomat' then -.08 else 0 end)); ratio:=least(.42,greatest(.12,.12+effective_aggression/300.0)); select units into u from public.villages where id=v.id; troops:=public.rt86_attack_detachment(u,ratio); attack_est:=public.rt_attack_power(troops);
    if effective_aggression>=45 and mod(ag.cycles,3)=0 and attack_est>0 and not exists(select 1 from public.rt86_ai_orders where agent_id=ag.id and status in('outbound','returning')) then
      select * into tgt from public.villages q where q.world_id=p_world_id and q.id<>v.id and not(q.owner_kind='ai' and q.owner_name=ag.display_name) and sqrt(power(q.x-v.x,2)+power(q.y-v.y,2))<=12 and (q.owner_kind<>'player' or (v.points>=q.points*.55 and v.points<=q.points*2.0)) and (q.owner_kind<>'player' or (select count(*) from public.rt86_ai_orders io where io.world_id=p_world_id and io.target_village_id=q.id and io.status='outbound')<2) and public.rt_defense_power(q.units)*(1+coalesce((q.buildings->>'wall')::int,0)*0.05)<=attack_est*risk_limit order by case when q.owner_kind='player' and effective_aggression>=75 then 0 when q.owner_kind='barbarian' then 1 when q.owner_kind='ai' then 2 else 3 end,(public.rt_defense_power(q.units)*(1+coalesce((q.buildings->>'wall')::int,0)*0.05))/greatest(attack_est,1),sqrt(power(q.x-v.x,2)+power(q.y-v.y,2)) limit 1;
      if tgt.id is not null then begin oid:=public.rt86_ai_schedule_order(ag.id,v.id,tgt.id,troops,'attack'); attacked:=attacked+1; acted:=acted||'+attack'; exception when others then aborted:=aborted+1; end; else aborted:=aborted+1; acted:=acted||'+hold:no_safe_target'; end if;
    end if;
    update public.rt86_npc_ai_agents set cycles=cycles+1,last_tick=now(),next_tick=now()+make_interval(secs=>greatest(300,round((900+mod(abs(hashtext(display_name||cycles::text)::bigint),900))/greatest(.65,pace))::int)),last_action=acted,memory=coalesce(memory,'{}'::jsonb)||jsonb_build_object('effective_aggression',effective_aggression,'risk_limit',risk_limit,'last_attack_estimate',round(attack_est)),metrics=jsonb_build_object('villages',(select count(*) from public.villages vv where vv.world_id=p_world_id and vv.owner_kind='ai' and vv.owner_name=ag.display_name),'points',(select coalesce(sum(points),0) from public.villages vv where vv.world_id=p_world_id and vv.owner_kind='ai' and vv.owner_name=ag.display_name),'pace',pace,'effective_aggression',effective_aggression,'risk_limit',round(risk_limit,3)),updated_at=now() where id=ag.id;
    insert into public.rt86_ai_decision_log(world_id,agent_id,actor,category,action,target,data) values(p_world_id,ag.id,ag.display_name,'agent_tick',acted,jsonb_build_object('village_id',v.id,'name',v.name),jsonb_build_object('personality',ag.personality,'pace',pace,'cycles',ag.cycles+1,'attack_estimate',round(attack_est),'risk_limit',round(risk_limit,3))); n:=n+1;
  end loop;
  return jsonb_build_object('processed',n,'built',built,'recruited',recruited,'researched',researched,'attacks_scheduled',attacked,'attacks_aborted_unsafe',aborted);
end $$;

create or replace function public.rt86_ai_director_tick(p_world_id uuid)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare aid uuid; ds public.rt86_ai_director_state%rowtype; human_med numeric; npc_med numeric; pace numeric; seeded int; events_added int:=0; activated int:=0; finished int:=0; balanced int:=0; m public.world_monsters%rowtype; desired_level int; desired_hp bigint; factor numeric; agents jsonb; orders jsonb; active_players int;
begin
  select id into aid from public.rt_admin_accounts where username='ai_director' and active limit 1; if aid is null then raise exception 'AI Director principal ausente'; end if;
  insert into public.rt86_ai_director_state(world_id,principal_admin_id) values(p_world_id,aid) on conflict(world_id) do update set principal_admin_id=excluded.principal_admin_id,updated_at=now(); select * into ds from public.rt86_ai_director_state where world_id=p_world_id for update; if not ds.enabled then return jsonb_build_object('enabled',false); end if;
  seeded:=public.rt86_seed_npc_agents(p_world_id); select coalesce(percentile_cont(.5) within group(order by points),1000) into human_med from public.villages where world_id=p_world_id and owner_kind='player'; select coalesce(percentile_cont(.5) within group(order by points),1000) into npc_med from public.villages where world_id=p_world_id and owner_kind='ai'; human_med:=greatest(100,human_med); npc_med:=greatest(100,npc_med); pace:=greatest(.65,least(1.35,(human_med/npc_med)*coalesce(ds.target_difficulty,1.0))); select count(*) into active_players from public.player_worlds where world_id=p_world_id and not is_suspended and last_seen_at>now()-interval '24 hours';
  begin events_added:=public.rt74_ensure_event_calendar(p_world_id); exception when others then events_added:=0; end; update public.rt_world_events set status='active',updated_at=now() where world_id=p_world_id and status='scheduled' and starts_at<=now() and ends_at>now(); get diagnostics activated=row_count; update public.rt_world_events set status='finished',updated_at=now() where world_id=p_world_id and status='active' and ends_at<=now(); get diagnostics finished=row_count;
  for m in select * from public.world_monsters wm where wm.world_id=p_world_id and wm.status='active' and not exists(select 1 from public.rt86_monster_balance b where b.monster_id=wm.id) and not exists(select 1 from public.world_monster_hits h where h.monster_id=wm.id) for update skip locked loop factor:=greatest(.85,least(1.25,.90+human_med/10000.0)); desired_level:=greatest(1,least(50,greatest(m.level,round(1+human_med/1500.0)::int))); desired_hp:=greatest(1000,round(m.max_hp*factor)::bigint); insert into public.rt86_monster_balance(monster_id,world_id,base_level,base_hp,balanced_level,balanced_hp,player_median_points) values(m.id,p_world_id,m.level,m.max_hp,desired_level,desired_hp,human_med); update public.world_monsters set level=desired_level,max_hp=desired_hp,hp=desired_hp,updated_at=now() where id=m.id; balanced:=balanced+1; end loop;
  orders:=public.rt86_ai_resolve_orders(p_world_id); update public.rt86_ai_director_state set player_median_points=human_med,npc_median_points=npc_med,pace_multiplier=pace,event_pressure=greatest(1,least(10,4+active_players)),monster_pressure=greatest(1,least(10,round(4+human_med/2500.0)::int)),last_tick=now(),next_tick=now()+interval '1 minute',state=coalesce(state,'{}'::jsonb)||jsonb_build_object('active_players_24h',active_players,'last_seeded',seeded,'events_added',events_added,'events_activated',activated,'events_finished',finished,'monsters_balanced',balanced,'orders',orders),updated_at=now() where world_id=p_world_id; agents:=public.rt86_ai_agents_tick(p_world_id,20);
  insert into public.rt86_ai_decision_log(world_id,agent_id,actor,category,action,target,data) values(p_world_id,null,'AI Director','director','world_tick',jsonb_build_object('world_id',p_world_id),jsonb_build_object('human_median',human_med,'npc_median',npc_med,'pace',pace,'active_players_24h',active_players,'events_added',events_added,'activated',activated,'finished',finished,'monsters_balanced',balanced,'agents',agents,'orders',orders)); insert into public.rt_admin_audit_log(admin_id,action,world_id,payload) values(aid,'ai_director_tick',p_world_id,jsonb_build_object('human_median',human_med,'npc_median',npc_med,'pace',pace,'agents',agents,'orders',orders,'events_added',events_added,'events_activated',activated,'events_finished',finished,'monsters_balanced',balanced));
  return jsonb_build_object('enabled',true,'principal_admin_id',aid,'human_median',human_med,'npc_median',npc_med,'pace',pace,'agents',agents,'orders',orders,'events_added',events_added,'events_activated',activated,'events_finished',finished,'monsters_balanced',balanced,'server_time',now());
end $$;

create or replace function public.rt86_ai_public_status(p_world_id uuid)
returns jsonb language sql security definer set search_path='public','pg_temp' as $$
select jsonb_build_object('version',86,'principal','ai_director','director',(select jsonb_build_object('enabled',d.enabled,'mode',d.mode,'target_difficulty',d.target_difficulty,'pace_multiplier',d.pace_multiplier,'event_pressure',d.event_pressure,'monster_pressure',d.monster_pressure,'player_median_points',d.player_median_points,'npc_median_points',d.npc_median_points,'last_tick',d.last_tick,'next_tick',d.next_tick,'state',d.state) from public.rt86_ai_director_state d where d.world_id=p_world_id),'agents',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.display_name,'personality',a.personality,'traits',a.traits,'goals',a.goals,'metrics',a.metrics,'cycles',a.cycles,'last_action',a.last_action,'last_tick',a.last_tick,'next_tick',a.next_tick,'enabled',a.enabled) order by a.display_name) from public.rt86_npc_ai_agents a where a.world_id=p_world_id),'[]'::jsonb),'active_orders',(select count(*) from public.rt86_ai_orders o where o.world_id=p_world_id and o.status in('outbound','returning')),'recent_decisions',coalesce((select jsonb_agg(x) from (select jsonb_build_object('actor',l.actor,'category',l.category,'action',l.action,'target',l.target,'data',l.data,'created_at',l.created_at) x from public.rt86_ai_decision_log l where l.world_id=p_world_id order by l.created_at desc limit 30) q),'[]'::jsonb))
$$;

grant execute on function public.rt86_ai_public_status(uuid) to anon,authenticated;
revoke all on function public.rt86_ai_director_tick(uuid) from public,anon,authenticated;
revoke all on function public.rt86_ai_agents_tick(uuid,integer) from public,anon,authenticated;
revoke all on function public.rt86_ai_resolve_orders(uuid) from public,anon,authenticated;
revoke all on function public.rt86_ai_schedule_order(uuid,uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.rt86_ai_director_tick(uuid) to service_role;
grant execute on function public.rt86_ai_agents_tick(uuid,integer) to service_role;
grant execute on function public.rt86_ai_resolve_orders(uuid) to service_role;
grant execute on function public.rt86_ai_schedule_order(uuid,uuid,uuid,jsonb,text) to service_role;

create or replace function private.rt79_system_tick()
returns jsonb language plpgsql security definer set search_path to '' as $$
declare r record; w record; processed int:=0; failed int:=0; barbarian_worlds int:=0; ai_director_worlds int:=0; result jsonb; ai_result jsonb;
begin
 for r in select distinct q.world_id,q.user_id from (select s.world_id,s.user_id from public.rt78_strategy_settings s union all select c.world_id,c.user_id from public.rt78_scheduled_commands c where c.status='scheduled' union all select m.world_id,m.user_id from public.rt78_market_routes m where m.enabled union all select j.world_id,j.user_id from public.rt79_scavenge_jobs j where j.status='running' union all select t.world_id,t.user_id from public.rt79_resource_transfers t where t.status='in_transit') q join public.worlds wo on wo.id=q.world_id and wo.is_active join public.player_worlds pw on pw.world_id=q.world_id and pw.user_id=q.user_id and not pw.is_suspended loop
   begin perform set_config('request.jwt.claim.sub',r.user_id::text,true); result:=public.rt79_world_maintenance(r.world_id); processed:=processed+1; exception when others then failed:=failed+1; insert into public.rt78_action_log(world_id,user_id,category,message,data) values(r.world_id,r.user_id,'system','Falha no task runner RT79',jsonb_build_object('error',sqlerrm)); end;
 end loop;
 perform set_config('request.jwt.claim.sub','',true);
 for w in select id from public.worlds where is_active loop
   begin perform public.rt79_admin_barbarian_tick(w.id); barbarian_worlds:=barbarian_worlds+1; exception when others then failed:=failed+1; end;
   begin ai_result:=public.rt86_ai_director_tick(w.id); ai_director_worlds:=ai_director_worlds+1; exception when others then failed:=failed+1; insert into public.rt86_ai_decision_log(world_id,actor,category,action,data) values(w.id,'AI Director','system','tick_failed',jsonb_build_object('error',sqlerrm)); end;
 end loop;
 return jsonb_build_object('version',86,'processed',processed,'barbarian_worlds',barbarian_worlds,'ai_director_worlds',ai_director_worlds,'failed',failed,'ran_at',now());
end $$;

select public.rt86_seed_npc_agents(id) from public.worlds where is_active;
