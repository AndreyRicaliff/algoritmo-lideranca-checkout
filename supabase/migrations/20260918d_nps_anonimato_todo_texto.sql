-- Migration: o anonimato para de depender do id da pergunta se chamar 'comentario'.
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy). ARQUIVO 100% ASCII (ver 20260817b).
--
-- O PROBLEMA (achado em revisao, antes de ir pro ar):
-- a versao anterior de nps_textos so apagava a sessao quando pergunta_id = 'comentario'.
-- Isso bastava quando o questionario era fixo no codigo e so existia UMA pergunta aberta.
-- Agora cada dia da turma tem roteiro proprio: se o roteiro do dia 1 trouxer outra pergunta
-- de texto livre (ex.: 'o_que_mudaria'), a linha dela sairia com a sessao PRESERVADA -- e a
-- identificacao da mesma sessao esta na mesma resposta. Bastava o F12 pra ligar a opiniao
-- critica ao nome de quem escreveu, sem nada na tela indicando isso.
--
-- A REGRA NOVA, por natureza da pergunta e nao por id combinado:
--   . pergunta de IDENTIFICACAO (id comeca com 'ident_') -> mantem a sessao (e o que agrupa
--     nome e cargo da mesma pessoa), mas perde a data;
--   . QUALQUER OUTRO texto livre -> perde a sessao e mantem so a data.
-- Ou seja: o default passou a ser anonimo. Roteiro novo nasce seguro sem ninguem lembrar
-- de uma convencao de nomes.
--
-- A ordenacao segue sendo parte da defesa: texto anonimo sai por data (mais novo primeiro),
-- identificacao sai alfabetica, fora da linha do tempo -- um array cronologico unico
-- reconstruiria o pareamento que as colunas nulas acabaram de desfazer.
--
-- De brinde, nps_gravar passa a respeitar o 'max' declarado na propria pergunta em vez de
-- cortar todo texto em 1000: campo de Nome com max 120 nao aceita mais 1000 caracteres
-- quando o POST vem de fora do formulario.

begin;

create or replace function public.nps_textos(p_evento text, p_token uuid)
returns table (sessao uuid, pergunta_id text, texto text, criado timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not nps_sessao_valida(p_token) then
    raise exception 'nao autorizado' using errcode = 'NPS01';
  end if;
  return query
  select
    case when r.pergunta_id like 'ident\_%' then r.sessao else null::uuid end,
    r.pergunta_id,
    r.texto,
    case when r.pergunta_id like 'ident\_%' then null::timestamptz else r.created_at end
  from nps_respostas r
  where r.evento = p_evento and r.tipo = 'texto'
  order by
    (r.pergunta_id not like 'ident\_%') desc,
    case when r.pergunta_id not like 'ident\_%' then r.created_at end desc nulls last,
    case when r.pergunta_id like 'ident\_%' then r.texto end asc nulls last
  limit 500;
end $$;

create or replace function public.nps_gravar(
  p_evento text, p_sessao uuid, p_pergunta_id text, p_tipo text, p_valor int, p_texto text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  cfg nps_config%rowtype;
  pergunta jsonb;
  teto int;
  ja_existe boolean;
  limite int;
begin
  select * into cfg from nps_config where evento = p_evento;
  if cfg.evento is null or not cfg.aberto or cfg.roteiro is null then
    raise exception 'pesquisa indisponivel' using errcode = 'NPS04';
  end if;

  -- a propria pergunta do roteiro: serve de allowlist E de fonte do limite de tamanho
  select q into pergunta
  from jsonb_array_elements(cfg.roteiro -> 'secoes') s,
       jsonb_array_elements(s -> 'perguntas') q
  where q ->> 'id' = p_pergunta_id and q ->> 'tipo' = p_tipo
  limit 1;
  if pergunta is null then
    raise exception 'pergunta invalida' using errcode = 'NPS05';
  end if;

  if p_tipo = 'texto' and (p_texto is null or trim(p_texto) = '') then
    return;   -- texto vazio nao e resposta
  end if;

  -- Faixa por tipo: escala do evento e 1-5, recomendacao (eNPS) e 0-10.
  if p_tipo <> 'texto' then
    if p_valor is null
       or (p_tipo = 'escala' and (p_valor < 1 or p_valor > 5))
       or (p_tipo = 'nps' and (p_valor < 0 or p_valor > 10)) then
      raise exception 'valor fora da faixa' using errcode = 'NPS07';
    end if;
  end if;

  teto := least(coalesce((pergunta ->> 'max')::int, 1000), 1000);

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

revoke execute on function public.nps_textos(text, uuid) from public;
revoke execute on function public.nps_gravar(text, uuid, text, text, int, text) from public;
grant execute on function public.nps_textos(text, uuid) to anon, service_role;
grant execute on function public.nps_gravar(text, uuid, text, text, int, text) to anon, service_role;

commit;
