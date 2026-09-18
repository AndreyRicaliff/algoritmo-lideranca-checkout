-- Migration: tipo de pergunta 'opcao' (escolha unica entre rotulos).
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy). ARQUIVO 100% ASCII (ver 20260817b).
--
-- POR QUE: o roteiro do dia 18 (modulo O Nucleo) tem 4 perguntas que nao sao escala nem
-- texto -- sao escolha entre rotulos nomeados:
--   "Como percebeu a sequencia das pautas?" -> complementares / repetiram / faltou conexao / nao sei
--   "Como chegou ao final do modulo?"       -> com energia / cansado / no limite / exausto
--   "Qual pauta mais valeu o tempo?"        -> uma das 4 pautas
--   "Qual pauta encurtaria?"                -> uma das 4 pautas, ou nenhuma
-- Nao da pra representar isso como escala: 1-5 implica ORDEM e permite media. "Exausto" nao
-- e 1 e "com energia" nao e 5 -- e media de categoria nao significa nada. Como texto livre,
-- viraria caixa aberta que ninguem agrega.
--
-- COMO E GUARDADO: valor = INDICE da opcao no array (0-based), reaproveitando a coluna
-- smallint que ja existe. Consequencia que precisa estar escrita em algum lugar:
--   *** NAO REORDENAR NEM REMOVER OPCOES DE UMA PERGUNTA QUE JA COLETOU RESPOSTA ***
-- o indice gravado passaria a apontar pro rotulo errado e o historico mentiria em silencio.
-- Acrescentar opcao no FIM e seguro.
--
-- A faixa valida nao e fixa: depende de quantas opcoes a pergunta tem NAQUELE roteiro.
-- Quem sabe isso e o banco, que ja tem o roteiro na mao -- entao e aqui que a validacao mora.

begin;

-- NPS08: opcao fora do conjunto declarado na pergunta.
create or replace function public.nps_gravar(
  p_evento text, p_sessao uuid, p_pergunta_id text, p_tipo text, p_valor int, p_texto text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  cfg nps_config%rowtype;
  pergunta jsonb;
  teto int := 1000;
  n_opcoes int;
  ja_existe boolean;
  limite int;
begin
  select * into cfg from nps_config where evento = p_evento;
  if cfg.evento is null or not cfg.aberto or cfg.roteiro is null then
    raise exception 'pesquisa indisponivel' using errcode = 'NPS04';
  end if;

  select q into pergunta
  from jsonb_array_elements(cfg.roteiro -> 'secoes') s,
       jsonb_array_elements(s -> 'perguntas') q
  where q ->> 'id' = p_pergunta_id and q ->> 'tipo' = p_tipo
  limit 1;
  if pergunta is null then
    raise exception 'pergunta invalida' using errcode = 'NPS05';
  end if;

  if p_tipo = 'texto' then
    if p_texto is null or trim(p_texto) = '' then
      return;   -- texto vazio nao e resposta
    end if;
    -- 'max' so vale como limite de caracteres em pergunta de texto, e so se for numero:
    -- em nps/escala esse mesmo campo carrega o rotulo do extremo ("Com certeza").
    if jsonb_typeof(pergunta -> 'max') = 'number' then
      teto := least(greatest((pergunta ->> 'max')::int, 1), 1000);
    end if;

  elsif p_tipo = 'opcao' then
    if jsonb_typeof(pergunta -> 'opcoes') <> 'array' then
      raise exception 'pergunta sem opcoes' using errcode = 'NPS05';
    end if;
    n_opcoes := jsonb_array_length(pergunta -> 'opcoes');
    if p_valor is null or p_valor < 0 or p_valor >= n_opcoes then
      raise exception 'opcao inexistente' using errcode = 'NPS08';
    end if;

  else
    -- Faixa por tipo: escala do evento e 1-5, recomendacao (eNPS) e 0-10.
    if p_valor is null
       or (p_tipo = 'escala' and (p_valor < 1 or p_valor > 5))
       or (p_tipo = 'nps' and (p_valor < 0 or p_valor > 10)) then
      raise exception 'valor fora da faixa' using errcode = 'NPS07';
    end if;
  end if;

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
    case when p_tipo = 'texto' then left(trim(p_texto), teto) else null end
  )
  on conflict (evento, sessao, pergunta_id) do update
    set tipo = excluded.tipo, valor = excluded.valor, texto = excluded.texto,
        atualizado_at = now();
end $$;

-- 'opcao' entra na agregacao junto com escala e nps (o painel conta por indice).
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
  where r.evento = p_evento and r.tipo in ('nps', 'escala', 'opcao')
  group by r.pergunta_id, r.tipo, r.valor
  union all
  select '_sessoes', 'meta', null::smallint, count(distinct r.sessao)
  from nps_respostas r where r.evento = p_evento
  union all
  select '_comentarios', 'meta', null::smallint, count(*)
  from nps_respostas r where r.evento = p_evento and r.pergunta_id = 'comentario';
end $$;

revoke execute on function public.nps_gravar(text, uuid, text, text, int, text) from public;
revoke execute on function public.nps_stats(text, uuid) from public;
grant execute on function public.nps_gravar(text, uuid, text, text, int, text) to anon, service_role;
grant execute on function public.nps_stats(text, uuid) to anon, service_role;

commit;
