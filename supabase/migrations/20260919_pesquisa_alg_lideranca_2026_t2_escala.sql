-- Pesquisa: alg-lideranca-2026-t2-escala
-- Gerada por scripts/nova-pesquisa.mjs a partir de alg-lideranca-2026-t2-escala.json.
-- ARQUIVO 100% ASCII: acento viaja como escape \uXXXX e o jsonb decodifica (ver 20260817b).
--
-- 21 perguntas em 10 secoes.
-- Reaplicar este arquivo ATUALIZA a pesquisa (upsert) -- as respostas ja gravadas nao
-- sao tocadas. Mudar o texto de uma pergunta sem mudar o id reescreve o rotulo tambem
-- no historico do painel, que passa a exibir o texto novo para respostas antigas.

begin;

insert into public.nps_config (evento, titulo, periodo, dia, aberto, roteiro)
values (
  'alg-lideranca-2026-t2-escala',
  ('"Avalia\u00e7\u00e3o \u00b7 M\u00f3dulo A Escala"'::jsonb ->> 0),
  ('"19/09/2026 \u00b7 noite"'::jsonb ->> 0),
  date '2026-09-19',
  true,
  '{"subtitulo":"O l\u00edder e a organiza\u00e7\u00e3o \u00b7 Cerca de 2 minutos. Resposta an\u00f4nima (identifica\u00e7\u00e3o opcional).","escalaRotulos":["Muito ruim","Ruim","Regular","Bom","Excelente"],"secoes":[{"id":"identificacao","titulo":"Identifica\u00e7\u00e3o","sub":"Opcional \u2014 pode pular sem responder.","perguntas":[{"id":"ident_nome","tipo":"texto","max":120,"texto":"Nome"},{"id":"ident_cargo","tipo":"texto","max":120,"texto":"\u00c1rea / cargo"}]},{"id":"pautas","titulo":"A Escala \u00b7 As pautas","sub":"Como voc\u00ea avalia cada pauta deste m\u00f3dulo?","perguntas":[{"id":"p_time","tipo":"escala","texto":"Formando o Time"},{"id":"p_cultura","tipo":"escala","texto":"Cultura e Clima Organizacional"},{"id":"p_visao","tipo":"escala","texto":"Vis\u00e3o Estrat\u00e9gica"},{"id":"p_vendedor","tipo":"escala","texto":"O L\u00edder Vendedor"},{"id":"p_cafe","tipo":"escala","texto":"B\u00f4nus \u00b7 C.A.F.E. com Dados"}]},{"id":"conducao","titulo":"Condu\u00e7\u00e3o, ritmo e aplica\u00e7\u00e3o","sub":"Como voc\u00ea avalia cada item?","perguntas":[{"id":"e_facilitador","tipo":"escala","texto":"Condu\u00e7\u00e3o dos facilitadores"},{"id":"e_ritmo","tipo":"escala","texto":"Ritmo e dura\u00e7\u00e3o do m\u00f3dulo"},{"id":"e_aplicabilidade","tipo":"escala","texto":"Aplicabilidade no seu dia a dia"}]},{"id":"percepcao","titulo":"Sequ\u00eancia e energia","sub":"Escolha uma op\u00e7\u00e3o em cada.","perguntas":[{"id":"seq_pautas","tipo":"opcao","texto":"Como voc\u00ea percebeu a sequ\u00eancia das pautas deste m\u00f3dulo?","opcoes":["Complementares, uma preparou a outra","Houve repeti\u00e7\u00e3o de conte\u00fado entre elas","Faltou conex\u00e3o entre as pautas","N\u00e3o soube avaliar"]},{"id":"energia_final","tipo":"opcao","texto":"Como voc\u00ea chegou ao final deste m\u00f3dulo?","opcoes":["Com energia, daria para seguir","Cansado, mas acompanhando bem","No limite, perdi o fio em alguns momentos","Exausto, rendi pouco na parte final"]}]},{"id":"destaques","titulo":"Destaques do m\u00f3dulo","sub":"Escolha uma pauta em cada.","perguntas":[{"id":"pauta_top","tipo":"opcao","texto":"Qual pauta deste m\u00f3dulo mais valeu o seu tempo?","opcoes":["Formando o Time","Cultura e Clima Organizacional","Vis\u00e3o Estrat\u00e9gica","O L\u00edder Vendedor","B\u00f4nus \u00b7 C.A.F.E. com Dados"]},{"id":"pauta_encurtar","tipo":"opcao","texto":"Qual pauta voc\u00ea encurtaria?","opcoes":["Formando o Time","Cultura e Clima Organizacional","Vis\u00e3o Estrat\u00e9gica","O L\u00edder Vendedor","B\u00f4nus \u00b7 C.A.F.E. com Dados","Nenhuma"]}]},{"id":"nota","titulo":"Nota do m\u00f3dulo","sub":"0\u20136 detrator \u00b7 7\u20138 neutro \u00b7 9\u201310 promotor","perguntas":[{"id":"nps_geral","tipo":"nps","texto":"De 0 a 10, que nota voc\u00ea d\u00e1 para este m\u00f3dulo?","min":"Muito ruim","max":"Excelente"}]},{"id":"comentario","titulo":"Coment\u00e1rio","sub":"Opcional.","perguntas":[{"id":"comentario","tipo":"texto","max":1000,"texto":"O que mais te marcou e o que podemos melhorar neste m\u00f3dulo?"}]},{"id":"alimentacao","titulo":"Alimenta\u00e7\u00e3o","sub":null,"perguntas":[{"id":"al_almoco","tipo":"escala","texto":"Qualidade do almo\u00e7o"},{"id":"al_tempo_almoco","tipo":"escala","texto":"Tempo dispon\u00edvel para almo\u00e7ar"},{"id":"al_coffee","tipo":"escala","texto":"Qualidade do coffee break da tarde de s\u00e1bado"}]},{"id":"bonus_formato","titulo":"Formato do b\u00f4nus no intervalo","sub":"Escolha uma op\u00e7\u00e3o.","perguntas":[{"id":"bonus_formato","tipo":"opcao","texto":"Como funcionou o b\u00f4nus durante o coffee break?","opcoes":["Funcionou bem, consegui acompanhar e me servir","Interessante, mas me dividi entre acompanhar e fazer o intervalo","Preferia o intervalo livre, sem conte\u00fado","Preferia o b\u00f4nus como pauta separada, fora do intervalo"]}]},{"id":"com_alimentacao","titulo":"Alimenta\u00e7\u00e3o e intervalos","sub":"Opcional.","perguntas":[{"id":"com_alimentacao","tipo":"texto","max":500,"texto":"Coment\u00e1rio sobre alimenta\u00e7\u00e3o e intervalos"}]}]}'::jsonb
)
on conflict (evento) do update set
  titulo  = excluded.titulo,
  periodo = excluded.periodo,
  dia     = excluded.dia,
  aberto  = excluded.aberto,
  roteiro = excluded.roteiro;

commit;
