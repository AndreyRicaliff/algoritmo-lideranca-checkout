-- Migration: dois fechamentos que faltaram na 20260918.
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy). ARQUIVO 100% ASCII (ver 20260817b).
--
-- 1. nps_roteiro com slug INEXISTENTE caia no fallback "pesquisa do dia".
--    Era bug de verdade: um QR com slug errado (ou de uma pesquisa apagada) nao daria erro --
--    silenciosamente abriria OUTRA pesquisa e coletaria resposta no lugar errado. O fallback
--    por data existe pra quem chega SEM parametro; pedir uma pesquisa especifica que nao
--    existe tem que devolver nada.
--
-- 2. nps_gravar nao conferia a FAIXA do valor (escala 1-5, nps 0-10).
--    O serverless conferia, mas ele nao e o unico caminho: a anon key e publica e a RPC tem
--    grant pro anon, entao um POST direto no /rest/v1/rpc/nps_gravar gravaria nota 99 numa
--    escala de 1 a 5 e envenenaria a media. Validacao de dominio pertence ao mesmo lugar que
--    a autorizacao.

begin;

create or replace function public.nps_roteiro(p_evento text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  cfg nps_config%rowtype;
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if p_evento is not null and p_evento <> '' then
    -- pediu uma pesquisa especifica: e ela ou nada. Sem fallback, pra um slug errado
    -- nunca virar resposta gravada em outra pesquisa.
    select * into cfg from nps_config where evento = p_evento;
    if cfg.evento is null then
      return null;
    end if;
  else
    select * into cfg from nps_config
    where aberto and roteiro is not null and dia = hoje
    order by criado desc limit 1;
    if cfg.evento is null then
      select * into cfg from nps_config
      where aberto and roteiro is not null
      order by dia desc nulls last, criado desc limit 1;
    end if;
    if cfg.evento is null then
      return null;
    end if;
  end if;

  return jsonb_build_object(
    'evento',  cfg.evento,
    'titulo',  cfg.titulo,
    'periodo', cfg.periodo,
    'aberto',  cfg.aberto and cfg.roteiro is not null,
    'roteiro', cfg.roteiro
  );
end $$;

-- NPS07: valor fora da faixa do tipo.
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

  -- Faixa por tipo: escala do evento e 1-5, recomendacao (eNPS) e 0-10.
  if p_tipo <> 'texto' then
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
    case when p_tipo = 'texto' then left(trim(p_texto), 1000) else null end
  )
  on conflict (evento, sessao, pergunta_id) do update
    set tipo = excluded.tipo, valor = excluded.valor, texto = excluded.texto,
        atualizado_at = now();
end $$;

revoke execute on function public.nps_roteiro(text) from public;
revoke execute on function public.nps_gravar(text, uuid, text, text, int, text) from public;
grant execute on function public.nps_roteiro(text) to anon, service_role;
grant execute on function public.nps_gravar(text, uuid, text, text, int, text) to anon, service_role;

commit;
