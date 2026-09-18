// Catálogo de pesquisas do painel — a tela inicial de /resultados.
// Atrás do mesmo login das estatísticas: a lista já diz quantas respostas cada pesquisa
// tem, e isso é informação interna.

const nps = require('../lib/nps.js');

module.exports = async function handler(req, res) {
  const token = nps.tokenDoCookie(req);
  res.setHeader('Cache-Control', 'no-store');
  if (!token) { res.status(401).json({ error: 'login' }); return; }

  try {
    const linhas = await nps.rpc('nps_catalogo', { p_token: token });
    res.status(200).json({
      eventos: (linhas || []).map((l) => ({
        evento: l.evento,
        titulo: l.titulo || l.evento,
        periodo: l.periodo,
        dia: l.dia,
        aberto: l.aberto,
        rascunho: l.rascunho,       // sem roteiro: existe no catálogo mas não coleta nada
        sessoes: Number(l.sessoes),
        respostas: Number(l.respostas),
        ultima: l.ultima,
      })),
    });
  } catch (err) {
    const msg = String(err && err.message);
    if (err.code === 'NPS01' || /autorizado/.test(msg)) {
      res.status(401).json({ error: 'login' });
      return;
    }
    console.error('[nps-eventos] falha:', msg);
    res.status(502).json({ error: 'Não foi possível carregar as pesquisas agora.' });
  }
};
