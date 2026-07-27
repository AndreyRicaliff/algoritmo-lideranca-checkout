// Vercel Serverless Function — cria cliente + cobrança no Asaas e redireciona pro checkout.
// A chave Asaas vive SÓ em env var (nunca no front/repo): definir no painel Vercel.
// Preço, lote e taxas vêm de lib/preco.js — o mesmo módulo que alimenta o front.
//
// Env vars (Settings -> Environment Variables):
//   ASAAS_API_KEY          (obrigatória)  chave $aact_... — use a de SANDBOX para testar
//   ASAAS_AMBIENTE         'producao' | 'sandbox' (default sandbox)
//   ASAAS_ANTECIPACAO_AM   taxa de antecipação ao mês em fração (ex: 0.0199). 0 desliga.
//   SUCCESS_URL            (opcional) pós-pagamento; só funciona com domínio cadastrado no Asaas
//   WHATSAPP_FALLBACK      (opcional) pra onde mandar se a cobrança falhar
//   CHECKOUT_DUE_DATE      (opcional) trava o vencimento numa data; default = hoje + 3 dias

const preco = require('../lib/preco.js');

const DESCRICAO = 'Inscrição – Algoritmo da Liderança (2ª turma · 18 a 20/09/2026)';
const DIAS_VENCIMENTO = 3;

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

function digitos(v) {
  return (v || '').replace(/\D/g, '');
}

function corpoCobranca(customerId, d, base) {
  const corpo = {
    customer: customerId,
    // Vencimento relativo: data fixa nasce vencida assim que a turma vira de mês.
    dueDate: process.env.CHECKOUT_DUE_DATE || preco.vencimentoEm(DIAS_VENCIMENTO),
    description: DESCRICAO,
    externalReference: d.email,
  };
  // O Asaas só aceita callback.successUrl com um site cadastrado na conta (Minha Conta ->
  // Informações). Sem domínio, mandar callback derruba a cobrança inteira.
  if (process.env.SUCCESS_URL) {
    corpo.callback = { successUrl: process.env.SUCCESS_URL, autoRedirect: true };
  }
  if (d.metodo !== 'cartao') {
    corpo.billingType = d.metodo === 'boleto' ? 'BOLETO' : 'PIX';
    corpo.value = base; // à vista sem cartão: a AG absorve a taxa
    return corpo;
  }
  corpo.billingType = 'CREDIT_CARD';
  const total = preco.totalCartao(d.parcelas, base); // MDR + antecipação já repassados
  if (d.parcelas <= 1) {
    corpo.value = total;
  } else {
    corpo.installmentCount = d.parcelas; // o Asaas divide o total nas parcelas
    corpo.totalValue = total;            // cliente paga o total; a AG recebe a base líquida
  }
  return corpo;
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

function lerCampos(p) {
  return {
    nome: (p.nome || '').trim(),
    email: (p.email || '').trim(),
    whatsapp: digitos(p.whatsapp),
    empresa: (p.empresa || '').trim(),
    cpfCnpj: digitos(p.cpfCnpj),
    metodo: ['cartao', 'boleto', 'pix'].indexOf(p.metodo) >= 0 ? p.metodo : 'pix',
    parcelas: preco.clampParcelas(p.parcelas),
    utm: (p.utm || '').trim().slice(0, 200),
    precoVisto: (p.precoVisto == null ? '' : String(p.precoVisto)).trim(),
  };
}

function invalido(d) {
  if (!d.nome) return 'Confira seu nome.';
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(d.email)) return 'E-mail inválido.';
  if (d.whatsapp.length < 10) return 'WhatsApp inválido — inclua o DDD.';
  if (d.cpfCnpj.length !== 11 && d.cpfCnpj.length !== 14) return 'CPF/CNPJ inválido.';
  return null;
}

// O comprador vê o preço na página e o lote pode virar entre o carregamento e o envio.
// Cobrar diferente do que foi exibido é o pior desfecho possível, então o form declara o que
// mostrou. Campo ausente = página anterior a este deploy, que exibia preço fixo sem declarar
// nada: essa é justamente a que mostra o valor errado depois da virada, então pede recarga.
// 'indisponivel' = front atual que não conseguiu carregar a tabela e não exibiu preço nenhum.
function precoDivergente(d, base) {
  if (d.precoVisto === 'indisponivel') return false;
  const visto = parseFloat(d.precoVisto);
  if (!isFinite(visto)) return true;
  const esperado = d.metodo === 'cartao' ? preco.totalCartao(d.parcelas, base) : base;
  return Math.abs(esperado - visto) > 0.01;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { res.status(405).send('Method Not Allowed'); return; }

  const d = lerCampos(await readBody(req));
  const erro = invalido(d);
  if (erro) { res.status(400).send(erro + ' Volte e corrija para continuar.'); return; }
  if (!process.env.ASAAS_API_KEY) {
    res.status(500).send('Pagamento temporariamente indisponível (configuração pendente).');
    return;
  }

  try {
    const lote = preco.loteVigente();
    if (precoDivergente(d, lote.base)) {
      res.status(409).send('O valor da inscrição foi atualizado. Recarregue a página para ver a condição vigente.');
      return;
    }
    const cliente = await asaas('/customers', {
      name: d.nome, email: d.email, mobilePhone: d.whatsapp, cpfCnpj: d.cpfCnpj,
      company: d.empresa || undefined,
      // Origem no próprio painel do Asaas: é onde a inscrição é acompanhada.
      observations: ['origem: ' + (d.utm || 'direto'), 'lote: ' + lote.id].join(' | '),
      externalReference: d.email,
    });
    const cobranca = await asaas('/payments', corpoCobranca(cliente.id, d, lote.base));
    if (!cobranca.invoiceUrl) throw new Error('sem invoiceUrl');
    res.writeHead(303, { Location: cobranca.invoiceUrl }); // checkout hospedado pelo Asaas
    res.end();
  } catch (err) {
    console.error('[inscrever] falha na cobrança:', err && err.message);
    const fallback = process.env.WHATSAPP_FALLBACK;
    if (fallback) { res.writeHead(303, { Location: fallback }); res.end(); return; }
    res.status(502).send('Não foi possível gerar a cobrança. Confira o CPF/CNPJ informado ou chame a AG no WhatsApp.');
  }
};
