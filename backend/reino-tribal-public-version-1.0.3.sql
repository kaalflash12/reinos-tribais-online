-- Reino Tribal v1.0.3
-- Hotfix: recuperação administrativa pública passa a usar o RPC de bootstrap validado.

update public.rt_public_release_state
set public_version='1.0.3',
    version_scheme='semver',
    notes='Hotfix do login administrativo: endpoint público de recuperação corrigido e link/código de uso único suportado diretamente no site.',
    updated_at=now()
where slug='reino-tribal';
