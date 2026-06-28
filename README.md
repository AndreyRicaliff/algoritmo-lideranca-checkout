# Checkout Algoritmo da Liderança — Lead + Pagamento → Google Sheets

Coletor de lead + pagamento Asaas, com tudo caindo numa **Planilha Google**. Sem servidor,
sem banco: roda em **Google Apps Script**. A chave do Asaas fica só em Propriedades do Script
(nunca no browser). O checkout de cartão/PIX é hospedado pelo próprio Asaas (zero PCI).

> Abordagem escolhida pela AG: simples (Sheets). A alternativa Supabase está documentada no
> design spec em `docs/` mas **não** é a implementação ativa.

## Fluxo
```
Form da página ──POST──▶ Apps Script ──▶ grava o lead no Sheets (status "lead")
                                      └─▶ cria cliente + cobrança no Asaas
                                          └─▶ redireciona p/ invoiceUrl (paga PIX ou cartão 5x)
Asaas ──webhook──▶ Apps Script ──▶ atualiza a linha para "pago"
```
O lead é salvo **antes** do pagamento — quem abandona o checkout fica registrado.
Se o Asaas falhar, o comprador cai no **WhatsApp** (não perde a venda).

## Arquivos
| Arquivo | Onde vai |
|---|---|
| `apps-script/Codigo.gs` | Apps Script vinculado à planilha (Extensões → Apps Script) |
| `apps-script/form-inscricao.html` | Bloco HTML na página de vendas |
| `apps-script/obrigado.html` | Página `/obrigado` (successUrl do Asaas) |

## Setup
1. Crie uma **Planilha Google** (será a base de leads).
2. **Extensões → Apps Script**, cole `apps-script/Codigo.gs`.
3. **Configurações do projeto → Propriedades do script:**
   | Propriedade | Valor |
   |---|---|
   | `ASAAS_API_KEY` | chave da API do Asaas (Integrações → API Key) |
   | `ASAAS_AMBIENTE` | `sandbox` (testes) ou `producao` |
   | `WEBHOOK_TOKEN` | um segredo (32+ caracteres) — valida o webhook |
   | `SUCCESS_URL` | `https://agconsultorialtda.com/obrigado` |
   | `WHATSAPP_FALLBACK` | `https://wa.me/5583999661686` |
   | `CHECKOUT_DUE_DATE` | `2026-07-31` |
4. **Implantar → Nova implantação → App da Web**, executar como **Eu**, acesso **Qualquer pessoa**. Copie a URL `…/exec`.
5. Cole `form-inscricao.html` na página e troque o `action` pela URL `…/exec`.
6. Publique `obrigado.html` em `https://agconsultorialtda.com/obrigado`.

### Webhook no Asaas
Integrações → Webhooks → URL `https://script.google.com/macros/s/SEU_ID/exec?token=WEBHOOK_TOKEN`
(Apps Script não lê header — validamos pela URL). Eventos: `PAYMENT_CONFIRMED` e `PAYMENT_RECEIVED`.

## O que cai na planilha (aba "Inscrições")
`Data · Nome · E-mail · WhatsApp · Empresa · CPF/CNPJ · Método · Valor · Status · Asaas ID · UTM`
Status: `lead` → `aguardando_pagamento` → `pago` (ou `erro_cobranca`).

## Preços / métodos
- PIX à vista: **R$ 1.670** · Cartão: **R$ 1.970 em até 5x** (`installmentCount` + `totalValue`).
- **Boleto fora** (conforme o guia/spec). Se quiser, é fácil adicionar.

## Pendências (você / AG)
- [ ] Chave **sandbox** do Asaas para testar; depois a de produção.
- [ ] Testar ponta-a-ponta no sandbox: form → lead na planilha → pagar → webhook marca "pago".
- [ ] LGPD: o form já tem checkbox de consentimento; criar a página `/politica-de-privacidade`.

## API Asaas usada (verificada na doc oficial)
- Base: prod `https://api.asaas.com/v3` · sandbox `https://api-sandbox.asaas.com/v3` · header `access_token`
- `POST /customers` → `id`; `POST /payments` (PIX `value`; cartão `installmentCount`+`totalValue`) → `invoiceUrl`
- Webhook `{ event, payment }`; idempotente; responder 2xx.
