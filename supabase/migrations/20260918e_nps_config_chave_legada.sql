-- Migration: solta o NOT NULL de nps_config.chave_stats.
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy). ARQUIVO 100% ASCII (ver 20260817b).
--
-- chave_stats e a chave que dava acesso aos agregados ANTES do login (20260816c a
-- substituiu; nps_comentarios, que a usava, foi derrubada junto). A coluna ficou para
-- tras com NOT NULL -- inofensiva enquanto existia um evento so, criado a mao.
--
-- Agora que pesquisa nova nasce de um INSERT gerado (scripts/nova-pesquisa.mjs), o
-- NOT NULL de uma coluna morta bloqueia a criacao: descoberto ao testar a criacao de
-- uma pesquisa de verdade, e teria estourado na hora de publicar a pesquisa do dia.
--
-- A coluna NAO e removida aqui de proposito: a funcao legada nps_login/3 ainda esta
-- servindo a versao do site que esta no ar. Ela e as colunas de login por evento caem
-- juntas na limpeza pos-deploy.

begin;

alter table public.nps_config alter column chave_stats drop not null;

comment on column public.nps_config.chave_stats is
  'LEGADO: chave de acesso aos agregados, aposentada pelo login em 20260816c. Nao usar.';

commit;
