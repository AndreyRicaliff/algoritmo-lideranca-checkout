-- Migration: comentários anônimos no /resultados.
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy). Aplicada via sb.sh em 2026-08-17.
--
-- Problema: nps_textos devolvia sessao + created_at em TODA linha de texto, então o painel
-- casava comentário com ident_nome pela sessão — e, mesmo se o front parasse de exibir o autor,
-- o pareamento continuaria no JSON (F12 desfaz "anonimato" de fachada).
--
-- Desenho: a quebra do vínculo acontece no BANCO, não na página.
--   · linha de comentário -> sessao = null  (não dá pra ligar a ninguém)
--   · linha de identificação -> criado = null  (não dá pra ligar pelo horário)
-- Identificação continua agrupada por sessão entre si (nome + cargo da mesma pessoa) e a lista
-- "quem se identificou" sobrevive — o que morre é a ponte entre as duas.
--
-- Ordenação também vaza: um array em ordem cronológica reconstrói o pareamento. Comentários
-- saem por data (mais novo primeiro); identificação sai em ordem alfabética, fora da linha do tempo.

begin;

create or replace function public.nps_textos(p_evento text, p_token uuid)
returns table (sessao uuid, pergunta_id text, texto text, criado timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not nps_sessao_valida(p_evento, p_token) then
    raise exception 'não autorizado';
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

revoke execute on function public.nps_textos(text, uuid) from public;
grant execute on function public.nps_textos(text, uuid) to anon, service_role;

commit;
