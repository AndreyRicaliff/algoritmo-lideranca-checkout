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
let nPrincipal = 0;
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
    if (!['escala', 'nps', 'texto', 'opcao'].includes(q.tipo)) {
      erros.push(`pergunta "${q.id}": tipo deve ser escala, nps, texto ou opcao`);
    }
    if (q.tipo === 'opcao') {
      // O valor gravado é o ÍNDICE da opção. Duas opções iguais viram duas barras
      // indistinguíveis no painel, e uma lista curta demais não é escolha.
      if (!Array.isArray(q.opcoes) || q.opcoes.length < 2) {
        erros.push(`pergunta "${q.id}": opcao precisa de pelo menos 2 opcoes`);
      } else if (q.opcoes.length > 50) {
        erros.push(`pergunta "${q.id}": no máximo 50 opções`);
      } else if (new Set(q.opcoes).size !== q.opcoes.length) {
        erros.push(`pergunta "${q.id}": opções repetidas`);
      }
    } else if (q.opcoes) {
      erros.push(`pergunta "${q.id}": só pergunta do tipo opcao pode ter "opcoes"`);
    }
    if (q.tipo === 'nps') nNps++;
    if (q.principal === true) {
      nPrincipal++;
      if (q.tipo !== 'nps') erros.push(`pergunta "${q.id}": só pergunta nps pode ser principal`);
    }
    if (!q.texto) erros.push(`pergunta "${q.id}": sem texto`);
  }
}
if (nNps === 0) erros.push('nenhuma pergunta tipo "nps" — a pesquisa não teria eNPS');
// Mais de um 0-10 é legítimo (nota do módulo E recomendação do treinamento, por exemplo),
// mas só um deles é o eNPS do produto. Sem dizer qual, o painel escolheria pela ordem —
// e a ordem é acidente de diagramação, não decisão de medição.
if (nNps > 1 && nPrincipal !== 1) {
  erros.push(`${nNps} perguntas tipo "nps": marque exatamente uma com "principal": true ` +
    '(é ela que vira o eNPS; hoje ' + nPrincipal + ' marcada(s))');
}

if (erros.length) {
  console.error('roteiro inválido:\n' + erros.map((e) => '  - ' + e).join('\n'));
  process.exit(1);
}

// ---- geração ----
// Escapa todo caractere fora do ASCII como \uXXXX. Feito caractere a caractere de
// proposito: uma classe de regex com escapes unicode ja chegou a virar caractere de
// controle literal neste arquivo -- funciona igual ate alguem normalizar os bytes, e
// ai o escape para de acontecer EM SILENCIO e o acento cru vai pro canal que corrompe.
// Assim o codigo-fonte deste gerador e 100% ASCII e nao tem como se auto-sabotar.
const BARRA = String.fromCharCode(92);   // a barra invertida, sem escrever barra no fonte
const paraAscii = (str) => {
  let out = '';
  for (const ch of String(str)) {
    const code = ch.codePointAt(0);
    out += code > 127 ? BARRA + 'u' + code.toString(16).padStart(4, '0') : ch;
  }
  return out;
};
const temNaoAscii = (str) => {
  for (const ch of String(str)) if (ch.codePointAt(0) > 127) return true;
  return false;
};


const roteiro = { subtitulo: r.subtitulo || null, escalaRotulos: r.escalaRotulos, secoes: r.secoes };
const ascii = paraAscii(JSON.stringify(roteiro));
const txt = (v) => (v === null || v === undefined ? 'null' : "'" + String(v).replace(/'/g, "''") + "'");
const txtAscii = (v) => {
  if (v === null || v === undefined) return 'null';
  // metadados também podem ter acento (título "2ª turma"): entram via JSON escapado e
  // saem com ->>0, o mesmo truque do roteiro.
  const j = paraAscii(JSON.stringify(String(v)));
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

if (temNaoAscii(sql)) {
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
