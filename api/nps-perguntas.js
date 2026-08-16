// Estrutura da pesquisa — o front carrega daqui pra nunca duplicar a lista em página.

const nps = require('../lib/nps.js');

module.exports = function handler(req, res) {
  res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=300');
  res.status(200).json({
    evento: nps.EVENTO,
    escalaRotulos: nps.ESCALA_ROTULOS,
    secoes: nps.SECOES,
  });
};
