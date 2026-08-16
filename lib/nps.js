// Fonte única da pesquisa NPS do evento: perguntas, evento vigente e acesso ao banco.
// O front exibe via /api/nps-perguntas e grava via /api/nps — nada duplicado em página.
//
// A anon key abaixo é PÚBLICA por design (Supabase) e vai pro browser em qualquer app
// que use o projeto. A segurança NÃO está nela: as tabelas nps_* não têm nenhuma policy
// nem grant pro anon — todo acesso passa pelas RPCs (ver supabase/migrations/20260816...).

// 1ª turma (15-17/08/2026). Quando a 2ª turma (18-20/09) acabar, trocar pra '...-t2':
// o site inteiro passa a coletar e mostrar a turma nova sem mexer em mais nada.
const EVENTO = 'alg-lideranca-2026-t1';

const SUPABASE_URL = 'https://hqcbpqkohgmlultnmbyy.supabase.co'; // AG-Converge (infra de eventos)
const SUPABASE_ANON =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhxY2JwcWtvaGdtbHVsdG5tYnl5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgyOTIyMTAsImV4cCI6MjA5Mzg2ODIxMH0.NCAvbQYVmLmcZuofj0B9Tkr7sv-tvz4QcTZLtjdWD-M';

// >>> PERGUNTAS PLACEHOLDER — Ricaliff manda as definitivas. Trocar SÓ aqui. <<<
//   tipo 'nps'    = 0 a 10, entra no cálculo do eNPS (pergunta de recomendação)
//   tipo 'escala' = 0 a 10, avaliada por média/distribuição (não entra no eNPS)
//   tipo 'texto'  = aberta, opcional
const PERGUNTAS = [
  {
    id: 'nps_geral', tipo: 'nps',
    texto: 'De 0 a 10: o quanto você recomendaria o Algoritmo da Liderança a outro gestor?',
    min: 'Não recomendaria', max: 'Com certeza',
  },
  {
    id: 'conteudo', tipo: 'escala',
    texto: '[PLACEHOLDER] Como você avalia o conteúdo dos 3 dias?',
    min: 'Fraco', max: 'Excelente',
  },
  {
    id: 'instrutores', tipo: 'escala',
    texto: '[PLACEHOLDER] Como você avalia os instrutores?',
    min: 'Fraco', max: 'Excelente',
  },
  {
    id: 'comentario', tipo: 'texto',
    texto: 'Quer deixar um comentário ou sugestão? (opcional)',
  },
];

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
    throw new Error(msg);
  }
  return body;
}

module.exports = { EVENTO, PERGUNTAS, rpc };
