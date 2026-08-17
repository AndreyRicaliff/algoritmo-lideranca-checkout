# Decisões — Checkout Algoritmo da Liderança

## 2026-07-27 — [preço] Fonte única de preço em vez de constante replicada
**Problema:** a 2ª turma tem preço que muda por data (R$ 1.280,50 até 31/07, R$ 1.977,00 a partir
de 01/08). O preço vivia duplicado em 4 arquivos (dois backends e dois fronts).
**Opções:** (A) editar a regra de lote nos 4 lugares; (B) módulo único no backend + endpoint que
o front consome; (C) renderizar o preço no HTML em build time.
**Decisão:** (B) — `lib/preco.js` como fonte única, exposto por `GET /api/preco`; o front deixou
de calcular preço e passou a exibir o que a API devolve.
**Por quê:** com preço fixo, duplicação é dívida estética. Com virada por data, ela vira cobrança
errada: front e backend podem discordar sobre qual lote está valendo. (C) não serve porque o site
é estático — o HTML publicado hoje seguiria mostrando o lote 1 depois da virada.
**Consequências:** o front depende de uma chamada de rede para exibir preço (degrada para
"consulte" se falhar, sem bloquear a inscrição). O `apps-script/Codigo.gs` foi marcado como
DESATIVADO em vez de sincronizado — manter dois backends com a mesma regra de preço reintroduz
exatamente o drift que esta decisão elimina.
**Em entrevista (30s):** "Preço que muda por data não pode ser constante duplicada. Centralizei
num módulo, expus por endpoint e fiz o front mandar de volta o preço que exibiu, pro backend
recusar a cobrança se tiver divergido."

## 2026-07-27 — [preço] Virada de lote no fuso de Brasília, não no relógio do runtime
**Problema:** decidir qual lote vale exige comparar "hoje" com a data de corte.
**Opções:** (A) `new Date()` do runtime; (B) `Intl.DateTimeFormat` fixando `America/Sao_Paulo`.
**Decisão:** (B), comparando strings `YYYY-MM-DD` (lexicográfica = cronológica).
**Por quê:** o runtime do Vercel roda em UTC. Em UTC a virada aconteceria à meia-noite UTC do
dia 01/08, que é **21h de 31/07 em Brasília** — as últimas três horas do lote promocional
cobrariam R$ 1.977,00 de quem viu R$ 1.280,50.
**Consequências:** toda data do domínio (lote, vencimento) passa pelo mesmo formatador.
**Em entrevista (30s):** "Data de corte comercial é fuso do negócio, não do servidor."

## 2026-07-27 — [preço] Antecipação repassada por gross-up linear, parametrizada por env var
**Problema:** repassar ao cliente a taxa de antecipação (receber em D+2 em vez de D+30 por
parcela), somada ao MDR, sem que a AG receba menos que a base.
**Opções:** (A) markup `base × (1+taxa)`; (B) gross-up `base / (1-taxa)`; (C) absorver.
**Decisão:** (B), com a taxa combinada = MDR da faixa + antecipação × meses adiantados, onde a
parcela k adianta (30k−2)/30 meses → fator médio (N+1)/2 − 1/15.
**Por quê:** markup não recompõe o valor descontado (o Asaas cobra sobre o total cobrado, não
sobre a base) e a AG receberia menos que R$ 1.977,00. O gross-up foi verificado nos 10
parcelamentos × 2 lotes: líquido bate na casa do centavo.
**Consequências:** a taxa combinada chega a ~14,8% em 10x, o que encarece a parcela de forma
visível. A taxa de antecipação vive em `ASAAS_ANTECIPACAO_AM` (default 1,99% a.m.) — **valor
ainda não confirmado no extrato do Asaas**; há um teto de sanidade de 35% que aborta em vez de
cobrar um preço absurdo por env var errada.
**Em entrevista (30s):** "Repasse de taxa é gross-up, não markup: divide pela taxa complementar,
senão você recupera menos do que pagou."

## 2026-08-16 — [nps] pesquisa do evento no Supabase AG-Converge, acesso só por RPC
**Problema:** pesquisa eNPS pós-evento precisa de persistência; o repo do checkout não tem banco.
**Opções:** A) projeto Supabase novo (custo extra na org Pro / pausa no free) · B) reusar
`survey_responses` do AG-Converge (tem `anon_select using(true)` — herdaria leitura pública) ·
C) tabelas novas `nps_*` no Converge, zero policies, acesso só por RPC SECURITY DEFINER.
**Decisão:** C. **Por quê:** org Pro não pausa; infra de eventos já é o Converge; fail-closed de
verdade — anon key pública não lê nem escreve linha; agregado sai por `nps_stats`, texto livre só
com chave (`nps_comentarios`, chave errada = vazio, sem oráculo). **Consequências:** migration
vive neste repo (`supabase/migrations/`) apontando pro Converge; anon key committada é pública por
design; perguntas têm fonte única em `lib/nps.js`.
**Em entrevista (30s):** "Pesquisa anônima com estatística agregada pública e dado bruto restrito:
em vez de policies de SELECT, tranquei a tabela inteira e expus duas RPCs SECURITY DEFINER — uma
grava com validação e upsert por sessão, outra devolve só histograma. A anon key pode vazar que
não há o que ler com ela."

## 2026-08-16 — [nps] login do /resultados validado no banco, sem env var e sem segredo no repo
**Problema:** painel precisa de login (usuário+senha fixos, sem 2FA) e a chave de comentários
morre; o repo é público e a senha pedida é reusada em outros sistemas da AG.
**Opções:** A) credencial hardcoded no front/API (vaza no repo público) · B) env vars no Vercel
(exige o dono provisionar + redeploy a cada troca; assinatura de cookie precisaria de segredo
extra) · C) credencial bcrypt no nps_config + sessão por token uuid em tabela, tudo validado
por RPC; cookie HttpOnly só transporta o token.
**Decisão:** C. **Por quê:** zero segredo em código/env; a senha nunca passa pelo assistente
(dono roda o UPDATE no SQL Editor); troca de senha não exige deploy; freio de 20 falhas/15min
protege uma senha reusada contra brute force; agregados também ficam atrás da sessão — login
obrigatório de verdade, não teatro de página.
**Consequências:** sessões de 30 dias em nps_admin_sessao; lockout temporário pode ser usado
pra travar o login por 15min (aceito, painel interno); nps_stats(text) e nps_comentarios
(chave) removidos após o deploy.
**Em entrevista (30s):** "Auth de painel interno sem infra nova: bcrypt no Postgres, sessão
por token opaco em cookie HttpOnly e autorização dentro de RPC SECURITY DEFINER — o serverless
é só transporte. O trade-off foi aceitar lockout coletivo de 15min em troca de frear brute
force numa senha que o cliente reusa."

## 2026-08-17 — [nps] comentários anônimos: o vínculo morre na RPC, não na página
**Problema:** o painel exibia autor em cima de cada comentário. Ricaliff pediu comentário
anônimo — mas parar de exibir não basta: `nps_textos` devolvia `sessao` e `created_at` em toda
linha, então o pareamento comentário↔nome continuava no JSON (F12 desfaz anonimato de fachada).
**Opções:** A) só remover o autor do HTML (anonimato de fachada) · B) apagar a seção de
identificação da pesquisa (perde a lista de quem participou, que o dono usa) · C) quebrar o
vínculo na RPC: comentário sem `sessao`, identificação sem `criado`, ordenação separada.
**Decisão:** C. **Por quê:** o front deste projeto é território do cliente e já é tratado como
não-confiável (toda a segurança vive em RPC SECURITY DEFINER); anonimato que só existe no
`innerHTML` é promessa que o próprio dono quebra abrindo o devtools. Ordem também vaza: array
cronológico reconstrói o par, então comentário sai por data e identificação em ordem alfabética.
Data sem hora no comentário — o horário exato entrega quem respondeu em qual momento da sala.
**Consequências:** a lista "quem se identificou" sobrevive, mas ninguém (nem o dono) consegue
saber quem escreveu qual comentário — inclusive para as 13 respostas já coletadas; se um dia
isso for necessário, só com acesso direto a `nps_respostas` no Supabase.
**Em entrevista (30s):** "Anonimato tem que ser propriedade do dado que sai da API, não do
template. Movi a quebra do vínculo pra dentro da RPC e cuidei dos canais laterais — ID de
sessão, timestamp e ordem do array — porque esconder no front é reversível com F12."
