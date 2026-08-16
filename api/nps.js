// Recebe UMA resposta da pesquisa e grava via RPC nps_gravar (upsert por sessão+pergunta).
// O wizard envia a cada avanço — quem abandona no meio ainda conta nas estatísticas.
// Validação toda aqui no boundary: o front não é confiável e o tipo vem da fonte única,
// nunca do cliente.

const nps = require('../lib/nps.js');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function readBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  const raw = await new Promise((resolve) => {
    let d = '';
    req.on('data', (c) => (d += c));
    req.on('end', () => resolve(d));
  });
  try { return JSON.parse(raw || '{}'); } catch (e) { return {}; }
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { res.status(405).json({ error: 'method not allowed' }); return; }
  const p = await readBody(req);

  // Honeypot: campo que humano não vê. Preenchido = bot; finge sucesso pra não calibrar.
  if (p.site) { res.status(204).end(); return; }

  const sessao = String(p.sessao || '');
  const pergunta = nps.PERGUNTAS.find((q) => q.id === p.pergunta_id);
  if (!UUID_RE.test(sessao) || !pergunta) {
    res.status(400).json({ error: 'resposta inválida' });
    return;
  }

  const args = {
    p_evento: nps.EVENTO, p_sessao: sessao.toLowerCase(),
    p_pergunta_id: pergunta.id, p_tipo: pergunta.tipo, p_valor: null, p_texto: null,
  };
  if (pergunta.tipo === 'texto') {
    const texto = String(p.texto || '').trim().slice(0, pergunta.max || 1000);
    if (!texto) { res.status(204).end(); return; } // texto vazio não é resposta
    args.p_texto = texto;
  } else {
    // faixa por tipo: escala do evento é 1-5, recomendação (eNPS) é 0-10
    const min = pergunta.tipo === 'nps' ? 0 : 1;
    const max = pergunta.tipo === 'nps' ? 10 : 5;
    const valor = Number(p.valor);
    if (!Number.isInteger(valor) || valor < min || valor > max) {
      res.status(400).json({ error: 'valor fora da escala ' + min + '-' + max });
      return;
    }
    args.p_valor = valor;
  }

  try {
    await nps.rpc('nps_gravar', args);
    res.status(200).json({ ok: true });
  } catch (err) {
    const msg = String(err && err.message);
    if (msg.indexOf('indisponível') >= 0) {
      res.status(409).json({ error: 'A pesquisa foi encerrada.' });
      return;
    }
    console.error('[nps] falha ao gravar:', msg);
    res.status(502).json({ error: 'Não foi possível salvar agora — tente de novo.' });
  }
};
