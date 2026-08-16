-- Migration: login obrigatório no /resultados (substitui a chave de comentários).
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy). Aplicada via sb.sh em 2026-08-16.
--
-- Desenho: credencial em nps_config (senha com bcrypt via pgcrypto — NUNCA em texto puro,
-- porque este repo é público e o banco é compartilhado), sessão por token uuid de 30 dias
-- validada no próprio banco. Nada de env var: o serverless só transporta o cookie.
-- A senha NÃO está nesta migration: o dono roda o UPDATE por fora (SQL Editor).
--
-- nps_stats ganha overload com token (a versão antiga sem token coexiste durante o deploy
-- e é derrubada no fim); nps_comentarios (chave) morre junto — comentário passa pelo login.

begin;

alter table public.nps_config
  add column if not exists login_user text,
  add column if not exists login_senha text; -- hash bcrypt (crypt/gen_salt), nunca texto puro

create table if not exists public.nps_admin_sessao (
  token uuid primary key default gen_random_uuid(),
  evento text not null,
  criado timestamptz not null default now(),
  expira timestamptz not null
);
alter table public.nps_admin_sessao enable row level security;
revoke all on public.nps_admin_sessao from anon, authenticated;

create table if not exists public.nps_login_falha (
  evento text not null,
  em timestamptz not null default now()
);
alter table public.nps_login_falha enable row level security;
revoke all on public.nps_login_falha from anon, authenticated;
create index if not exists nps_login_falha_idx on public.nps_login_falha (evento, em);

-- Login: usuário+senha certos -> token de sessão (30 dias). Errado -> null, sem oráculo
-- de qual campo falhou. Freio: 20 falhas em 15min bloqueia o evento temporariamente
-- (trade-off aceito: atacante pode travar o login por 15min, mas não fica martelando
-- bcrypt à vontade numa senha que o dono reusa em outros sistemas).
create or replace function public.nps_login(p_evento text, p_usuario text, p_senha text)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  cfg nps_config%rowtype;
  novo uuid;
begin
  select * into cfg from nps_config where evento = p_evento;
  if cfg.evento is null or cfg.login_user is null or cfg.login_senha is null then
    raise exception 'login não configurado';
  end if;
  if (select count(*) from nps_login_falha
      where evento = p_evento and em > now() - interval '15 minutes') >= 20 then
    raise exception 'muitas tentativas';
  end if;
  if p_usuario = cfg.login_user and cfg.login_senha = crypt(p_senha, cfg.login_senha) then
    delete from nps_login_falha where evento = p_evento or em < now() - interval '1 hour';
    insert into nps_admin_sessao (evento, expira)
    values (p_evento, now() + interval '30 days')
    returning token into novo;
    return novo;
  end if;
  insert into nps_login_falha (evento) values (p_evento);
  return null;
end $$;

create or replace function public.nps_sessao_valida(p_evento text, p_token uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from nps_admin_sessao
    where token = p_token and evento = p_evento and expira > now()
  )
$$;

-- Agregados agora exigem sessão: "login obrigatório" de verdade, não só na página —
-- sem token válido nem o histograma sai.
create or replace function public.nps_stats(p_evento text, p_token uuid)
returns table (pergunta_id text, tipo text, valor smallint, n bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not nps_sessao_valida(p_evento, p_token) then
    raise exception 'não autorizado';
  end if;
  return query
  select r.pergunta_id, r.tipo, r.valor, count(*)::bigint
  from nps_respostas r
  where r.evento = p_evento and r.tipo in ('nps', 'escala')
  group by r.pergunta_id, r.tipo, r.valor
  union all
  select '_sessoes', 'meta', null::smallint, count(distinct r.sessao)
  from nps_respostas r where r.evento = p_evento
  union all
  select '_comentarios', 'meta', null::smallint, count(*)
  from nps_respostas r where r.evento = p_evento and r.pergunta_id = 'comentario';
end $$;

-- Textos (identificação + comentários) pela sessão — substitui a chave.
create or replace function public.nps_textos(p_evento text, p_token uuid)
returns table (sessao uuid, pergunta_id text, texto text, criado timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not nps_sessao_valida(p_evento, p_token) then
    raise exception 'não autorizado';
  end if;
  return query
  select r.sessao, r.pergunta_id, r.texto, r.created_at
  from nps_respostas r
  where r.evento = p_evento and r.tipo = 'texto'
  order by r.created_at desc
  limit 500;
end $$;

revoke execute on function public.nps_login(text, text, text) from public;
revoke execute on function public.nps_sessao_valida(text, uuid) from public;
revoke execute on function public.nps_stats(text, uuid) from public;
revoke execute on function public.nps_textos(text, uuid) from public;
grant execute on function public.nps_login(text, text, text) to anon, service_role;
grant execute on function public.nps_stats(text, uuid) to anon, service_role;
grant execute on function public.nps_textos(text, uuid) to anon, service_role;

commit;
