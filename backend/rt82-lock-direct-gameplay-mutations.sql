-- RT82 — comandos e aldeias só podem ser alterados por RPC/Edge autoritativo.
revoke insert, update, delete, truncate, references, trigger on table public.commands from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on table public.villages from anon, authenticated;

grant select on table public.commands to authenticated;
grant select on table public.villages to authenticated;

comment on table public.commands is 'RT82: mutacoes somente por RPC/Edge autoritativo; cliente autenticado possui apenas leitura RLS.';
comment on table public.villages is 'RT82: mutacoes somente por RPC/Edge autoritativo; cliente autenticado possui apenas leitura RLS.';
