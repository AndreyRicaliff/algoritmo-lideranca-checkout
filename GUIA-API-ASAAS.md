# Guia de Integração — API Asaas (Algoritmo da Liderança)

**Para:** desenvolvedor da página (WordPress)
**Entregue por:** AG Consultoria
**Objetivo:** receber pagamento da inscrição (PIX e cartão) com a cobrança caindo na conta Asaas da AG, e confirmar a vaga automaticamente.

> A captação de lead (formulário) é construída à parte. Este guia cobre **só a camada de pagamento Asaas**: criar a cobrança e tratar a confirmação. Onde diz "o form", entenda o formulário que já existe na página.

---

## 1. Valores e regras do produto

| Método | Valor | Parcelas |
|---|---|---|
| **PIX (à vista)** | R$ 1.670 | — |
| **Cartão de crédito** | R$ 1.970 | até **5x sem juros** (a AG absorve a taxa) |

- **30 vagas** no total. Ao confirmar 30 pagamentos, encerrar novas inscrições.
- Após pagamento **confirmado**, enviar e-mail com: confirmação, dados do evento e **link do grupo de WhatsApp**.
- Sem garantia/estorno no fluxo.

---

## 2. Como a cobrança cai na conta certa (atrelar a conta)

No Asaas **não há um passo de "vincular conta"**: a cobrança credita **a conta dona da chave de API usada**. Portanto:

1. A AG gera a **API Key na própria conta Asaas** (Produção).
2. Essa chave é entregue ao dev e usada **só no servidor** (ver Segurança).
3. Toda cobrança criada com ela credita **a conta da AG**. Pronto — é esse o vínculo.

### Onde gerar a chave (painel Asaas)
`Configurações da conta` → `Integrações` → **Chave de API** (a chave de produção começa com `$aact_...`).
> Há chaves **separadas** para Sandbox e Produção. Desenvolva em Sandbox; troque pela de Produção só no go-live. *(Os rótulos exatos do menu podem variar — procurar a seção "Integrações / API".)*

### Identificação na fatura do cartão (recomendado)
Configurar o **descritivo que aparece no extrato do cartão** do cliente (algo curto e reconhecível, ex.: `AGCONSULT`) em `Configurações` → conta/empresa. Reduz disputas por "não reconheço a compra".

---

## 3. Endereços da API e autenticação

| Ambiente | Base URL |
|---|---|
| Sandbox | `https://api-sandbox.asaas.com/v3` *(confirmar host atual no doc)* |
| Produção | `https://api.asaas.com/v3` |

Autenticação por header (**não** é Bearer/OAuth):

```
access_token: $aact_SUA_CHAVE
Content-Type: application/json
```

---

## 4. Segurança (obrigatório)

- A **chave de API NUNCA** vai pro JavaScript / HTML / browser. Só no servidor.
  - Em WordPress: defina em `wp-config.php` como constante, não no banco nem no tema.
    ```php
    define('ASAAS_API_KEY', '$aact_...');
    define('ASAAS_BASE_URL', 'https://api.asaas.com/v3');
    define('ASAAS_WEBHOOK_TOKEN', 'um-token-secreto-que-voce-inventa');
    ```
- O dado de **cartão é digitado na tela do Asaas** (checkout hospedado, `invoiceUrl`). A página **não** coleta número de cartão — isso evita o escopo pesado de PCI-DSS.
- Não logar CPF nem dados de pagamento em claro.

---

## 5. Fluxo completo

```
[Form na página]
   └─(POST nome,email,cpf,telefone,método)─▶ [Endpoint PHP no WordPress]
                                                 1. valida
                                                 2. cria cliente  (POST /customers)
                                                 3. cria cobrança (POST /payments)
                                                 4. recebe invoiceUrl
   ◀────────────── devolve invoiceUrl ──────────┘
   redireciona o comprador ▶ [Checkout hospedado do Asaas]  ──paga──▶ Asaas

Asaas ──(webhook PAYMENT_CONFIRMED)──▶ [Endpoint webhook PHP]
                                          valida token, confirma a vaga,
                                          envia e-mail com link do grupo
```

`externalReference` é o campo que liga a cobrança do Asaas ao registro do inscrito no seu lado — quando o webhook chegar, é por ele que você identifica quem pagou.

---

## 6. Chamada 1 — Criar cliente · `POST /v3/customers`

**Body:**
```json
{
  "name": "Fulano de Tal",
  "email": "fulano@email.com",
  "cpfCnpj": "00000000000",
  "mobilePhone": "83999999999"
}
```
**Resposta (200):** `{ "id": "cus_000001", ... }` → guarde o `id`.

---

## 7. Chamada 2 — Criar cobrança · `POST /v3/payments`

O corpo **muda conforme o método** (o preço difere):

**PIX (R$ 1.670):**
```json
{
  "customer": "cus_000001",
  "billingType": "PIX",
  "value": 1670,
  "dueDate": "2026-07-31",
  "description": "Inscrição – Algoritmo da Liderança (Turma 2026)",
  "externalReference": "ID_DO_INSCRITO_NO_SEU_BANCO"
}
```

**Cartão (R$ 1.970 em 5x sem juros):**
```json
{
  "customer": "cus_000001",
  "billingType": "CREDIT_CARD",
  "installmentCount": 5,
  "totalValue": 1970,
  "dueDate": "2026-07-31",
  "description": "Inscrição – Algoritmo da Liderança (Turma 2026)",
  "externalReference": "ID_DO_INSCRITO_NO_SEU_BANCO"
}
```
**Resposta (200):** traz `invoiceUrl` → **redirecione o comprador para essa URL**. É o checkout do próprio Asaas (PIX com QR Code, ou formulário de cartão seguro).

---

## 8. Código de referência (WordPress / PHP)

> Server-side. Cole num plugin simples ou em `functions.php`. Mantém a chave fora do browser.

### 8.1 Helper de requisição
```php
function asaas_post($path, $body) {
    $resp = wp_remote_post(ASAAS_BASE_URL . $path, [
        'headers' => [
            'access_token' => ASAAS_API_KEY,
            'Content-Type' => 'application/json',
        ],
        'body'    => wp_json_encode($body),
        'timeout' => 20,
    ]);
    if (is_wp_error($resp)) {
        throw new Exception('Falha de rede Asaas: ' . $resp->get_error_message());
    }
    $code = wp_remote_retrieve_response_code($resp);
    $data = json_decode(wp_remote_retrieve_body($resp), true);
    if ($code < 200 || $code >= 300) {
        throw new Exception('Asaas ' . $path . ' erro ' . $code);
    }
    return $data;
}
```

### 8.2 Criar cliente
```php
function asaas_criar_cliente($nome, $email, $cpf, $telefone) {
    $data = asaas_post('/customers', [
        'name'        => $nome,
        'email'       => $email,
        'cpfCnpj'     => preg_replace('/\D/', '', $cpf),
        'mobilePhone' => preg_replace('/\D/', '', $telefone),
    ]);
    return $data['id'];
}
```

### 8.3 Montar e criar a cobrança (preço por método)
```php
function asaas_corpo_cobranca($customer_id, $metodo, $ref) {
    $base = [
        'customer'          => $customer_id,
        'dueDate'           => '2026-07-31',
        'description'       => 'Inscrição – Algoritmo da Liderança (Turma 2026)',
        'externalReference' => $ref,
    ];
    if ($metodo === 'pix') {
        return $base + ['billingType' => 'PIX', 'value' => 1670];
    }
    return $base + [
        'billingType'     => 'CREDIT_CARD',
        'installmentCount'=> 5,
        'totalValue'      => 1970,
    ];
}

function asaas_criar_cobranca($customer_id, $metodo, $ref) {
    $data = asaas_post('/payments', asaas_corpo_cobranca($customer_id, $metodo, $ref));
    return $data['invoiceUrl'];
}
```

### 8.4 Endpoint que o form chama (REST do WordPress)
```php
add_action('rest_api_init', function () {
    register_rest_route('alg/v1', '/inscrever', [
        'methods'             => 'POST',
        'permission_callback' => '__return_true',
        'callback'            => 'alg_inscrever',
    ]);
});

function alg_inscrever(WP_REST_Request $req) {
    $nome     = sanitize_text_field($req['nome']);
    $email    = sanitize_email($req['email']);
    $cpf      = sanitize_text_field($req['cpf']);
    $telefone = sanitize_text_field($req['telefone']);
    $metodo   = in_array($req['metodo'], ['pix', 'cartao'], true) ? $req['metodo'] : null;
    if (!$nome || !is_email($email) || !$cpf || !$metodo) {
        return new WP_REST_Response(['erro' => 'dados inválidos'], 400);
    }
    try {
        $ref     = wp_generate_uuid4(); // salve junto com os dados do inscrito (status: pendente)
        $cliente = asaas_criar_cliente($nome, $email, $cpf, $telefone);
        $url     = asaas_criar_cobranca($cliente, $metodo, $ref);
        return new WP_REST_Response(['invoiceUrl' => $url], 200);
    } catch (Exception $e) {
        return new WP_REST_Response(['erro' => 'falha ao gerar cobrança'], 502);
    }
}
```

No front, ao receber a resposta: `window.location = resposta.invoiceUrl;`

---

## 9. Webhook — confirmação do pagamento

O Asaas avisa o seu servidor quando o pagamento é confirmado. Cadastre **uma URL** em
`Configurações` → `Integrações` → **Webhooks**, com:
- **URL:** o endpoint abaixo (ex. `https://seusite.com/wp-json/alg/v1/asaas-webhook`)
- **Token de autenticação:** o mesmo valor de `ASAAS_WEBHOOK_TOKEN`

### Eventos que importam
- `PAYMENT_CONFIRMED` → pagamento confirmado (PIX caiu / cartão autorizado) — **libere a vaga aqui**.
- `PAYMENT_RECEIVED` → valor compensado.

### Endpoint do webhook
```php
add_action('rest_api_init', function () {
    register_rest_route('alg/v1', '/asaas-webhook', [
        'methods'             => 'POST',
        'permission_callback' => '__return_true',
        'callback'            => 'alg_webhook',
    ]);
});

function alg_webhook(WP_REST_Request $req) {
    $token = $req->get_header('asaas-access-token'); // confirmar nome do header no doc
    if ($token !== ASAAS_WEBHOOK_TOKEN) {
        return new WP_REST_Response(['erro' => 'não autorizado'], 401);
    }
    $evento = $req->get_json_params();
    if (($evento['event'] ?? '') !== 'PAYMENT_CONFIRMED') {
        return new WP_REST_Response(['ok' => true], 200); // ignora os outros
    }
    $ref = $evento['payment']['externalReference'] ?? '';
    alg_confirmar_inscricao($ref); // marcar pago (idempotente) + e-mail c/ link do grupo
    return new WP_REST_Response(['ok' => true], 200);
}
```

`alg_confirmar_inscricao()` (a implementar conforme onde os leads são salvos) deve:
1. Achar o inscrito pelo `externalReference`.
2. Se **já estiver pago, não fazer nada** (o Asaas pode reenviar o webhook — evita e-mail duplicado).
3. Marcar `pago`, registrar a data.
4. **Enviar o e-mail** com dados do evento + link do grupo de WhatsApp.
5. Contar pagos; ao chegar a 30, encerrar inscrições.

---

## 10. Contador de vagas (escassez)

A página mostra "Restam X vagas". Exponha **só o número** (sem dados pessoais):
`restantes = 30 - (quantidade de inscritos com status pago)`.
Faça um endpoint GET público que devolve `{ "restantes": N }` e o JS da página atualiza o texto.

---

## 11. Testes em Sandbox (antes de produção)

1. Gerar **chave Sandbox** e apontar `ASAAS_BASE_URL` para o host de sandbox.
2. Criar cliente + cobrança PIX e cartão; abrir o `invoiceUrl` e simular o pagamento (o Sandbox permite confirmar pagamentos de teste).
3. Verificar que o **webhook chega**, marca pago e dispara o e-mail.
4. Reenviar o mesmo webhook e confirmar que **não** manda 2 e-mails (idempotência).
5. Forçar 30 pagos e confirmar que novas inscrições são bloqueadas.

---

## 12. A confirmar no doc oficial (`docs.asaas.com`)

1. Host atual do **Sandbox**.
2. Cartão sem juros: `totalValue` + `installmentCount` (usado aqui) vs `installmentValue`.
3. Nome exato do **header de autenticação do webhook** (`asaas-access-token`?).
4. Diferença prática `PAYMENT_CONFIRMED` × `PAYMENT_RECEIVED` para liberar acesso.
5. Como **reusar cliente** pelo CPF (buscar antes de criar, evitar duplicado).

---

## 13. Checklist de entrega / go-live

- [ ] Chave de **Produção** configurada em `wp-config.php` (fora do browser).
- [ ] Descritivo de fatura do cartão configurado no Asaas.
- [ ] Webhook cadastrado com URL de produção + token.
- [ ] Teste ponta-a-ponta em Sandbox aprovado.
- [ ] E-mail de confirmação com link do grupo funcionando.
- [ ] Contador de vagas refletindo pagamentos.
- [ ] Política de privacidade / consentimento LGPD no form (coleta CPF, e-mail, telefone).
