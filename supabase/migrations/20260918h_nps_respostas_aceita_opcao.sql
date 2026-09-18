-- Migration: a TABELA passa a aceitar o tipo 'opcao'.
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy). ARQUIVO 100% ASCII (ver 20260817b).
--
-- A 20260918g ensinou as FUNCOES a falar 'opcao', mas nps_respostas tinha travas proprias
-- que ninguem tinha olhado -- e elas recusaram a linha:
--   nps_respostas_tipo_check   -> tipo in ('nps','escala','texto')
--   nps_respostas_valor_check  -> valor entre 0 e 10   (indice de opcao pode passar de 10)
--   nps_valor_por_tipo         -> so previa nps/escala/texto
-- Sintoma: opcao VALIDA devolvia 502 enquanto opcao invalida era corretamente recusada --
-- as barreiras novas funcionavam e a linha boa morria na ultima porta. Pego testando a
-- pesquisa real em producao, nao em teoria.
--
-- Aproveitando a troca, o constraint fica MAIS restrito do que era, nao menos:
-- antes 'escala' aceitava 0 a 10 (a faixa do NPS) porque o check de valor era global.
-- Agora cada tipo declara a propria faixa, e a tabela sozinha ja recusa escala 0, escala 9
-- ou indice de opcao fora do teto -- mesmo que alguem chame a RPC por outro caminho.
-- Conferido antes de aplicar: nenhuma das 308 linhas existentes viola a regra nova.

begin;

alter table public.nps_respostas drop constraint if exists nps_respostas_tipo_check;
alter table public.nps_respostas drop constraint if exists nps_respostas_valor_check;
alter table public.nps_respostas drop constraint if exists nps_valor_por_tipo;

alter table public.nps_respostas
  add constraint nps_respostas_tipo_check
  check (tipo in ('nps', 'escala', 'texto', 'opcao'));

-- Uma regra so, por tipo: faixa do valor E o pareamento valor/texto no mesmo lugar.
--   nps    0-10   escala 1-5   opcao 0-49 (indice do rotulo)   texto sem valor
alter table public.nps_respostas
  add constraint nps_valor_por_tipo
  check (
    (tipo = 'nps'    and texto is null and valor between 0 and 10) or
    (tipo = 'escala' and texto is null and valor between 1 and 5)  or
    (tipo = 'opcao'  and texto is null and valor between 0 and 49) or
    (tipo = 'texto'  and valor is null and texto is not null)
  );

commit;
