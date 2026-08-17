// Estatísticas da pesquisa pro painel interno (/resultados) — atrás de login.
// A sessão (cookie HttpOnly) é validada no banco a cada chamada; sem ela nem os
// agregados saem. O eNPS, médias e faixas são calculados AQUI, num lugar só.
//
// Método eNPS: promotores = 9-10, neutros = 7-8, detratores = 0-6.
// eNPS = %promotores − %detratores. Demais perguntas: escala 1-5, média e distribuição.

const nps = require('../lib/nps.js');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function tokenDoCookie(req) {
  const m = /(?:^|;\s*)nps_admin=([^;]+)/.exec(req.headers.cookie || '');
  return m && UUID_RE.test(m[1]) ? m[1] : null;
}

function resumo(rows) {
  const perguntas = {};
  let sessoes = 0;
  let comentariosN = 0;
  for (const r of rows) {
    if (r.pergunta_id === '_sessoes') { sessoes = Number(r.n); continue; }
    if (r.pergunta_id === '_comentarios') { comentariosN = Number(r.n); continue; }
    const q = perguntas[r.pergunta_id] ||
      (perguntas[r.pergunta_id] = { tipo: r.tipo, n: 0, soma: 0, dist: {} });
    const valor = Number(r.valor);
    const n = Number(r.n);
    q.dist[valor] = (q.dist[valor] || 0) + n;
    q.n += n;
    q.soma += valor * n;
  }
  for (const id of Object.keys(perguntas)) {
    const q = perguntas[id];
    q.media = q.n ? Math.round((q.soma / q.n) * 100) / 100 : null;
    delete q.soma;
    if (q.tipo === 'nps') {
      let det = 0, neu = 0, pro = 0;
      for (let v = 0; v <= 10; v++) {
        const n = q.dist[v] || 0;
        if (v <= 6) det += n; else if (v <= 8) neu += n; else pro += n;
      }
      q.detratores = det; q.neutros = neu; q.promotores = pro;
      q.enps = q.n ? Math.round(((pro - det) / q.n) * 100) : null;
    }
    const meta = nps.PERGUNTAS.find((p) => p.id === id);
    q.texto = meta ? meta.texto : id;
  }
  const geral = perguntas.nps_geral;
  return {
    evento: nps.EVENTO,
    sessoes,
    comentariosN,
    enps: geral && geral.enps !== undefined ? geral.enps : null,
    secoes: nps.SECOES.map((s) => ({
      id: s.id, titulo: s.titulo,
      perguntas: s.perguntas.map((q) => q.id),
    })),
    perguntas,
  };
}

module.exports = async function handler(req, res) {
  const token = tokenDoCookie(req);
  res.setHeader('Cache-Control', 'no-store'); // painel autenticado: nada em cache compartilhado
  if (!token) { res.status(401).json({ error: 'login' }); return; }
  try {
    const [rows, textos] = await Promise.all([
      nps.rpc('nps_stats', { p_evento: nps.EVENTO, p_token: token }),
      nps.rpc('nps_textos', { p_evento: nps.EVENTO, p_token: token }),
    ]);
    const corpo = resumo(rows);
    corpo.textos = textos;
    res.status(200).json(corpo);
  } catch (err) {
    const msg = String(err && err.message);
    if (err.code === 'NPS01' || /autorizado/.test(msg)) {
      res.status(401).json({ error: 'login' }); // sessão inválida/expirada -> volta pro login
      return;
    }
    console.error('[nps-stats] falha:', msg);
    res.status(502).json({ error: 'Não foi possível carregar as estatísticas agora.' });
  }
};
