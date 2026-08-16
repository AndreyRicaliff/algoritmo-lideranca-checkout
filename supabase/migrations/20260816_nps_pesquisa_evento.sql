-- Migration: pesquisa NPS do evento (Algoritmo da Liderança — 2ª turma, 18-20/09)
-- ALVO: projeto Supabase AG-Converge (ref hqcbpqkohgmlultnmbyy, org AG CONSULTORIA — Pro).
--   Este repo não tem projeto Supabase próprio; o Converge é a infra de eventos da AG.
--   Aplicada via Management API em 2026-08-16 (sb.sh sql -f). Registrada aqui contra drift.
-- Padrão rls-fail-closed: tabelas SEM nenhuma policy e sem grant pro anon — todo acesso
--   passa pelas RPCs SECURITY DEFINER abaixo, que validam dentro. Anon key pública não
--   lê nem escreve linha nenhuma diretamente.

begin;

create table if not exists public.nps_respostas (
  id uuid primary key default gen_random_uuid(),
  evento text not null,
  sessao uuid not null,
  pergunta_id text not null,
  tipo text not null check (tipo in ('nps', 'escala', 'texto')),
  valor smallint check (valor between 0 and 10),
  texto text check (char_length(texto) <= 1000),
  created_at timestamptz not null default now(),
  atualizado_at timestamptz not null default now(),
  -- escala responde com número e texto responde com texto — nunca os dois
  constraint nps_valor_por_tipo check (
    (tipo in ('nps', 'escala') and valor is not null and texto is null)
    or (tipo = 'texto' and texto is not null and valor is null)
  ),
  constraint nps_uma_resposta unique (evento, sessao, pergunta_id)
);

create index if not exists nps_respostas_evento_idx on public.nps_respostas (evento, pergunta_id);

alter table public.nps_respostas enable row level security;
revoke all on public.nps_respostas from anon, authenticated;

-- Config por evento: liga/desliga a coleta e guarda a chave que libera os comentários
-- na página de resultados. A chave NÃO vai neste arquivo (repo público): é inserida
-- por fora, no mesmo ato da aplicação.
create table if not exists public.nps_config (
  evento text primary key,
  chave_stats text not null,
  aberto boolean not null default true
);
alter table public.nps_config enable row level security;
revoke all on public.nps_config from anon, authenticated;

-- Grava/atualiza uma resposta. Upsert por (evento, sessao, pergunta): voltar e mudar
-- a resposta vale a última — sem policy de UPDATE pro anon.
create or replace function public.nps_gravar(
  p_evento text, p_sessao uuid, p_pergunta_id text, p_tipo text, p_valor int, p_texto text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  cfg nps_config%rowtype;
begin
  select * into cfg from nps_config where evento = p_evento;
  if cfg.evento is null or not cfg.aberto then
    raise exception 'pesquisa indisponível';
  end if;
  if p_pergunta_id !~ '^[a-z0-9_]{1,40}$' or p_tipo not in ('nps', 'escala', 'texto') then
    raise exception 'pergunta inválida';
  end if;
  if p_tipo = 'texto' and (p_texto is null or trim(p_texto) = '') then
    return; -- comentário vazio não é resposta
  end if;
  -- teto por sessão: upsert não cresce em re-resposta, então isso só barra abuso
  if (select count(*) from nps_respostas where evento = p_evento and sessao = p_sessao) >= 24 then
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

-- Agregados por pergunta: histograma valor->n. Nunca devolve linha individual nem texto.
-- Linhas meta: (_sessoes) participantes distintos, (_comentarios) qtde de textos.
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
  from nps_respostas where evento = p_evento and tipo = 'texto'
$$;

-- Comentários (linha a linha) só com a chave do evento. Chave errada = conjunto vazio,
-- sem oráculo de erro.
create or replace function public.nps_comentarios(p_evento text, p_chave text)
returns table (pergunta_id text, texto text, criado timestamptz)
language sql stable security definer set search_path = public as $$
  select r.pergunta_id, r.texto, r.created_at
  from nps_respostas r
  join nps_config c on c.evento = r.evento
  where r.evento = p_evento and r.tipo = 'texto' and c.chave_stats = p_chave
  order by r.created_at desc
  limit 500
$$;

revoke execute on function public.nps_gravar(text, uuid, text, text, int, text) from public;
revoke execute on function public.nps_stats(text) from public;
revoke execute on function public.nps_comentarios(text, text) from public;
grant execute on function public.nps_gravar(text, uuid, text, text, int, text) to anon, service_role;
grant execute on function public.nps_stats(text) to anon, service_role;
grant execute on function public.nps_comentarios(text, text) to anon, service_role;

commit;
