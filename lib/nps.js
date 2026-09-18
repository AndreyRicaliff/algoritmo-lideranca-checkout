// Acesso ao banco da pesquisa e resolucao de QUAL pesquisa esta em jogo.
//
// Antes daqui morava tambem o questionario inteiro (const EVENTO + SECOES hardcoded).
// Saiu: o roteiro de cada pesquisa vive no banco (nps_config.roteiro), porque a 2a turma
// tem UMA PESQUISA POR DIA e criar pesquisa nao pode depender de deploy. Ver
// supabase/migrations/20260918_nps_multi_pesquisa.sql.
//
// A anon key abaixo é PÚBLICA por design (Supabase) e vai pro browser em qualquer app
// que use o projeto. A segurança NÃO está nela: as tabelas nps_* não têm nenhuma policy
// nem grant pro anon — todo acesso passa pelas RPCs.

const SUPABASE_URL = 'https://hqcbpqkohgmlultnmbyy.supabase.co'; // AG-Converge (infra de eventos)
const SUPABASE_ANON =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhxY2JwcWtvaGdtbHVsdG5tYnl5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgyOTIyMTAsImV4cCI6MjA5Mzg2ODIxMH0.NCAvbQYVmLmcZuofj0B9Tkr7sv-tvz4QcTZLtjdWD-M';

const SLUG_RE = /^[a-z0-9][a-z0-9-]{1,59}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Slug vindo da URL: só confere FORMATO. Se existe e se está aberta, quem decide é o
// banco — o serverless nunca mantém uma lista paralela de pesquisas pra desencontrar.
// Vazio vira null: aí o banco resolve a pesquisa do dia.
function eventoDaQuery(req) {
  const q = (req.query && req.query.e) || '';
  const bruto = String(Array.isArray(q) ? q[0] : q).trim().toLowerCase();
  return bruto && SLUG_RE.test(bruto) ? bruto : null;
}

function tokenDoCookie(req) {
  const m = /(?:^|;\s*)nps_admin=([^;]+)/.exec(req.headers.cookie || '');
  return m && UUID_RE.test(m[1]) ? m[1] : null;
}

async function rpc(nome, args) {
  const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/' + nome, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_ANON,
      Authorization: 'Bearer ' + SUPABASE_ANON,
    },
    body: JSON.stringify(args),
  });
  const body = await r.json().catch(() => null);
  if (!r.ok) {
    const msg = body && (body.message || body.hint) ? body.message || body.hint : 'rpc ' + r.status;
    const err = new Error(msg);
    // O SQLSTATE (NPS01..NPS06) é o que decide o roteamento lá em cima. A mensagem serve
    // pra log: ela atravessa canais que já provaram corromper acento, o código não.
    err.code = body && body.code ? body.code : null;
    throw err;
  }
  return body;
}

async function readBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  const raw = await new Promise((resolve) => {
    let d = '';
    req.on('data', (c) => (d += c));
    req.on('end', () => resolve(d));
  });
  try { return JSON.parse(raw || '{}'); } catch (e) { return {}; }
}

module.exports = { SUPABASE_URL, rpc, readBody, eventoDaQuery, tokenDoCookie, SLUG_RE, UUID_RE };
