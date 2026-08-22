-- RT86.3 — o seed periódico não pode apagar métricas adaptativas calculadas pelo agente.
create or replace function public.rt86_seed_npc_agents(p_world_id uuid)
returns integer
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare n integer:=0;
begin
  insert into public.rt86_npc_ai_agents(world_id,npc_key,display_name,personality,traits,memory,goals,metrics,next_tick)
  select p_world_id,
         'npc_'||substr(md5(v.owner_name),1,12),
         v.owner_name,
         (array['raider','warden','merchant','scholar','opportunist','conqueror','diplomat','builder'])[1+mod(abs(hashtext(v.owner_name)::bigint),8)],
         jsonb_build_object('aggression',20+mod(abs(hashtext(v.owner_name||':agg')::bigint),81),'risk',15+mod(abs(hashtext(v.owner_name||':risk')::bigint),76),'economy',25+mod(abs(hashtext(v.owner_name||':eco')::bigint),76),'defense',20+mod(abs(hashtext(v.owner_name||':def')::bigint),81),'research',20+mod(abs(hashtext(v.owner_name||':res')::bigint),81),'diplomacy',10+mod(abs(hashtext(v.owner_name||':dip')::bigint),91),'expansion',15+mod(abs(hashtext(v.owner_name||':exp')::bigint),86)),
         jsonb_build_object('known_targets','{}'::jsonb,'recent_losses',0,'recent_wins',0,'last_enemy',null),
         jsonb_build_object('economy','grow','army','balanced','research','adaptive','territory','hold'),
         jsonb_build_object('villages',count(*),'points',sum(v.points)),
         now()+make_interval(secs=>mod(abs(hashtext(v.owner_name||':tick')::bigint),300)::int)
  from public.villages v
  where v.world_id=p_world_id and v.owner_kind='ai'
  group by v.owner_name
  on conflict(world_id,npc_key) do update
    set display_name=excluded.display_name,
        metrics=coalesce(public.rt86_npc_ai_agents.metrics,'{}'::jsonb)||excluded.metrics,
        updated_at=now();
  get diagnostics n=row_count;
  return n;
end $$;
