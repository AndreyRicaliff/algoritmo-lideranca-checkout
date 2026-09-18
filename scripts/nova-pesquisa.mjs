// Transforma um roteiro (roteiros/<slug>.json) numa migration que cria/atualiza a pesquisa
// no banco. Uso:  node scripts/nova-pesquisa.mjs roteiros/alg-lideranca-2026-t2-d1.json
//
// Por que passar por migration em vez de escrever direto no banco: a pesquisa que a turma
// respondeu fica versionada junto com o resto: dá pra ver depois exatamente que perguntas
// estavam no ar naquele dia.
//
// O SQL sai 100% ASCII de proposito -- o canal de aplicacao corrompe byte nao-ASCII no envio
// (ver supabase/migrations/20260817b). Todo acento viaja como escape \uXXXX dentro do JSON e
// o jsonb do Postgres decodifica de volta.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { basename, join } from 'node:path';

const arquivo = process.argv[2];
if (!arquivo) {
  console.error('uso: node scripts/nova-pesquisa.mjs roteiros/<arquivo>.json');
  process.exit(1);
}

const r = JSON.parse(readFileSync(arquivo, 'utf8'));
const erros = [];

// ---- validação: falhar aqui é muito mais barato que descobrir na sala ----
if (!/^[a-z0-9][a-z0-9-]{1,59}$/.test(r.evento || '')) {
  erros.push('evento: slug inválido (minúsculas, números e hífen, 2-60 chars)');
}
if (!r.titulo) erros.push('titulo: obrigatório');
if (r.dia && !/^\d{4}-\d{2}-\d{2}$/.test(r.dia)) erros.push('dia: use AAAA-MM-DD');
if (!Array.isArray(r.escalaRotulos) || r.escalaRotulos.length !== 5) {
  erros.push('escalaRotulos: precisa de exatamente 5 rótulos');
}
if (!Array.isArray(r.secoes) || !r.secoes.length) erros.push('secoes: vazio');

const ids = new Map();
let nNps = 0;
let nPerguntas = 0;
for (const s of r.secoes || []) {
  if (!s.id || !s.titulo) erros.push(`seção "${s.id || '?'}": precisa de id e titulo`);
  if (!Array.isArray(s.perguntas) || !s.perguntas.length) {
    erros.push(`seção "${s.id}": sem perguntas`);
    continue;
  }
  for (const q of s.perguntas) {
    nPerguntas++;
    if (!/^[a-z0-9_]{1,40}$/.test(q.id || '')) {
      erros.push(`pergunta "${q.id || '?'}": id inválido ([a-z0-9_], até 40)`);
    } else if (ids.has(q.id)) {
      erros.push(`pergunta "${q.id}": id repetido (também em "${ids.get(q.id)}")`);
    } else {
      ids.set(q.id, s.id);
    }
    if (!['escala', 'nps', 'texto'].includes(q.tipo)) {
      erros.push(`pergunta "${q.id}": tipo deve ser escala, nps ou texto`);
    }
    if (q.tipo === 'nps') nNps++;
    if (!q.texto) erros.push(`pergunta "${q.id}": sem texto`);
  }
}
if (nNps === 0) erros.push('nenhuma pergunta tipo "nps" — a pesquisa não teria eNPS');
if (nNps > 1) erros.push(`${nNps} perguntas tipo "nps" — o painel só usa a primeira`);

if (erros.length) {
  console.error('roteiro inválido:\n' + erros.map((e) => '  - ' + e).join('\n'));
  process.exit(1);
}

// ---- geração ----
const roteiro = { escalaRotulos: r.escalaRotulos, secoes: r.secoes };
const ascii = JSON.stringify(roteiro).replace(
  /[-￿]/g,
  (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0')
);
const txt = (v) => (v === null || v === undefined ? 'null' : "'" + String(v).replace(/'/g, "''") + "'");
const txtAscii = (v) => {
  if (v === null || v === undefined) return 'null';
  // metadados também podem ter acento (título "2ª turma"): entram via JSON escapado e
  // saem com ->>0, o mesmo truque do roteiro.
  const j = JSON.stringify(String(v)).replace(/[-￿]/g, (c) =>
    '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));
  return "(" + txt(j) + "::jsonb ->> 0)";
};

const hoje = new Date().toISOString().slice(0, 10).replace(/-/g, '');
const nome = `${hoje}_pesquisa_${r.evento.replace(/-/g, '_')}.sql`;
const destino = join('supabase', 'migrations', nome);

const sql = `-- Pesquisa: ${r.evento}
-- Gerada por scripts/nova-pesquisa.mjs a partir de ${basename(arquivo)}.
-- ARQUIVO 100% ASCII: acento viaja como escape \\uXXXX e o jsonb decodifica (ver 20260817b).
--
-- ${nPerguntas} perguntas em ${r.secoes.length} secoes.
-- Reaplicar este arquivo ATUALIZA a pesquisa (upsert) -- as respostas ja gravadas nao
-- sao tocadas. Mudar o texto de uma pergunta sem mudar o id reescreve o rotulo tambem
-- no historico do painel, que passa a exibir o texto novo para respostas antigas.

begin;

insert into public.nps_config (evento, titulo, periodo, dia, aberto, roteiro)
values (
  ${txt(r.evento)},
  ${txtAscii(r.titulo)},
  ${txtAscii(r.periodo)},
  ${r.dia ? `date '${r.dia}'` : 'null'},
  ${r.aberto === false ? 'false' : 'true'},
  ${txt(ascii)}::jsonb
)
on conflict (evento) do update set
  titulo  = excluded.titulo,
  periodo = excluded.periodo,
  dia     = excluded.dia,
  aberto  = excluded.aberto,
  roteiro = excluded.roteiro;

commit;
`;

if (/[^\x00-\x7F]/.test(sql)) {
  console.error('BUG: a migration gerada tem byte nao-ASCII — nao aplique.');
  process.exit(1);
}

mkdirSync(join('supabase', 'migrations'), { recursive: true });
writeFileSync(destino, sql, 'utf8');

console.log(`ok: ${r.evento} — ${nPerguntas} perguntas em ${r.secoes.length} seções`);
console.log(`migration: ${destino}`);
console.log('');
console.log('aplicar: cole o arquivo no SQL Editor do Supabase (projeto AG-Converge) e execute,');
console.log('         ou peça ao Claude pra aplicar.');
console.log('');
console.log(`depois:  cartaz em /qr?e=${r.evento}   ·   painel em /resultados`);
