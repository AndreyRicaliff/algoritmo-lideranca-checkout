// Vercel Serverless Function — cria cliente + cobrança no Asaas e redireciona pro checkout.
// Porta a lógica testada do Apps Script (apps-script/Codigo.gs) pro runtime do Vercel.
// A chave Asaas vive SÓ em env var (nunca no front/repo): definir no painel Vercel.
//
// Env vars (Settings -> Environment Variables):
//   ASAAS_API_KEY      (obrigatória)  chave $aact_... — use a de SANDBOX para testar
//   ASAAS_AMBIENTE     'producao' | 'sandbox' (default sandbox)
//   SUCCESS_URL        (opcional) página pós-pagamento; default /apps-script/obrigado.html
//   WHATSAPP_FALLBACK  (opcional) pra onde mandar se a cobrança falhar
//   CHECKOUT_DUE_DATE  (opcional) vencimento YYYY-MM-DD (default 2026-07-31)

const PRECO_BASE = 1280.50;   // líquido que a AG quer receber (PIX à vista, base do cartão)
const MAX_PARCELAS = 10;
const TAXA_AVISTA = 0.0299;   // 1x
const TAXA_2_6 = 0.0349;      // 2 a 6 parcelas
const TAXA_7_12 = 0.0399;     // 7 a 12 parcelas

function taxaCartao(p) { return p <= 1 ? TAXA_AVISTA : (p <= 6 ? TAXA_2_6 : TAXA_7_12); }
function centavos(v) { return Math.round(v * 100) / 100; }
// Gross-up: cliente paga X tal que, após o Asaas descontar a taxa sobre o total, a AG receba PRECO_BASE.
function totalCartao(p) { return centavos(PRECO_BASE / (1 - taxaCartao(p))); }
function digitos(v) { return (v || '').replace(/\D/g, ''); }
function clampParcelas(v) { const n = parseInt(v, 10); return (isNaN(n) || n < 1) ? 1 : Math.min(n, MAX_PARCELAS); }

function baseUrl() {
  return process.env.ASAAS_AMBIENTE === 'producao'
    ? 'https://api.asaas.com/v3'
    : 'https://api-sandbox.asaas.com/v3';
}

async function asaas(path, payload) {
  const r = await fetch(baseUrl() + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', access_token: process.env.ASAAS_API_KEY },
    body: JSON.stringify(payload),
  });
  const body = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error('Asaas ' + r.status + ': ' + JSON.stringify(body));
  return body;
}

function corpoCobranca(customerId, d, successUrl) {
  const base = {
    customer: customerId,
    dueDate: process.env.CHECKOUT_DUE_DATE || '2026-07-31',
    description: 'Inscrição – Algoritmo da Liderança (Turma 2026)',
    externalReference: d.email,
    callback: { successUrl: successUrl, autoRedirect: true },
  };
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
    base.value = PRECO_BASE;
  } else {
    base.billingType = 'PIX';
    base.value = PRECO_BASE; // AG absorve a taxa do PIX
  }
  return base;
}

async function readBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  const raw = await new Promise((resolve) => {
    let d = ''; req.on('data', (c) => (d += c)); req.on('end', () => resolve(d));
  });
  if (!raw) return {};
  const ct = req.headers['content-type'] || '';
  if (ct.indexOf('application/json') >= 0) { try { return JSON.parse(raw); } catch (e) { return {}; } }
  return Object.fromEntries(new URLSearchParams(raw)); // application/x-www-form-urlencoded
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { res.status(405).send('Method Not Allowed'); return; }

  const p = await readBody(req);
  const d = {
    nome: (p.nome || '').trim(),
    email: (p.email || '').trim(),
    whatsapp: digitos(p.whatsapp),
    empresa: (p.empresa || '').trim(),
    cpfCnpj: digitos(p.cpfCnpj),
    metodo: ['cartao', 'boleto', 'pix'].indexOf(p.metodo) >= 0 ? p.metodo : 'pix',
    parcelas: clampParcelas(p.parcelas),
  };

  if (!d.nome || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(d.email) || d.whatsapp.length < 10 || d.cpfCnpj.length < 11) {
    res.status(400).send('Dados inválidos. Volte e confira nome, e-mail, WhatsApp (com DDD) e CPF/CNPJ.');
    return;
  }
  if (!process.env.ASAAS_API_KEY) {
    res.status(500).send('Pagamento temporariamente indisponível (configuração pendente).');
    return;
  }

  const proto = req.headers['x-forwarded-proto'] || 'https';
  const host = req.headers['x-forwarded-host'] || req.headers.host;
  const successUrl = process.env.SUCCESS_URL || (proto + '://' + host + '/apps-script/obrigado.html');

  try {
    const cliente = await asaas('/customers', {
      name: d.nome, email: d.email, mobilePhone: d.whatsapp, cpfCnpj: d.cpfCnpj, externalReference: d.email,
    });
    const cobranca = await asaas('/payments', corpoCobranca(cliente.id, d, successUrl));
    if (!cobranca.invoiceUrl) throw new Error('sem invoiceUrl');
    res.writeHead(303, { Location: cobranca.invoiceUrl }); // redireciona pro checkout hospedado do Asaas
    res.end();
  } catch (err) {
    console.error('[inscrever] falha na cobrança:', err && err.message);
    const fallback = process.env.WHATSAPP_FALLBACK;
    if (fallback) { res.writeHead(303, { Location: fallback }); res.end(); return; }
    res.status(502).send('Não foi possível gerar a cobrança agora. Tente novamente em instantes.');
  }
};
