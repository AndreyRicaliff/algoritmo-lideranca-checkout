// Login do painel /resultados. Credencial mora no banco (bcrypt em nps_config) e a
// validação acontece na RPC nps_login — aqui só transporte: acertou, o token de sessão
// (30 dias) vira cookie HttpOnly e nenhum JS da página consegue lê-lo.

const nps = require('../lib/nps.js');

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
  const usuario = String(p.usuario || '').trim().slice(0, 120);
  const senha = String(p.senha || '').slice(0, 120);
  if (!usuario || !senha) { res.status(400).json({ error: 'Informe usuário e senha.' }); return; }

  try {
    const token = await nps.rpc('nps_login', {
      p_evento: nps.EVENTO, p_usuario: usuario, p_senha: senha,
    });
    if (!token) { res.status(401).json({ error: 'Usuário ou senha incorretos.' }); return; }
    res.setHeader('Set-Cookie',
      'nps_admin=' + token + '; Path=/; Max-Age=' + 30 * 86400 +
      '; HttpOnly; Secure; SameSite=Lax');
    res.status(200).json({ ok: true });
  } catch (err) {
    const msg = String(err && err.message);
    if (msg.indexOf('muitas tentativas') >= 0) {
      res.status(429).json({ error: 'Muitas tentativas — aguarde 15 minutos.' });
      return;
    }
    if (msg.indexOf('não configurado') >= 0) {
      res.status(503).json({ error: 'Login ainda não configurado no banco.' });
      return;
    }
    console.error('[login] falha:', msg);
    res.status(502).json({ error: 'Não foi possível entrar agora — tente de novo.' });
  }
};
