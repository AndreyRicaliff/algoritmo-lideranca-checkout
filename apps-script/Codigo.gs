/**
 * Checkout Algoritmo da Liderança — coletor de lead + pagamento Asaas → Google Sheets.
 *
 * Fluxo:
 *  1. Form da página faz POST aqui (nome, email, whatsapp, empresa, cpfCnpj, metodo).
 *  2. Grava o lead no Sheets IMEDIATAMENTE (mesmo se não pagar) — status "lead".
 *  3. Cria cliente + cobrança no Asaas e redireciona o comprador para a fatura (invoiceUrl).
 *  4. Webhook do Asaas confirma o pagamento → atualiza a linha para "pago".
 *
 * Preço: base líquida R$ 1.280,50 (PIX à vista — a AG absorve a taxa). No cartão a taxa
 * do Asaas (MDR) é repassada ao cliente por faixa de parcelas (gross-up): 2,99% à vista,
 * 3,49% (2–6x), 3,99% (7–10x). Chave do Asaas só em Propriedades do Script (nunca no front).
 */

// ---- Regras de negócio (CONFIRMAR com o financeiro) ----
const PRECO_BASE = 1280.50; // líquido que a AG quer receber (PIX à vista, e base do cartão)
const MAX_PARCELAS = 10;

// Taxas do Asaas (MDR sobre o total da venda), repassadas ao cliente no cartão, por faixa.
// No PIX a AG absorve a taxa: o cliente paga só o PRECO_BASE.
const TAXA_CARTAO_AVISTA = 0.0299; // 1x
const TAXA_CARTAO_2_6    = 0.0349; // 2 a 6 parcelas
const TAXA_CARTAO_7_12   = 0.0399; // 7 a 12 parcelas

// Gross-up: o cliente paga um total X tal que, após o Asaas descontar a taxa sobre o total,
// a AG receba exatamente o PRECO_BASE.  X * (1 - taxa) = PRECO_BASE  ->  X = PRECO_BASE/(1-taxa)
function taxaCartao(parcelas) {
  if (parcelas <= 1) return TAXA_CARTAO_AVISTA;
  if (parcelas <= 6) return TAXA_CARTAO_2_6;
  return TAXA_CARTAO_7_12;
}
function totalCartao(parcelas) {
  return centavos(PRECO_BASE / (1 - taxaCartao(parcelas)));
}
function centavos(v) {
  return Math.round(v * 100) / 100;
}

// ---- Roteamento ----
function doPost(e) {
  const ehWebhook = e.postData && e.postData.type === 'application/json';
  return ehWebhook ? handleWebhook(e) : handleInscricao(e);
}

// ---- Inscrição (lead + cobrança) ----
function handleInscricao(e) {
  const dados = lerFormulario(e);
  const erro = validar(dados);
  if (erro) return paginaErro(erro);

  const linha = salvarLead(dados); // salva ANTES do Asaas — não perde o lead
  try {
    const cliente = criarCliente(dados);
    const cobranca = criarCobranca(cliente.id, dados);
    atualizarPagamento(linha, cobranca.id, 'aguardando_pagamento');
    return redirecionar(cobranca.invoiceUrl);
  } catch (err) {
    atualizarPagamento(linha, '', 'erro_cobranca');
    return redirecionar(prop('WHATSAPP_FALLBACK')); // não perde a venda: cai no comercial
  }
}

function lerFormulario(e) {
  const p = e.parameter;
  return {
    nome: (p.nome || '').trim(),
    email: (p.email || '').trim(),
    whatsapp: somenteDigitos(p.whatsapp),
    empresa: (p.empresa || '').trim(),
    cpfCnpj: somenteDigitos(p.cpfCnpj),
    metodo: ['cartao', 'boleto', 'pix'].indexOf(p.metodo) >= 0 ? p.metodo : 'pix',
    parcelas: clampParcelas(p.parcelas),
    utm: (p.utm || '').trim()
  };
}

function validar(d) {
  if (!d.nome) return 'Informe seu nome.';
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(d.email)) return 'E-mail inválido.';
  if (d.whatsapp.length < 10) return 'WhatsApp inválido (com DDD).';
  if (d.cpfCnpj.length < 11) return 'CPF/CNPJ inválido.';
  return null;
}

// ---- Asaas ----
function asaasRequest(path, payload) {
  const base = prop('ASAAS_AMBIENTE') === 'producao'
    ? 'https://api.asaas.com/v3'
    : 'https://api-sandbox.asaas.com/v3';
  const res = UrlFetchApp.fetch(base + path, {
    method: 'post',
    contentType: 'application/json',
    headers: { access_token: prop('ASAAS_API_KEY') },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  });
  const body = JSON.parse(res.getContentText() || '{}');
  if (res.getResponseCode() >= 300) {
    throw new Error('Asaas ' + res.getResponseCode() + ': ' + res.getContentText());
  }
  return body;
}

function criarCliente(d) {
  return asaasRequest('/customers', {
    name: d.nome, email: d.email, mobilePhone: d.whatsapp,
    cpfCnpj: d.cpfCnpj, externalReference: d.email
  });
}

function criarCobranca(customerId, d) {
  return asaasRequest('/payments', corpoCobranca(customerId, d));
}

function corpoCobranca(customerId, d) {
  const base = {
    customer: customerId,
    dueDate: vencimento(),
    description: 'Inscrição – Algoritmo da Liderança (Turma 2026)',
    externalReference: d.email
  };
  // Asaas só aceita callback.successUrl com um site/domínio cadastrado na conta; sem isso derruba a cobrança.
  const successUrl = prop('SUCCESS_URL');
  if (successUrl) base.callback = { successUrl: successUrl, autoRedirect: true };
  if (d.metodo === 'cartao') {
    base.billingType = 'CREDIT_CARD';
    const total = totalCartao(d.parcelas); // já com a taxa da faixa repassada ao cliente
    if (d.parcelas <= 1) {
      base.value = total;                  // à vista (1x)
    } else {
      base.installmentCount = d.parcelas;  // Asaas divide o total nas parcelas
      base.totalValue = total;             // cliente paga o total; AG recebe o PRECO_BASE líquido
    }
  } else if (d.metodo === 'boleto') {
    base.billingType = 'BOLETO';
    base.value = PRECO_BASE; // boleto à vista = mesmo preço do PIX (AG absorve)
  } else {
    base.billingType = 'PIX';
    base.value = PRECO_BASE; // PIX à vista: AG absorve a taxa
  }
  return base;
}

function vencimento() {
  return prop('CHECKOUT_DUE_DATE') || '2026-07-31';
}

// ---- Webhook de pagamento ----
function handleWebhook(e) {
  if (e.parameter.token !== prop('WEBHOOK_TOKEN')) {
    return ContentService.createTextOutput('forbidden');
  }
  const corpo = JSON.parse(e.postData.contents || '{}');
  const pago = corpo.event === 'PAYMENT_CONFIRMED' || corpo.event === 'PAYMENT_RECEIVED';
  if (pago && corpo.payment) marcarPago(corpo.payment.id);
  return ContentService.createTextOutput('ok'); // sempre 2xx p/ o Asaas não reenfileirar
}

// ---- Planilha ----
function aba() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName('Inscrições') || ss.insertSheet('Inscrições');
  if (sheet.getLastRow() === 0) {
    sheet.appendRow(['Data', 'Nome', 'E-mail', 'WhatsApp', 'Empresa',
      'CPF/CNPJ', 'Método', 'Valor', 'Status', 'Asaas ID', 'UTM']);
  }
  return sheet;
}

function salvarLead(d) {
  const sheet = aba();
  const valor = d.metodo === 'cartao' ? totalCartao(d.parcelas) : PRECO_BASE;
  sheet.appendRow([new Date(), d.nome, d.email, d.whatsapp, d.empresa,
    d.cpfCnpj, d.metodo, valor, 'lead', '', d.utm]);
  return sheet.getLastRow();
}

function atualizarPagamento(linha, asaasId, status) {
  const sheet = aba();
  sheet.getRange(linha, 9).setValue(status);   // coluna Status
  sheet.getRange(linha, 10).setValue(asaasId);  // coluna Asaas ID
}

function marcarPago(paymentId) {
  const sheet = aba();
  const total = Math.max(sheet.getLastRow() - 1, 1);
  const ids = sheet.getRange(2, 10, total, 1).getValues();
  for (let i = 0; i < ids.length; i++) {
    if (ids[i][0] === paymentId) {
      sheet.getRange(i + 2, 9).setValue('pago'); // idempotente: regravar 'pago' é inócuo
      return;
    }
  }
}

// ---- Utilitários ----
function prop(nome) {
  return PropertiesService.getScriptProperties().getProperty(nome) || '';
}
function somenteDigitos(v) {
  return (v || '').replace(/\D/g, '');
}
function clampParcelas(v) {
  const n = parseInt(v, 10);
  return (isNaN(n) || n < 1) ? 1 : Math.min(n, MAX_PARCELAS);
}
function redirecionar(url) {
  return HtmlService.createHtmlOutput('<script>location.href=' + JSON.stringify(url) + '</script>');
}
function paginaErro(msg) {
  return HtmlService.createHtmlOutput('<p>' + msg + ' <a href="javascript:history.back()">Voltar</a></p>');
}
