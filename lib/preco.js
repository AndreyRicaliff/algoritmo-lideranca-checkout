// Fonte única de verdade do preço do checkout: lote vigente, MDR do cartão e antecipação.
// O backend (api/inscrever.js) cobra por aqui e o front exibe por aqui (via api/preco.js).
// Preço duplicado em dois lugares com virada por data = comprador vê um valor e paga outro.

// Lotes por data de virada. `ate` = ÚLTIMO dia com esse preço (inclusive), fuso de Brasília.
const LOTES = [
  { id: 'lote1', ate: '2026-07-31', base: 1280.50, rotulo: 'Condição de lançamento' },
  { id: 'lote2', ate: null, base: 1977.00, rotulo: 'Valor cheio' },
];

const MAX_PARCELAS = 10;

// MDR do Asaas — taxa sobre o total da venda, por faixa de parcelas.
const MDR_AVISTA = 0.0299;
const MDR_2_6 = 0.0349;
const MDR_7_12 = 0.0399;

// Antecipação: receber em D+2 em vez de D+30 por parcela, cobrada em % ao mês sobre o
// valor antecipado. Varia por conta — CONFERIR no extrato do Asaas. 0 desliga o repasse.
const ANTECIPACAO_AM = taxaEnv(process.env.ASAAS_ANTECIPACAO_AM, 0.0199);

// Taxa combinada acima disso é erro de configuração, não preço: aborta em vez de cobrar.
const TETO_TAXA = 0.35;

function taxaEnv(v, padrao) {
  const n = parseFloat(v);
  return isFinite(n) && n >= 0 && n < 1 ? n : padrao;
}

// O runtime do Vercel roda em UTC: sem fixar o fuso, a virada de lote aconteceria às 21h do
// dia anterior em Brasília e as últimas horas do lote sairiam pelo preço novo.
const FMT_DIA = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit',
});

function diaBrasilia(data) {
  return FMT_DIA.format(data || new Date()); // en-CA => YYYY-MM-DD (comparável como string)
}

function vencimentoEm(dias) {
  return diaBrasilia(new Date(Date.now() + dias * 86400000));
}

function loteVigente(hoje) {
  const dia = hoje || diaBrasilia();
  return LOTES.find((l) => !l.ate || dia <= l.ate) || LOTES[LOTES.length - 1];
}

function proximoLote(lote) {
  const i = LOTES.indexOf(lote);
  return i >= 0 && i + 1 < LOTES.length ? LOTES[i + 1] : null;
}

// Dia seguinte ao fim do lote, para o aviso de virada. Meio-dia UTC evita a borda de fuso.
function diaSeguinte(iso) {
  return diaBrasilia(new Date(Date.parse(iso + 'T12:00:00Z') + 86400000));
}

function mdr(parcelas) {
  if (parcelas <= 1) return MDR_AVISTA;
  if (parcelas <= 6) return MDR_2_6;
  return MDR_7_12;
}

// A parcela k cairia em D+30k; antecipada para D+2 ela adianta (30k-2)/30 meses.
// Somando as N parcelas e dividindo pelo total, o fator médio é (N+1)/2 - 1/15 meses.
function mesesAntecipados(parcelas) {
  return (parcelas + 1) / 2 - 1 / 15;
}

function taxaTotal(parcelas) {
  return mdr(parcelas) + ANTECIPACAO_AM * mesesAntecipados(parcelas);
}

function centavos(v) {
  return Math.round(v * 100) / 100;
}

// Gross-up: o cliente paga X tal que, descontadas as taxas sobre o total, a AG receba a base.
function totalCartao(parcelas, base) {
  const taxa = taxaTotal(parcelas);
  if (!isFinite(taxa) || taxa < 0 || taxa >= TETO_TAXA) {
    throw new Error('taxa combinada fora da faixa (' + taxa + ') — confira ASAAS_ANTECIPACAO_AM');
  }
  return centavos(base / (1 - taxa));
}

function clampParcelas(v) {
  const n = parseInt(v, 10);
  return !isFinite(n) || n < 1 ? 1 : Math.min(n, MAX_PARCELAS);
}

// Tabela completa consumida pelo front — o que a página exibe vem daqui, não de constante local.
function tabela(hoje) {
  const lote = loteVigente(hoje);
  const proximo = proximoLote(lote);
  const parcelas = [];
  for (let p = 1; p <= MAX_PARCELAS; p++) {
    const total = totalCartao(p, lote.base);
    parcelas.push({ n: p, total: total, parcela: centavos(total / p), taxa: taxaTotal(p) });
  }
  return {
    lote: lote.id,
    rotulo: lote.rotulo,
    base: lote.base,
    ate: lote.ate,
    proximaBase: proximo ? proximo.base : null,
    proximoInicio: proximo && lote.ate ? diaSeguinte(lote.ate) : null,
    maxParcelas: MAX_PARCELAS,
    antecipacaoAm: ANTECIPACAO_AM,
    parcelas: parcelas,
  };
}

module.exports = {
  LOTES, MAX_PARCELAS, ANTECIPACAO_AM,
  diaBrasilia, vencimentoEm, loteVigente, proximoLote, diaSeguinte,
  mdr, mesesAntecipados, taxaTotal, centavos, totalCartao, clampParcelas, tabela,
};
