# Pendências

> Este repositório é público. Pendência de segurança não entra aqui: vai no registro privado da
> AG (regra do `CLAUDE.md`).

## 🔴 Críticas

- **2026-07-15 — `WHATSAPP_FALLBACK` não está setada no Vercel.** Verificado por requisição real:
  falha na cobrança devolve 502 com texto cru em vez de redirecionar pro WhatsApp. O código de
  fallback existe e está morto até a env var existir — toda venda que falha é perdida sem rastro.
  Reconfirmada ausente em 11/10/2026. Setar antes de abrir a próxima turma.

- **2026-10-09 — `algoritmo.agconsultorialtda.com` não resolve (NXDOMAIN em 1.1.1.1 e 8.8.8.8).** O
  domínio segue cadastrado no projeto Vercel, mas o registro sumiu da zona da Cloudflare — no mesmo dia em
  que `educacao.agconsultorialtda.com` entrou. É o domínio canônico deste CLAUDE.md (QR, links,
  lead page): todo link/QR impresso com ele está quebrado. Decidir (só Ricaliff): recriar o CNAME
  `algoritmo` → `cname.vercel-dns.com`, ou declarar `educacao` o canônico e atualizar o CLAUDE.md.
  Reconfirmado em 11/10: a lead page publicada no WordPress tem `action` e `fetch` em `algoritmo.`,
  então hoje o form dela nem chega à API (erro de DNS no navegador). A escolha arrasta o WordPress
  junto: ou o CNAME volta, ou todo link/QR/form de lá passa para `educacao.`.

## 🟠 Abertas

- **2026-10-14 — Republicar a lead page do WordPress com o `apps-script/leadpage.html` atual.** A
  cópia publicada é anterior ao painel "Inscrições encerradas": quando a API voltar a responder
  (item de DNS acima), ela recebe `{ encerrado: true }`, cai em "consulte" e, ao enviar, mostra o 410
  em texto cru. A venda já está fechada no backend; o que falta é a página de lá dizer isso bonito.

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
