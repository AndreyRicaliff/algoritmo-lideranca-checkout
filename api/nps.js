// Recebe UMA resposta e grava via RPC nps_gravar (upsert por pesquisa+sessão+pergunta).
// O wizard envia a cada avanço — quem abandona no meio ainda conta nas estatísticas.
//
// Quem valida SE a pergunta existe é o banco, contra o roteiro daquela pesquisa
// (migration 20260918). Aqui fica a faixa numérica e o formato: o par (id, tipo) já foi
// conferido lá, então confiar no `tipo` declarado pra escolher a faixa não abre brecha —
// mentir o tipo faz a RPC recusar com NPS05 antes de gravar qualquer coisa.

const nps = require('../lib/nps.js');

// Faixa conferida aqui. Para 'opcao' o limite real é quantas opções aquela pergunta tem,
// coisa que só o roteiro sabe — então aqui vai só um teto de sanidade e quem recusa índice
// inexistente é a RPC (NPS08), contra o roteiro da própria pesquisa.
const TIPOS = { nps: [0, 10], escala: [1, 5], opcao: [0, 49] };

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { res.status(405).json({ error: 'method not allowed' }); return; }
  const p = await nps.readBody(req);

  // Honeypot: campo que humano não vê. Preenchido = bot; finge sucesso pra não calibrar.
  if (p.site) { res.status(204).end(); return; }

  const sessao = String(p.sessao || '');
  const evento = String(p.evento || '').trim().toLowerCase();
  const perguntaId = String(p.pergunta_id || '');
  const tipo = String(p.tipo || '');

  if (!nps.UUID_RE.test(sessao) || !nps.SLUG_RE.test(evento) ||
      !/^[a-z0-9_]{1,40}$/.test(perguntaId) ||
      (tipo !== 'texto' && !TIPOS[tipo])) {
    res.status(400).json({ error: 'resposta inválida' });
    return;
  }

  const args = {
    p_evento: evento, p_sessao: sessao.toLowerCase(),
    p_pergunta_id: perguntaId, p_tipo: tipo, p_valor: null, p_texto: null,
  };
  if (tipo === 'texto') {
    const texto = String(p.texto || '').trim().slice(0, 1000);
    if (!texto) { res.status(204).end(); return; } // texto vazio não é resposta
    args.p_texto = texto;
  } else {
    const [min, max] = TIPOS[tipo];
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
    if (err.code === 'NPS04' || /indispon/.test(msg)) {
      res.status(409).json({ error: 'A pesquisa foi encerrada.' });
      return;
    }
    if (err.code === 'NPS08' || /opcao inexistente/.test(msg)) {
      res.status(400).json({ error: 'Opção não faz parte desta pergunta.' });
      return;
    }
    if (err.code === 'NPS05' || /pergunta inval/.test(msg)) {
      // pergunta que não existe no roteiro desta pesquisa — front desatualizado ou chamada forjada
      res.status(400).json({ error: 'Pergunta não faz parte desta pesquisa.' });
      return;
    }
    console.error('[nps] falha ao gravar:', msg);
    res.status(502).json({ error: 'Não foi possível salvar agora — tente de novo.' });
  }
};
