<!-- Area de trabalho deste projeto. Carregado automaticamente em toda sessao aberta nesta pasta. -->

# Checkout - O Algoritmo da Lideranca

Lead + pagamento (Asaas) -> Google Sheets, mais a pesquisa/NPS do evento. **Repo PUBLICO.**

## Regra numero um: este repo e publico

Nada de credencial, dado real de cliente ou caminho de exploracao aqui - nem em comentario, nem em
migration, nem em doc. Pendencia sensivel vai em `C:\CODE\PENDENCIAS.md`, que e privado. O hook
`auto-backup` da push automatico, entao o erro se publica sozinho.

## Estado (18/08/2026)

Auditado em todas as refs, inclusive a branch `backup/pre-format-2026-07-10`: **zero chave de
gateway** no repo e no historico. A anon key do Supabase em `lib/nps.js` e `role=anon`, publica por
design - o que protege e a RLS atras dela, testada e fechada.

Telefone e e-mail em `apps-script/politica-de-privacidade.html` sao contato institucional
obrigatorio, nao vazamento.

## Desenho a manter

Acesso ao banco so por RPC `SECURITY DEFINER` com grant explicito; tabela com `revoke all` do anon.
O login do painel tem freio de forca-bruta - **nao exercitar o login as vesperas de evento**, sob
risco de travar o acesso real. Detalhe operacional das defesas fica em `C:\CODE\PENDENCIAS.md`,
que e privado.

### Pesquisa e multi-evento (desde 18/09/2026)

O questionario NAO mora mais no codigo. Cada pesquisa e uma linha em `nps_config` com o roteiro
em `jsonb`; a fonte versionada sao os JSON em `roteiros/`, e `scripts/nova-pesquisa.mjs` gera a
migration. Criar pesquisa nao exige deploy. Ver `roteiros/README.md`.

- **Migration aplicada por `sb.sh` tem que ser 100% ASCII**, comentario inclusive - o canal
  corrompe byte nao-ASCII no ENVIO. Texto em pt-BR entra como escape `\uXXXX` dentro de JSON.
  Historia completa em `supabase/migrations/20260817b_nps_errcodes_ascii.sql`.
- **Login e do painel, nao do evento** (`nps_painel`): uma sessao abre o catalogo inteiro.
- **Anonimato do comentario e garantido no BANCO**, nao na pagina: `nps_textos` devolve o
  comentario com `sessao` nula e a identificacao com data nula, e ordena cada um por criterio
  diferente. Vale para toda pesquisa nova sem reconfigurar nada - nao desfazer isso no front.
- **Rascunho do wizard e prefixado pelo slug** (`nps:<evento>:respostas`). Sem isso o celular de
  quem respondeu ontem pula direto pro "Obrigado" e a coleta do dia some sem erro.
- `/qr?e=<slug>` gera o cartaz na hora (vendor `assets/vendor/qrcode.js`, MIT).

## Onde as coisas ficam

- Inventario de todos os projetos: `C:\CODE\PROJETOS.md`
- Regras da area e do ambiente: `C:\CODE\CLAUDE.md`
- Pendencia **sensivel** (credencial, PII, caminho de exploracao) vai em `C:\CODE\PENDENCIAS.md`, nunca no repo do projeto quando ele for publico -- o hook `auto-backup` da push sem revisao humana.
