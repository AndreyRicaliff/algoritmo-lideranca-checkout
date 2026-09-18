-- Migration: corrige o teto de texto quando 'max' nao e numero.
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy). ARQUIVO 100% ASCII (ver 20260817b).
--
-- BUG (pego em teste de fumaca, antes de ir pro ar):
-- a 20260918d passou a respeitar o 'max' da pergunta como limite de caracteres, fazendo
-- (pergunta ->> 'max')::int para QUALQUER tipo. Acontece que 'max' e polissemico no roteiro:
--   . pergunta de TEXTO   -> max = limite de caracteres  (numero: 120, 1000)
--   . pergunta de NPS     -> max = rotulo do extremo     (string: "Com certeza")
-- Resultado: gravar a resposta de NPS explodia com
--   22P02 invalid input syntax for type integer: "Com certeza"
-- e o serverless devolvia 502. Ou seja: a escala gravava, o comentario gravava, e a UNICA
-- pergunta que nao gravava era justamente a que vira o eNPS -- o numero que o evento existe
-- pra medir. Teria passado despercebido ate alguem abrir o painel sem eNPS nenhum.
--
-- Correcao: o teto so e calculado no ramo de texto, e so quando 'max' for mesmo um numero
-- (jsonb_typeof), em vez de apostar na conversao.

begin;

create or replace function public.nps_gravar(
  p_evento text, p_sessao uuid, p_pergunta_id text, p_tipo text, p_valor int, p_texto text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  cfg nps_config%rowtype;
  pergunta jsonb;
  teto int := 1000;
  ja_existe boolean;
  limite int;
begin
  select * into cfg from nps_config where evento = p_evento;
  if cfg.evento is null or not cfg.aberto or cfg.roteiro is null then
    raise exception 'pesquisa indisponivel' using errcode = 'NPS04';
  end if;

  -- a propria pergunta do roteiro serve de allowlist
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

revoke execute on function public.nps_gravar(text, uuid, text, text, int, text) from public;
grant execute on function public.nps_gravar(text, uuid, text, text, int, text) to anon, service_role;

commit;
