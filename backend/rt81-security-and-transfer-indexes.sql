-- RT81 — índices de logística + fechamento de manutenção anônima.
create index if not exists rt79_resource_transfers_source_idx on public.rt79_resource_transfers(source_village_id);
create index if not exists rt79_resource_transfers_target_idx on public.rt79_resource_transfers(target_village_id);
create index if not exists rt_ranked_reward_grants_reward_idx on public.rt_ranked_reward_grants(reward_id);

revoke execute on function public.rt74_ensure_event_calendar(uuid) from public, anon;
revoke execute on function public.rt74_finalize_ranked_seasons(uuid) from public, anon;
grant execute on function public.rt74_ensure_event_calendar(uuid) to authenticated;
grant execute on function public.rt74_finalize_ranked_seasons(uuid) to authenticated;
