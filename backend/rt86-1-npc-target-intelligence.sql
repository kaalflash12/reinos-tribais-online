-- RT86.1 — histórico reproduzível: inteligência de alvo por personalidade/risco.
-- A definição canônica FINAL de public.rt86_ai_agents_tick(uuid,integer)
-- está incorporada integralmente em backend/rt86-ai-director-and-per-npc-agents.sql.
-- Esta migration-marcador garante que um replay do repositório contém a revisão RT86.1
-- (effective_aggression + risk_limit + no_safe_target + limite de ataques simultâneos em humanos).

do $$
declare d text;
begin
  select pg_get_functiondef('public.rt86_ai_agents_tick(uuid,integer)'::regprocedure) into d;
  if d is null
     or position('effective_aggression' in d)=0
     or position('risk_limit' in d)=0
     or position('no_safe_target' in d)=0
     or position('target_village_id=q.id' in d)=0 then
    raise exception 'RT86.1 ausente: aplique primeiro rt86-ai-director-and-per-npc-agents.sql';
  end if;
end $$;
