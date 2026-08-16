// Estatísticas agregadas da pesquisa pro painel interno (/resultados).
// O banco devolve só o histograma (pergunta × valor × n) — o eNPS, médias e faixas são
// calculados AQUI, num lugar só, e o front apenas renderiza.
//
// Método eNPS: promotores = notas 9-10, neutros = 7-8, detratores = 0-6.
// eNPS = %promotores − %detratores (inteiro, -100 a +100), sobre a pergunta tipo 'nps'.
// Demais perguntas são escala 1-5, lidas por média e distribuição.

const nps = require('../lib/nps.js');

let cache = { em: 0, dados: null };

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
    // esqueleto das seções pro painel renderizar agrupado na ordem da pesquisa
    secoes: nps.SECOES.map((s) => ({
      id: s.id, titulo: s.titulo,
      perguntas: s.perguntas.map((q) => q.id),
    })),
    perguntas,
  };
}

module.exports = async function handler(req, res) {
  const chave = String((req.query && req.query.chave) || '').slice(0, 64);
  try {
    let dados = cache.dados;
    if (!dados || Date.now() - cache.em > 15000) {
      dados = resumo(await nps.rpc('nps_stats', { p_evento: nps.EVENTO }));
      cache = { em: Date.now(), dados };
    }
    const corpo = Object.assign({}, dados);
    if (chave) {
      // Chave errada devolve conjunto vazio (sem oráculo). Vem TUDO que é texto —
      // identificação e comentário — com a sessão pra ligar as pontas no painel.
      corpo.textos = await nps.rpc('nps_comentarios', { p_evento: nps.EVENTO, p_chave: chave });
      res.setHeader('Cache-Control', 'no-store');
    } else {
      res.setHeader('Cache-Control', 's-maxage=15, stale-while-revalidate=60');
    }
    res.status(200).json(corpo);
  } catch (err) {
    console.error('[nps-stats] falha:', err && err.message);
    res.status(502).json({ error: 'Não foi possível carregar as estatísticas agora.' });
  }
};
