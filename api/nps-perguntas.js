// Roteiro da pesquisa — o wizard carrega daqui e nunca duplica a lista em página.
// ?e=<slug> escolhe a pesquisa; sem parâmetro o banco resolve a do dia (America/Sao_Paulo).

const nps = require('../lib/nps.js');

module.exports = async function handler(req, res) {
  try {
    const d = await nps.rpc('nps_roteiro', { p_evento: nps.eventoDaQuery(req) });
    if (!d) {
      // nenhuma pesquisa aberta com roteiro: quem leu o QR merece saber disso, não um 500
      res.setHeader('Cache-Control', 'no-store');
      res.status(404).json({ error: 'Nenhuma pesquisa disponível no momento.' });
      return;
    }
    // Cache curto e por URL: o roteiro muda quando o dono publica a pesquisa do dia, e
    // 60s de atraso é aceitável; o Vary garante que ?e= diferente não reusa a mesma cópia.
    res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=300');
    res.status(200).json({
      evento: d.evento,
      titulo: d.titulo,
      periodo: d.periodo,
      aberto: d.aberto,
      subtitulo: (d.roteiro && d.roteiro.subtitulo) || null,
      escalaRotulos: (d.roteiro && d.roteiro.escalaRotulos) || [],
      secoes: (d.roteiro && d.roteiro.secoes) || [],
    });
  } catch (err) {
    console.error('[nps-perguntas] falha:', String(err && err.message));
    res.setHeader('Cache-Control', 'no-store');
    res.status(502).json({ error: 'Não foi possível carregar a pesquisa agora.' });
  }
};
