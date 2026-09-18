// Estatísticas de UMA pesquisa pro painel interno (/resultados) — atrás de login.
// A sessão (cookie HttpOnly) é validada no banco a cada chamada; sem ela nem os
// agregados saem. O eNPS, médias e faixas são calculados AQUI, num lugar só.
//
// Método eNPS: promotores = 9-10, neutros = 7-8, detratores = 0-6.
// eNPS = %promotores − %detratores. Demais perguntas: escala 1-5, média e distribuição.
//
// Os rótulos (texto da pergunta, títulos de seção) vêm do roteiro da própria pesquisa,
// não de uma constante: cada dia da turma tem pautas diferentes, e o painel de uma
// pesquisa antiga precisa continuar mostrando os textos que ELA usou.

const nps = require('../lib/nps.js');

function resumo(rows, roteiro) {
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

  const secoes = (roteiro && roteiro.secoes) || [];
  const meta = {};
  for (const s of secoes) for (const q of s.perguntas) meta[q.id] = q.texto;

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
    q.texto = meta[id] || id;
  }

  // eNPS da pesquisa = o da primeira pergunta tipo 'nps' do roteiro. Não fixa mais o id
  // 'nps_geral': cada dia pode nomear a sua como quiser.
  const idNps = Object.keys(perguntas).find((id) => perguntas[id].tipo === 'nps');
  const geral = idNps ? perguntas[idNps] : null;

  return {
    sessoes,
    comentariosN,
    idNps: idNps || null,
    enps: geral && geral.enps !== undefined ? geral.enps : null,
    secoes: secoes.map((s) => ({
      id: s.id, titulo: s.titulo,
      perguntas: s.perguntas.map((q) => q.id),
    })),
    perguntas,
  };
}

module.exports = async function handler(req, res) {
  const token = nps.tokenDoCookie(req);
  res.setHeader('Cache-Control', 'no-store'); // painel autenticado: nada em cache compartilhado
  if (!token) { res.status(401).json({ error: 'login' }); return; }

  const evento = nps.eventoDaQuery(req);
  if (!evento) { res.status(400).json({ error: 'Pesquisa não informada.' }); return; }

  try {
    const [rows, textos, cfg] = await Promise.all([
      nps.rpc('nps_stats', { p_evento: evento, p_token: token }),
      nps.rpc('nps_textos', { p_evento: evento, p_token: token }),
      nps.rpc('nps_roteiro', { p_evento: evento }),
    ]);
    if (!cfg) { res.status(404).json({ error: 'Pesquisa não encontrada.' }); return; }
    const corpo = resumo(rows, cfg.roteiro);
    corpo.evento = cfg.evento;
    corpo.titulo = cfg.titulo;
    corpo.periodo = cfg.periodo;
    corpo.aberto = cfg.aberto;
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
