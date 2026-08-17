-- Migration: erro identificado por SQLSTATE, mensagem sem acento.
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy). Aplicada via sb.sh em 2026-08-17.
--
-- ESTE ARQUIVO E PROPOSITALMENTE 100% ASCII -- inclusive os comentarios. Nao e estilo,
-- e blindagem: o canal usado pra aplicar migration (sb.sh -> Management API) corrompe
-- caractere nao-ASCII no ENVIO. Prova: "select md5('acao-com-cedilha')" no banco devolve
-- hash diferente do md5 real, e pg_get_functiondef das funcoes ja aplicadas contem
-- U+FFFD (replacement char) no lugar dos acentos. A leitura preserva -- so o envio quebra.
--
-- CONSEQUENCIA QUE ISSO CAUSOU EM PRODUCAO: as funcoes gravaram "n<U+FFFD>o autorizado" em
-- vez de "nao autorizado". O serverless comparava a mensagem com o literal correto
-- (indexOf('nao autorizado' com til)), nunca casava, e sessao expirada caia no ramo
-- generico: HTTP 502 "Nao foi possivel carregar as estatisticas" em vez de 401 -> tela
-- de login. O painel ficava num beco sem saida, sem oferecer o login.
--
-- CORRECAO EM DUAS CAMADAS:
--   1. toda excecao ganha um SQLSTATE proprio (NPS01..NPS04) -- controle de fluxo passa a
--      depender de um codigo de 5 chars ASCII, nao de uma frase em portugues;
--   2. as mensagens perdem o acento, entao mesmo o fallback por substring sobrevive
--      ao canal. Frase quebrada vira problema cosmetico, nunca de roteamento.
--
-- Corpos reproduzidos das migrations 20260816b (nps_gravar) e 20260816c (nps_login,
-- nps_stats) e 20260817 (nps_textos, versao anonima) -- logica inalterada.

begin;

-- NPS04: pesquisa fechada. Consumido por api/nps.js -> HTTP 409.
create or replace function public.nps_gravar(
  p_evento text, p_sessao uuid, p_pergunta_id text, p_tipo text, p_valor int, p_texto text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  cfg nps_config%rowtype;
  ja_existe boolean;
begin
  select * into cfg from nps_config where evento = p_evento;
  if cfg.evento is null or not cfg.aberto then
    raise exception 'pesquisa indisponivel' using errcode = 'NPS04';
  end if;
  if p_pergunta_id !~ '^[a-z0-9_]{1,40}$' or p_tipo not in ('nps', 'escala', 'texto') then
    raise exception 'pergunta invalida' using errcode = 'NPS05';
  end if;
  if p_tipo = 'texto' and (p_texto is null or trim(p_texto) = '') then
    return;
  end if;
  select exists (
    select 1 from nps_respostas
    where evento = p_evento and sessao = p_sessao and pergunta_id = p_pergunta_id
  ) into ja_existe;
  if not ja_existe and (
    select count(*) from nps_respostas where evento = p_evento and sessao = p_sessao
  ) >= 30 then
    raise exception 'limite de respostas da sessao' using errcode = 'NPS06';
  end if;
  insert into nps_respostas (evento, sessao, pergunta_id, tipo, valor, texto)
  values (
    p_evento, p_sessao, p_pergunta_id, p_tipo,
    case when p_tipo = 'texto' then null else p_valor end,
    case when p_tipo = 'texto' then left(trim(p_texto), 1000) else null end
  )
  on conflict (evento, sessao, pergunta_id) do update
    set tipo = excluded.tipo, valor = excluded.valor, texto = excluded.texto,
        atualizado_at = now();
end $$;

-- NPS02 (login ausente no banco) e NPS03 (freio de forca bruta). Consumidos por api/login.js.
create or replace function public.nps_login(p_evento text, p_usuario text, p_senha text)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  cfg nps_config%rowtype;
  novo uuid;
begin
  select * into cfg from nps_config where evento = p_evento;
  if cfg.evento is null or cfg.login_user is null or cfg.login_senha is null then
    raise exception 'login nao configurado' using errcode = 'NPS02';
  end if;
  if (select count(*) from nps_login_falha
      where evento = p_evento and em > now() - interval '15 minutes') >= 20 then
    raise exception 'muitas tentativas' using errcode = 'NPS03';
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

-- NPS01: sem sessao valida. Consumido por api/nps-stats.js -> HTTP 401 -> tela de login.
create or replace function public.nps_stats(p_evento text, p_token uuid)
returns table (pergunta_id text, tipo text, valor smallint, n bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not nps_sessao_valida(p_evento, p_token) then
    raise exception 'nao autorizado' using errcode = 'NPS01';
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

-- Mesma versao anonima da 20260817 (comentario sem sessao, identificacao sem data),
-- so trocando a excecao pelo SQLSTATE.
create or replace function public.nps_textos(p_evento text, p_token uuid)
returns table (sessao uuid, pergunta_id text, texto text, criado timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not nps_sessao_valida(p_evento, p_token) then
    raise exception 'nao autorizado' using errcode = 'NPS01';
  end if;
  return query
  select
    case when r.pergunta_id = 'comentario' then null::uuid else r.sessao end,
    r.pergunta_id,
    r.texto,
    case when r.pergunta_id = 'comentario' then r.created_at else null::timestamptz end
  from nps_respostas r
  where r.evento = p_evento and r.tipo = 'texto'
  order by
    (r.pergunta_id = 'comentario') desc,
    case when r.pergunta_id = 'comentario' then r.created_at end desc nulls last,
    case when r.pergunta_id <> 'comentario' then r.texto end asc nulls last
  limit 500;
end $$;

revoke execute on function public.nps_gravar(text, uuid, text, text, int, text) from public;
revoke execute on function public.nps_login(text, text, text) from public;
revoke execute on function public.nps_stats(text, uuid) from public;
revoke execute on function public.nps_textos(text, uuid) from public;
grant execute on function public.nps_gravar(text, uuid, text, text, int, text) to anon, service_role;
grant execute on function public.nps_login(text, text, text) to anon, service_role;
grant execute on function public.nps_stats(text, uuid) to anon, service_role;
grant execute on function public.nps_textos(text, uuid) to anon, service_role;

commit;
