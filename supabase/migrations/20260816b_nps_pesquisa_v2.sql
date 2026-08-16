-- Migration: ajustes pra pesquisa definitiva da 1ª turma (24 perguntas em 9 seções).
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy). Aplicada via sb.sh em 2026-08-16.
--
-- 1) nps_gravar: o teto de 24 respostas/sessão disparava ANTES do upsert — com a pesquisa
--    definitiva tendo exatamente 24 perguntas, responder tudo e voltar pra corrigir uma
--    resposta estourava o limite. O teto agora só vale pra linha NOVA (update passa) e
--    sobe pra 30 (margem pra pergunta adicionada depois).
-- 2) nps_comentarios: devolve também a sessão (pseudônimo) — o painel liga nome, cargo e
--    comentário da mesma pessoa. Continua atrás da chave; agregados seguem sem texto.
-- 3) nps_stats: a linha meta _comentarios passa a contar só o comentário aberto —
--    identificação (nome/cargo) é texto mas não é comentário, e inflava o card do painel.

begin;

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
    raise exception 'pesquisa indisponível';
  end if;
  if p_pergunta_id !~ '^[a-z0-9_]{1,40}$' or p_tipo not in ('nps', 'escala', 'texto') then
    raise exception 'pergunta inválida';
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
    raise exception 'limite de respostas da sessão';
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

drop function if exists public.nps_comentarios(text, text);
create or replace function public.nps_comentarios(p_evento text, p_chave text)
returns table (sessao uuid, pergunta_id text, texto text, criado timestamptz)
language sql stable security definer set search_path = public as $$
  select r.sessao, r.pergunta_id, r.texto, r.created_at
  from nps_respostas r
  join nps_config c on c.evento = r.evento
  where r.evento = p_evento and r.tipo = 'texto' and c.chave_stats = p_chave
  order by r.created_at desc
  limit 500
$$;

create or replace function public.nps_stats(p_evento text)
returns table (pergunta_id text, tipo text, valor smallint, n bigint)
language sql stable security definer set search_path = public as $$
  select pergunta_id, tipo, valor, count(*)::bigint
  from nps_respostas
  where evento = p_evento and tipo in ('nps', 'escala')
  group by pergunta_id, tipo, valor
  union all
  select '_sessoes', 'meta', null, count(distinct sessao)
  from nps_respostas where evento = p_evento
  union all
  select '_comentarios', 'meta', null, count(*)
  from nps_respostas where evento = p_evento and pergunta_id = 'comentario'
$$;

revoke execute on function public.nps_comentarios(text, text) from public;
grant execute on function public.nps_comentarios(text, text) to anon, service_role;

commit;
