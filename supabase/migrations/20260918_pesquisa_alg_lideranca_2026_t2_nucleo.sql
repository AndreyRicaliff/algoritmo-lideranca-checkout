-- Pesquisa: alg-lideranca-2026-t2-nucleo
-- Gerada por scripts/nova-pesquisa.mjs a partir de alg-lideranca-2026-t2-nucleo.json.
-- ARQUIVO 100% ASCII: acento viaja como escape \uXXXX e o jsonb decodifica (ver 20260817b).
--
-- 19 perguntas em 9 secoes.
-- Reaplicar este arquivo ATUALIZA a pesquisa (upsert) -- as respostas ja gravadas nao
-- sao tocadas. Mudar o texto de uma pergunta sem mudar o id reescreve o rotulo tambem
-- no historico do painel, que passa a exibir o texto novo para respostas antigas.

begin;

insert into public.nps_config (evento, titulo, periodo, dia, aberto, roteiro)
values (
  'alg-lideranca-2026-t2-nucleo',
  ('"Avalia\u00e7\u00e3o \u00b7 M\u00f3dulo O N\u00facleo"'::jsonb ->> 0),
  ('"18/09/2026"'::jsonb ->> 0),
  date '2026-09-18',
  true,
  '{"subtitulo":"O l\u00edder por dentro \u00b7 Menos de 2 minutos. Resposta an\u00f4nima (identifica\u00e7\u00e3o opcional). O que voc\u00ea responder aqui a gente ajusta ainda hoje, para amanh\u00e3.","escalaRotulos":["Muito ruim","Ruim","Regular","Bom","Excelente"],"secoes":[{"id":"identificacao","titulo":"Identifica\u00e7\u00e3o","sub":"Opcional \u2014 pode pular sem responder.","perguntas":[{"id":"ident_nome","tipo":"texto","max":120,"texto":"Nome"},{"id":"ident_cargo","tipo":"texto","max":120,"texto":"\u00c1rea / cargo"}]},{"id":"pautas","titulo":"O N\u00facleo \u00b7 As pautas","sub":"Como voc\u00ea avalia cada pauta deste m\u00f3dulo?","perguntas":[{"id":"p_dna","tipo":"escala","texto":"O DNA da sua Lideran\u00e7a"},{"id":"p_autocuidado","tipo":"escala","texto":"Autocuidado, Energia e Longevidade"},{"id":"p_decisao","tipo":"escala","texto":"Decis\u00e3o sob Press\u00e3o"},{"id":"p_foco","tipo":"escala","texto":"Foco no que Gera Resultado"}]},{"id":"conducao","titulo":"Condu\u00e7\u00e3o, ritmo e aplica\u00e7\u00e3o","sub":"Como voc\u00ea avalia cada item?","perguntas":[{"id":"e_facilitador","tipo":"escala","texto":"Condu\u00e7\u00e3o dos facilitadores"},{"id":"e_ritmo","tipo":"escala","texto":"Ritmo e dura\u00e7\u00e3o do m\u00f3dulo"},{"id":"e_aplicabilidade","tipo":"escala","texto":"Aplicabilidade no seu dia a dia"}]},{"id":"percepcao","titulo":"Sequ\u00eancia e energia","sub":"Escolha uma op\u00e7\u00e3o em cada.","perguntas":[{"id":"seq_pautas","tipo":"opcao","texto":"Como voc\u00ea percebeu a sequ\u00eancia das pautas deste m\u00f3dulo?","opcoes":["Complementares, uma preparou a outra","Houve repeti\u00e7\u00e3o de conte\u00fado entre elas","Faltou conex\u00e3o entre as pautas","N\u00e3o soube avaliar"]},{"id":"energia_final","tipo":"opcao","texto":"Como voc\u00ea chegou ao final deste m\u00f3dulo?","opcoes":["Com energia, daria para seguir","Cansado, mas acompanhando bem","No limite, perdi o fio em alguns momentos","Exausto, rendi pouco na parte final"]}]},{"id":"destaques","titulo":"Destaques do m\u00f3dulo","sub":"Escolha uma pauta em cada.","perguntas":[{"id":"pauta_top","tipo":"opcao","texto":"Qual pauta deste m\u00f3dulo mais valeu o seu tempo?","opcoes":["O DNA da sua Lideran\u00e7a","Autocuidado, Energia e Longevidade","Decis\u00e3o sob Press\u00e3o","Foco no que Gera Resultado"]},{"id":"pauta_encurtar","tipo":"opcao","texto":"Qual pauta voc\u00ea encurtaria?","opcoes":["O DNA da sua Lideran\u00e7a","Autocuidado, Energia e Longevidade","Decis\u00e3o sob Press\u00e3o","Foco no que Gera Resultado","Nenhuma"]}]},{"id":"nps","titulo":"Nota do m\u00f3dulo","sub":"0\u20136 detrator \u00b7 7\u20138 neutro \u00b7 9\u201310 promotor","perguntas":[{"id":"nps_geral","tipo":"nps","texto":"De 0 a 10, que nota voc\u00ea d\u00e1 para este m\u00f3dulo?","min":"N\u00e3o recomendaria","max":"Com certeza"}]},{"id":"comentario","titulo":"Coment\u00e1rio","sub":"Opcional.","perguntas":[{"id":"comentario","tipo":"texto","max":1000,"texto":"O que mais te marcou e o que podemos melhorar neste m\u00f3dulo?"}]},{"id":"alimentacao","titulo":"Alimenta\u00e7\u00e3o","sub":null,"perguntas":[{"id":"al_coffee","tipo":"escala","texto":"Qualidade do coffee break de sexta"},{"id":"al_tempo","tipo":"escala","texto":"Tempo dispon\u00edvel para o intervalo"}]},{"id":"estrutura","titulo":"Estrutura e acolhimento","sub":"Ainda d\u00e1 tempo de ajustar para amanh\u00e3.","perguntas":[{"id":"es_sala","tipo":"escala","texto":"Sala, som, proje\u00e7\u00e3o e climatiza\u00e7\u00e3o"},{"id":"es_recepcao","tipo":"escala","texto":"Recep\u00e7\u00e3o e atendimento da equipe"}]}]}'::jsonb
)
on conflict (evento) do update set
  titulo  = excluded.titulo,
  periodo = excluded.periodo,
  dia     = excluded.dia,
  aberto  = excluded.aberto,
  roteiro = excluded.roteiro;

commit;
