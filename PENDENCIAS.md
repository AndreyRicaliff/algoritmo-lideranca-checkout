# Pendências

## 🔴 Críticas

- **2026-07-15 — Rotacionar a chave de produção do Asaas.** Foi compartilhada por chat e
  confirmada ativa em 15/07; o repositório é público desde então. Rotacionar no Asaas e atualizar
  `ASAAS_API_KEY` no Vercel. (Só Ricaliff pode fazer.)
- **2026-07-15 — `WHATSAPP_FALLBACK` não está setada no Vercel.** Verificado por requisição real:
  falha na cobrança devolve 502 com texto cru em vez de redirecionar pro WhatsApp. O código de
  fallback existe e está morto até a env var existir — toda venda que falha é perdida sem rastro.

## 🟠 Abertas

- **2026-07-27 — Confirmar a taxa de antecipação do Asaas.** `ASAAS_ANTECIPACAO_AM` está em 1,99%
  a.m. por estimativa, não por leitura do extrato. Afeta todo preço de cartão. Conferir em
  Asaas → Configurações → Taxas e ajustar a env var (não precisa mexer em código).
- **2026-07-27 — Grade da 2ª turma não confirmada.** A página segue anunciando "13 módulos" e
  "+15 horas" da 1ª turma; o briefing de lançamento falava em 14 módulos. Confirmar antes de subir
  tráfego pago.
- **2026-07-27 — Limpar registros de teste na conta de produção do Asaas.** Cliente "Teste
  Cobrança" + cobrança PIX pendente de R$ 1.280,50, criados na validação de 15/07.
- **2026-07-27 — `package.json` órfão em `C:\Projetos` contamina o repo localmente.** O
  `"type": "module"` do diretório pai faz o Node tratar `lib/preco.js` como ESM e `require()`
  devolver objeto vazio. Não afeta o Vercel (que só enxerga o repositório), mas quebra teste
  local. Corrigir com um `package.json` `{"type":"commonjs"}` na raiz — mudança de build, merece
  deploy próprio, fora da janela de lançamento.
- **2026-07-27 — Endpoint público sem rate limit.** `POST /api/inscrever` cria cliente + cobrança
  na conta de produção sem nenhum limite; como o acompanhamento é feito pelo painel do Asaas,
  spam polui a única fonte de verdade do lançamento.
