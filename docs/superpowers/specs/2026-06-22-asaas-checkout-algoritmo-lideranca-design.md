# Checkout Asaas — Algoritmo da Liderança

**Data:** 2026-06-22
**Status:** Spec aprovado (aguardando revisão final do Ricalfiff)
**Prazo duro:** 13/07/2026 — página no ar com checkout + contador funcionando (impreterível)

---

## 1. Contexto

Venda da formação presencial **Algoritmo da Liderança** (AG Consultoria), Campina Grande/PB
(Catolé), 13 módulos. Lançamento com janela de vendas **13/07 → 31/07/2026**; aulas
**01/08 → 19/09/2026**. Fonte de verdade da estratégia: `~/projetos/algoritmo-lideranca-ads/README.md`.

O objetivo desta entrega é o **caminho de conversão por checkout** (pago via Asaas), embutido na
página WordPress/Elementor existente (`agconsultorialtda.com/algoritmo-da-lideranca/`), com
**contador de vagas em tempo real**.

### Regras de negócio confirmadas

| Item | Valor |
|---|---|
| Vagas | **30 total** (2 turmas de 15) — AG aloca a turma depois |
| Contador | Único, de 30, público em tempo real |
| Preço PIX (à vista) | **R$ 1.670** |
| Preço Cartão | **R$ 1.970** em **5x sem juros** (AG absorve a taxa) |
| Métodos | PIX e cartão de crédito |
| Pós-pagamento | E-mail com confirmação + dados do evento + link do grupo WhatsApp |
| Garantia/estorno | Não há — fluxo de reembolso fora de escopo |
| Login / área de membros | Não há |
| Escolha de turma no checkout | Não — AG aloca depois; e-mail diz "sua turma será confirmada" |

### Decisão arquitetural central

**Nível 2 — API cria a cobrança + checkout hospedado pelo Asaas.** O backend orquestra a cobrança
via API, mas o dado de cartão é digitado na tela do **próprio Asaas** (`invoiceUrl`). Isso mantém a
AG **fora do escopo pesado de PCI-DSS**. Rejeitado o nível 3 (checkout próprio tokenizando cartão):
ganho cosmético, custo regulatório alto, sem retorno para 30 inscritos.

---

## 2. Arquitetura

```
[Página WordPress/Elementor]
  ├── Form (widget HTML/JS)  ──POST──▶  [Edge: criar-cobranca]  ──API──▶  Asaas
  │        nome, email, cpf,                 valida + checa vaga          (customer + payment)
  │        telefone, método                  grava inscricao(pendente)
  │                                          ◀── invoiceUrl ──────────────┘
  │   redireciona ▶ [Checkout hospedado Asaas]  ── paga ──▶  Asaas
  │
  └── Contador "Restam X" ◀──GET── [Edge: vagas]  (só número, sem PII)

Asaas ──webhook PAYMENT_CONFIRMED──▶ [Edge: asaas-webhook]
                                        valida token, marca pago (idempotente),
                                        envia e-mail (Resend) c/ link do grupo,
                                        alerta admin ao atingir limiar
```

### Componentes

**A. Form na landing (Elementor — widget HTML/JS custom)**
Coleta: `nome`, `email`, `cpf`, `telefone`, `metodo` (radio: PIX R$1.670 / Cartão R$1.970 5x).
Valida CPF e e-mail no cliente (UX) — a validação **autoritativa** é no backend. Faz `POST` para
`criar-cobranca`. **Nunca** contém a chave do Asaas. Ao receber `invoiceUrl`, redireciona.

**B. Edge Function `criar-cobranca` (Supabase)**
1. Valida payload no boundary (nome, e-mail, CPF válido, telefone, método ∈ {pix, cartao}).
2. Checa vaga: `COUNT(status='pago') < 30` — senão retorna `409 esgotado`.
3. `POST /v3/customers` no Asaas (ou reusa por CPF) → `asaas_customer_id`.
4. Grava `inscricoes` com `status='pendente'` → gera `id` (UUID).
5. `POST /v3/payments` com `externalReference = id`, valor/parcelas conforme método.
6. Salva `asaas_payment_id` na linha; retorna `{ invoiceUrl }`.

**C. Edge Function `asaas-webhook` (Supabase)**
1. Valida header de token secreto (rejeita se não bater → `401`).
2. Lê `event` + `payment.externalReference`.
3. Em `PAYMENT_CONFIRMED`/`PAYMENT_RECEIVED`: acha a inscrição; se já `pago`, **no-op** (idempotente)
   e retorna `200`; senão marca `pago`.
4. Dispara e-mail (Resend) com dados do evento + link do grupo WhatsApp.
5. Se `COUNT(pago) >= LIMIAR_ALERTA` (config, ex. 27), notifica admin.
6. Sempre responde `200` rápido para eventos conhecidos; loga o resto.

**D. Edge Function `vagas` (Supabase — pública, GET)**
Retorna `{ restantes: 30 - COUNT(status='pago'), total: 30 }`. **Sem PII.** Cache curto (ex. 30s)
para aguentar tráfego da campanha.

### Onde a chave do Asaas vive
Somente como **secret** nas edge functions (Supabase secrets). Nunca no WordPress, nunca no browser.

---

## 3. Modelo de dados

Tabela `inscricoes` (Supabase / Postgres):

| Coluna | Tipo | Nota |
|---|---|---|
| `id` | uuid (pk, default gen) | usado como `externalReference` no Asaas |
| `nome` | text | |
| `email` | text | |
| `cpf` | text | só dígitos; validado no boundary |
| `telefone` | text | |
| `metodo` | text | `pix` \| `cartao` |
| `valor` | integer | em reais (1670 ou 1970) |
| `asaas_customer_id` | text | `cus_...` |
| `asaas_payment_id` | text | `pay_...` |
| `status` | text | `pendente` \| `pago` \| `cancelado` |
| `created_at` | timestamptz | default now() |
| `paid_at` | timestamptz | preenchido pelo webhook |

**RLS:** habilitada, **service-role only**. Nenhuma leitura/escrita anônima direto na tabela — todo
acesso passa pelas edge functions. O contador NÃO lê a tabela do browser; lê pela função `vagas`.

**Config** (tabela `config` chave-valor OU env das functions): `data_inicio_aulas`, `data_fim_aulas`,
`local`, `link_grupo_whatsapp`, `limite_vagas=30`, `limiar_alerta=27`, `email_admin`,
`template_email`.

---

## 4. Fluxo de dados (happy path)

1. Visitante preenche o form e escolhe método → `POST criar-cobranca`.
2. Backend valida, reserva conceitualmente (checa < 30), cria customer + payment no Asaas, grava
   `pendente`, devolve `invoiceUrl`.
3. Browser redireciona para o checkout hospedado do Asaas.
4. Visitante paga (PIX QR ou cartão na tela do Asaas).
5. Asaas dispara `webhook PAYMENT_CONFIRMED` → backend marca `pago`, envia e-mail com link do grupo,
   atualiza contador implicitamente.
6. Contador da página reflete `restantes` na próxima chamada a `vagas`.

---

## 5. Tratamento de erro e bordas

- **Falha na API do Asaas** (criar customer/payment): retorna erro ao form; inscrição **não** vira
  `pago`. Se a linha `pendente` já foi gravada e o payment falhou, marca `cancelado` ou remove.
- **Webhook idempotente:** confirmação dupla (Asaas reenvia) não manda 2 e-mails — checa `status` já
  `pago` antes de agir.
- **Webhook autenticado:** token secreto no header; rejeita o que não bater.
- **Oversell:** controle simples conta `status='pago'`. Risco teórico de >30 se muitos `pendente`
  pagarem quase juntos no fim. Aceito para 30 vagas + alerta em 27. (Mitigação futura, se preciso:
  reserva em `pendente` com expiração.)
- **CPF/e-mail inválido:** rejeitado no boundary do `criar-cobranca`.
- **Esgotado:** `criar-cobranca` retorna `409`; o form mostra "vagas esgotadas" e o contador zera.

---

## 6. Segurança e LGPD

- Chave Asaas e token de webhook: **somente** secrets das edge functions.
- RLS service-role-only em `inscricoes`; função `vagas` expõe só contagem.
- Coleta de **PII** (nome, CPF, e-mail, telefone) → LGPD:
  - **Finalidade:** processar inscrição e contato sobre a turma. Explicitar no form (checkbox de
    consentimento + link à política).
  - **Minimização:** coletar só o necessário para a cobrança e o contato.
  - **Retenção/descarte:** definir prazo (ex. expurgar `pendente` não pago após X dias).
  - **Acesso restrito:** só service-role / admin.
  - Rodar a skill `lgpd-check` na fase de implementação.
- Sem `console.log` de dados de pagamento/CPF em claro.

---

## 7. Variáveis de ambiente / secrets

| Secret | Onde |
|---|---|
| `ASAAS_API_KEY` | edge functions |
| `ASAAS_BASE_URL` | edge functions (sandbox vs produção) |
| `ASAAS_WEBHOOK_TOKEN` | edge functions (valida o header do webhook) |
| `RESEND_API_KEY` | edge functions |
| `SUPABASE_SERVICE_ROLE_KEY` | edge functions |

`.env.example` versionado, sem valores. Build/testes em **sandbox**; vira produção só no fim.

---

## 8. Testes

- **Sandbox Asaas:** simular pagamento PIX e cartão confirmados; validar que o webhook marca `pago` e
  o e-mail sai com o link do grupo.
- **Idempotência:** reenviar o mesmo webhook → 1 e-mail só.
- **Boundary:** CPF inválido / método inválido → `400`.
- **Esgotado:** forçar 30 pagos → `criar-cobranca` retorna `409` e `vagas` retorna `0`.
- **Contador:** `vagas` reflete o número correto após pagamentos.

---

## 9. A confirmar no doc oficial do Asaas (antes de implementar)

Não decorado — verificar em `docs.asaas.com`:
1. Host exato do **sandbox** (`api-sandbox.asaas.com/v3`?).
2. Cartão sem juros 5x: usar `totalValue` vs `installmentValue` em `POST /payments`.
3. Nome do header de **autenticação do webhook**.
4. Semântica `PAYMENT_CONFIRMED` × `PAYMENT_RECEIVED` para liberar acesso (PIX e cartão).
5. Como **reusar customer** por CPF (buscar antes de criar, evitar duplicado).

---

## 10. Fora de escopo

- Área de membros / login.
- Reembolso/estorno (sem garantia).
- Escolha de turma no checkout (AG aloca depois).
- Split de pagamento.
- Caminho de conversão por WhatsApp (este spec cobre só o checkout pago).

---

## 11. Caminho crítico

Hoje **22/06**. Página com checkout + contador **no ar e testada até 13/07** (impreterível, do plano
da AG). ~3 semanas. Sequência sugerida: tabela+RLS → `criar-cobranca` (sandbox) → `asaas-webhook`
(sandbox) → `vagas` → form no Elementor → teste ponta-a-ponta sandbox → virar produção.
