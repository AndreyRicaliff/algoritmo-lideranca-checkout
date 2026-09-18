-- Migration: de "um evento" para "catalogo de pesquisas".
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy).
--
-- ESTE ARQUIVO E PROPOSITALMENTE 100% ASCII, inclusive comentarios -- ver 20260817b:
-- o canal de aplicacao (sb.sh -> Management API) corrompe nao-ASCII no ENVIO. Texto com
-- acento entra por outro caminho: JSON com escape \uXXXX, que viaja em ASCII e o jsonb
-- decodifica (ver migration irma 20260918b, que carrega os roteiros).
--
-- POR QUE: a 2a turma precisa de UMA PESQUISA POR DIA (18, 19 e 20/09), cada uma com pautas
-- proprias. O desenho antigo tinha um unico evento fixo no codigo (lib/nps.js: const EVENTO)
-- e o questionario hardcoded -- criar pesquisa exigia deploy, e duas pesquisas simultaneas
-- nao tinham como coexistir.
--
-- O QUE MUDA (3 eixos):
--
--   1. ROTEIRO SAI DO CODIGO E VAI PRO BANCO (nps_config.roteiro jsonb).
--      Criar pesquisa = inserir uma linha. Sem deploy, sem editar JS.
--      Ganho de seguranca de brinde: nps_gravar passa a validar a pergunta CONTRA O ROTEIRO
--      daquela pesquisa. Pesquisa sem roteiro nao aceita nada (fail-closed) -- antes a
--      validacao morava so no serverless, que e substituivel por um curl.
--
--   2. LOGIN DEIXA DE SER POR EVENTO E PASSA A SER DO PAINEL (tabela nps_painel).
--      O modelo real e "um dono, N pesquisas": manter credencial por evento obrigaria a
--      logar de novo a cada dia e multiplicaria hash de senha sem ganho. A credencial do
--      painel e COPIADA do evento t1 (mesmo hash bcrypt), entao a senha que ele ja usa
--      continua valendo e ninguem precisa saber qual e.
--      Efeito colateral desejado: some o risco de queimar o freio de forca-bruta tentando
--      a senha "do evento errado" na vespera.
--
--   3. A PESQUISA VIRA PARAMETRO (?e=slug), validado contra o catalogo do banco.
--      O front nunca escolhe o destino: manda um slug, o banco diz se existe e se esta
--      aberto. String arbitraria de cliente nao cria nem alimenta pesquisa nenhuma.
--
-- COMPATIBILIDADE: as funcoes antigas (nps_login/3, nps_sessao_valida/2) NAO sao derrubadas
-- aqui de proposito -- elas seguem servindo a versao do site que esta no ar ate o deploy do
-- codigo novo. A limpeza fica na 20260918c, aplicada depois do deploy validado.

begin;

-- ---------------------------------------------------------------------------
-- 1. Catalogo
-- ---------------------------------------------------------------------------

alter table public.nps_config
  add column if not exists titulo  text,        -- "2a turma - Dia 1", ja em pt-BR com acento
  add column if not exists periodo text,        -- "18/09/2026" ou "15-17/08/2026", so exibicao
  add column if not exists dia     date,        -- dia que a pesquisa cobre; resolve /pesquisa sem ?e=
  add column if not exists roteiro jsonb,       -- {escalaRotulos:[], secoes:[{id,titulo,sub,perguntas:[]}]}
  add column if not exists criado  timestamptz not null default now();

-- Sem roteiro a pesquisa nao funciona; o catalogo do painel mostra isso como rascunho.
comment on column public.nps_config.roteiro is
  'Estrutura da pesquisa. Null = rascunho: nps_gravar recusa toda resposta.';

-- ---------------------------------------------------------------------------
-- 2. Credencial do painel (uma so, independente de pesquisa)
-- ---------------------------------------------------------------------------

create table if not exists public.nps_painel (
  id          boolean primary key default true check (id),  -- trava: no maximo uma linha
  login_user  text not null,
  login_senha text not null,                                -- hash bcrypt, nunca texto puro
  atualizado  timestamptz not null default now()
);
alter table public.nps_painel enable row level security;
revoke all on public.nps_painel from anon, authenticated;

-- Herda a credencial que o dono ja usa (hash bcrypt copiado -- a senha nao trafega e
-- ninguem alem dele precisa saber qual e).
insert into public.nps_painel (id, login_user, login_senha)
select true, login_user, login_senha
from public.nps_config
where evento = 'alg-lideranca-2026-t1' and login_user is not null and login_senha is not null
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Login e sessao do painel (sem evento)
-- ---------------------------------------------------------------------------

-- Sessao e falha passam a usar o rotulo '_painel' nas colunas evento (que sao not null)
-- em vez de um slug de pesquisa: a sessao nao pertence mais a uma pesquisa.

-- NPS02 login nao configurado - NPS03 freio de forca bruta. Mesmos SQLSTATE da 20260817b,
-- porque api/login.js roteia por eles.
create or replace function public.nps_login(p_usuario text, p_senha text)
returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  cfg nps_painel%rowtype;
  novo uuid;
begin
  select * into cfg from nps_painel where id;
  if cfg.login_user is null then
    raise exception 'login nao configurado' using errcode = 'NPS02';
  end if;
  -- Freio: 20 falhas em 15min travam o painel inteiro. Trade-off herdado e mantido de
  -- proposito -- atacante trava o login por 15min, mas nao martela bcrypt numa senha reusada.
  if (select count(*) from nps_login_falha
      where evento = '_painel' and em > now() - interval '15 minutes') >= 20 then
    raise exception 'muitas tentativas' using errcode = 'NPS03';
  end if;
  if p_usuario = cfg.login_user and cfg.login_senha = crypt(p_senha, cfg.login_senha) then
    delete from nps_login_falha where evento = '_painel' or em < now() - interval '1 hour';
    insert into nps_admin_sessao (evento, expira)
    values ('_painel', now() + interval '30 days')
    returning token into novo;
    return novo;
  end if;
  insert into nps_login_falha (evento) values ('_painel');
  return null;   -- sem oraculo de qual campo errou
end $$;

create or replace function public.nps_sessao_valida(p_token uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from nps_admin_sessao where token = p_token and expira > now()
  )
$$;

-- ---------------------------------------------------------------------------
-- 4. Catalogo para o painel
-- ---------------------------------------------------------------------------

-- Uma linha por pesquisa, com o contador que o painel usa pra mostrar o que esta vivo.
-- NPS01 = sem sessao valida, consumido por api/nps-eventos.js -> HTTP 401 -> tela de login.
create or replace function public.nps_catalogo(p_token uuid)
returns table (
  evento text, titulo text, periodo text, dia date, aberto boolean,
  rascunho boolean, sessoes bigint, respostas bigint, ultima timestamptz
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not nps_sessao_valida(p_token) then
    raise exception 'nao autorizado' using errcode = 'NPS01';
  end if;
  return query
  select c.evento, c.titulo, c.periodo, c.dia, c.aberto,
         (c.roteiro is null) as rascunho,
         count(distinct r.sessao)::bigint,
         count(r.id)::bigint,
         max(r.created_at)
  from nps_config c
  left join nps_respostas r on r.evento = c.evento
  group by c.evento, c.titulo, c.periodo, c.dia, c.aberto, c.roteiro, c.criado
  order by c.dia desc nulls last, c.criado desc;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Roteiro para o wizard (publico -- e a propria pesquisa)
-- ---------------------------------------------------------------------------

-- Sem p_evento (ou com slug inexistente) resolve a pesquisa do DIA de hoje em Brasilia;
-- sem pesquisa do dia, cai na aberta mais recente. Assim o QR generico funciona os 3 dias
-- e o QR com ?e=slug e imune a relogio.
-- Devolve tambem fechada/rascunho: quem le o QR de ontem merece "encerrada", nao erro seco.
create or replace function public.nps_roteiro(p_evento text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  cfg nps_config%rowtype;
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if p_evento is not null and p_evento <> '' then
    select * into cfg from nps_config where evento = p_evento;
  end if;
  if cfg.evento is null then
    select * into cfg from nps_config
    where aberto and roteiro is not null and dia = hoje
    order by criado desc limit 1;
  end if;
  if cfg.evento is null then
    select * into cfg from nps_config
    where aberto and roteiro is not null
    order by dia desc nulls last, criado desc limit 1;
  end if;
  if cfg.evento is null then
    return null;
  end if;
  return jsonb_build_object(
    'evento',  cfg.evento,
    'titulo',  cfg.titulo,
    'periodo', cfg.periodo,
    'aberto',  cfg.aberto and cfg.roteiro is not null,
    'roteiro', cfg.roteiro
  );
end $$;

-- ---------------------------------------------------------------------------
-- 6. Gravacao validada contra o roteiro da propria pesquisa
-- ---------------------------------------------------------------------------

-- NPS04 pesquisa indisponivel - NPS05 pergunta invalida - NPS06 limite por sessao.
-- Mudanca em relacao a 20260817b: a pergunta passa a ser conferida no ROTEIRO da pesquisa,
-- nao so contra um regex. Pergunta que nao existe naquele roteiro nao entra, mesmo que o
-- chamador invente o id -- e pesquisa sem roteiro nao aceita nada.
create or replace function public.nps_gravar(
  p_evento text, p_sessao uuid, p_pergunta_id text, p_tipo text, p_valor int, p_texto text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  cfg nps_config%rowtype;
  vale boolean;
  ja_existe boolean;
  limite int;
begin
  select * into cfg from nps_config where evento = p_evento;
  if cfg.evento is null or not cfg.aberto or cfg.roteiro is null then
    raise exception 'pesquisa indisponivel' using errcode = 'NPS04';
  end if;

  select exists (
    select 1
    from jsonb_array_elements(cfg.roteiro -> 'secoes') s,
         jsonb_array_elements(s -> 'perguntas') q
    where q ->> 'id' = p_pergunta_id and q ->> 'tipo' = p_tipo
  ) into vale;
  if not vale then
    raise exception 'pergunta invalida' using errcode = 'NPS05';
  end if;

  if p_tipo = 'texto' and (p_texto is null or trim(p_texto) = '') then
    return;   -- texto vazio nao e resposta
  end if;

  -- Teto por sessao: o proprio tamanho do roteiro, com folga. Antes era 30 fixo, que nao
  -- serve quando cada dia tem um numero diferente de perguntas.
  select count(*) + 5 into limite
  from jsonb_array_elements(cfg.roteiro -> 'secoes') s,
       jsonb_array_elements(s -> 'perguntas') q;

  select exists (
    select 1 from nps_respostas
    where evento = p_evento and sessao = p_sessao and pergunta_id = p_pergunta_id
  ) into ja_existe;
  if not ja_existe and (
    select count(*) from nps_respostas where evento = p_evento and sessao = p_sessao
  ) >= limite then
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

-- ---------------------------------------------------------------------------
-- 7. Stats e textos: sessao do painel, pesquisa por parametro
-- ---------------------------------------------------------------------------

-- Corpo identico ao da 20260817b; muda so a validacao (sessao do painel, nao do evento).
create or replace function public.nps_stats(p_evento text, p_token uuid)
returns table (pergunta_id text, tipo text, valor smallint, n bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not nps_sessao_valida(p_token) then
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

-- ANONIMATO (herdado da 20260817, mantido palavra por palavra): a quebra do vinculo
-- acontece AQUI, no banco, nao na pagina.
--   . linha de comentario  -> sessao = null  (nao da pra ligar a ninguem)
--   . linha de identificacao -> criado = null (nao da pra ligar pelo horario)
-- A ordenacao tambem vaza: comentario sai por data, identificacao em ordem alfabetica,
-- fora da linha do tempo. Vale para toda pesquisa nova sem precisar reconfigurar nada.
create or replace function public.nps_textos(p_evento text, p_token uuid)
returns table (sessao uuid, pergunta_id text, texto text, criado timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not nps_sessao_valida(p_token) then
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

-- ---------------------------------------------------------------------------
-- 8. Grants
-- ---------------------------------------------------------------------------

revoke execute on function public.nps_login(text, text) from public;
revoke execute on function public.nps_sessao_valida(uuid) from public;
revoke execute on function public.nps_catalogo(uuid) from public;
revoke execute on function public.nps_roteiro(text) from public;
revoke execute on function public.nps_gravar(text, uuid, text, text, int, text) from public;
revoke execute on function public.nps_stats(text, uuid) from public;
revoke execute on function public.nps_textos(text, uuid) from public;

grant execute on function public.nps_login(text, text) to anon, service_role;
grant execute on function public.nps_catalogo(uuid) to anon, service_role;
grant execute on function public.nps_roteiro(text) to anon, service_role;
grant execute on function public.nps_gravar(text, uuid, text, text, int, text) to anon, service_role;
grant execute on function public.nps_stats(text, uuid) to anon, service_role;
grant execute on function public.nps_textos(text, uuid) to anon, service_role;
-- nps_sessao_valida NAO recebe grant: e uso interno das outras funcoes (security definer
-- roda como dono). Deixar exposta so entregaria um oraculo de "este token vale?".

commit;
