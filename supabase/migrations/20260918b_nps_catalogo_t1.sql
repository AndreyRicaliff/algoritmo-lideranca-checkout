-- Migration: carrega o catalogo com o que ja existe e congela a 1a turma.
-- ALVO: Supabase AG-Converge (hqcbpqkohgmlultnmbyy). Irma da 20260918 (estrutura).
--
-- ARQUIVO 100% ASCII. O texto em pt-BR entra pelo JSON abaixo, onde todo acento esta
-- como escape \uXXXX -- ASCII no fio, acento certo no jsonb. Foi assim que o roteiro
-- da 1a turma (gerado a partir do lib/nps.js antigo) atravessou o canal sem corromper.
--
-- O QUE ACONTECE AQUI:
--   1. a 1a turma ganha rotulo, periodo e o roteiro que ela usou de fato;
--   2. a 1a turma e FECHADA -- os dados viram historico so-leitura (o painel continua
--      mostrando tudo; nps_gravar passa a recusar escrita). Export completo fora do
--      Supabase em C:\CODE\dados-eventos\alg-lideranca-2026-t1;
--   3. o rascunho 'alg-lideranca-2026-t2' e REMOVIDO. Ele estava com aberto=true e sem
--      roteiro: uma pesquisa fantasma aberta e exatamente o tipo de conflito que a 2a
--      turma nao pode ter. Zero respostas (conferido antes), entao nada se perde --
--      as pesquisas da 2a turma sao uma por dia, com slug proprio.

begin;

update public.nps_config set
  titulo  = 'Turma 1',
  periodo = '15-17/08/2026',
  dia     = date '2026-08-16',   -- dia em que a coleta aconteceu de fato
  roteiro = '{"escalaRotulos":["Muito ruim","Ruim","Regular","Bom","Excelente"],"secoes":[{"id":"identificacao","titulo":"Identifica\u00e7\u00e3o","sub":"Opcional \u2014 pode pular sem responder.","perguntas":[{"id":"ident_nome","tipo":"texto","max":120,"texto":"Nome"},{"id":"ident_cargo","tipo":"texto","max":120,"texto":"\u00c1rea / cargo"}]},{"id":"nucleo","titulo":"O N\u00facleo \u00b7 O l\u00edder por dentro","sub":"Como voc\u00ea avalia cada pauta?","perguntas":[{"id":"p_dna","tipo":"escala","texto":"O DNA da sua Lideran\u00e7a"},{"id":"p_autocuidado","tipo":"escala","texto":"Autocuidado, Energia e Longevidade"},{"id":"p_decisao","tipo":"escala","texto":"Decis\u00e3o sob Press\u00e3o"},{"id":"p_foco","tipo":"escala","texto":"Foco no que Gera Resultado"}]},{"id":"conexoes","titulo":"As Conex\u00f5es \u00b7 O l\u00edder e o time","sub":"Como voc\u00ea avalia cada pauta?","perguntas":[{"id":"p_presenca","tipo":"escala","texto":"Presen\u00e7a e Influ\u00eancia"},{"id":"p_conversas","tipo":"escala","texto":"Conversas Dif\u00edceis, Rela\u00e7\u00f5es Fortes"},{"id":"p_feedback","tipo":"escala","texto":"Feedback que Desenvolve"},{"id":"p_conflito","tipo":"escala","texto":"Do Conflito ao Acordo"}]},{"id":"escala_org","titulo":"A Escala \u00b7 O l\u00edder e a organiza\u00e7\u00e3o","sub":"Como voc\u00ea avalia cada pauta?","perguntas":[{"id":"p_time","tipo":"escala","texto":"Formando o Time"},{"id":"p_cultura","tipo":"escala","texto":"Cultura e Clima Organizacional"},{"id":"p_visao","tipo":"escala","texto":"Vis\u00e3o Estrat\u00e9gica"},{"id":"p_vendedor","tipo":"escala","texto":"O L\u00edder Vendedor"}]},{"id":"bonus","titulo":"B\u00f4nus \u00b7 O l\u00edder e o futuro","sub":"Como voc\u00ea avalia a pauta?","perguntas":[{"id":"p_ia","tipo":"escala","texto":"IA para a Gest\u00e3o"}]},{"id":"materiais","titulo":"Materiais","sub":null,"perguntas":[{"id":"m_apostila","tipo":"escala","texto":"Qualidade da apostila"},{"id":"m_clareza","tipo":"escala","texto":"Clareza e organiza\u00e7\u00e3o do conte\u00fado"},{"id":"m_utilidade","tipo":"escala","texto":"Utilidade para o dia a dia"}]},{"id":"experiencia","titulo":"Experi\u00eancia geral","sub":null,"perguntas":[{"id":"e_facilitador","tipo":"escala","texto":"Facilitador(es) / condu\u00e7\u00e3o"},{"id":"e_ritmo","tipo":"escala","texto":"Ritmo e dura\u00e7\u00e3o"},{"id":"e_logistica","tipo":"escala","texto":"Organiza\u00e7\u00e3o e log\u00edstica"},{"id":"e_aplicabilidade","tipo":"escala","texto":"Aplicabilidade no seu trabalho"}]},{"id":"nps","titulo":"Recomenda\u00e7\u00e3o","sub":"0\u20136 detrator \u00b7 7\u20138 neutro \u00b7 9\u201310 promotor","perguntas":[{"id":"nps_geral","tipo":"nps","texto":"De 0 a 10, o quanto voc\u00ea recomendaria este treinamento a um colega?","min":"N\u00e3o recomendaria","max":"Com certeza"}]},{"id":"comentario","titulo":"Coment\u00e1rio","sub":"Opcional.","perguntas":[{"id":"comentario","tipo":"texto","max":1000,"texto":"O que mais te marcou e o que podemos melhorar?"}]}]}'::jsonb,
  aberto  = false
where evento = 'alg-lideranca-2026-t1';

delete from public.nps_config
where evento = 'alg-lideranca-2026-t2'
  and not exists (select 1 from public.nps_respostas where evento = 'alg-lideranca-2026-t2');

commit;
