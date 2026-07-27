// GET /api/preco — tabela de preços vigente (lote + parcelas com taxa já embutida).
// O front consome daqui em vez de replicar a regra: é o mesmo módulo que a cobrança usa.
// Dado público (nenhum segredo), por isso CORS liberado — a leadpage roda em outro domínio.

const preco = require('../lib/preco.js');

module.exports = function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.method === 'OPTIONS') { res.status(204).end(); return; }
  if (req.method !== 'GET') { res.status(405).json({ erro: 'Method Not Allowed' }); return; }

  try {
    // Sem cache: a virada de lote é por data e não pode ficar presa numa borda da CDN.
    res.setHeader('Cache-Control', 'no-store');
    res.status(200).json(preco.tabela());
  } catch (err) {
    console.error('[preco] tabela inválida:', err && err.message);
    res.status(500).json({ erro: 'preco_indisponivel' });
  }
};
