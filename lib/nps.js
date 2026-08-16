// Fonte única da pesquisa do evento: seções, perguntas, evento vigente e acesso ao banco.
// O front exibe via /api/nps-perguntas e grava via /api/nps — nada duplicado em página.
//
// A anon key abaixo é PÚBLICA por design (Supabase) e vai pro browser em qualquer app
// que use o projeto. A segurança NÃO está nela: as tabelas nps_* não têm nenhuma policy
// nem grant pro anon — todo acesso passa pelas RPCs (ver supabase/migrations/20260816*).

// 1ª turma (15-17/08/2026). Quando a 2ª turma (18-20/09) acabar, trocar pra '...-t2':
// o site inteiro passa a coletar e mostrar a turma nova sem mexer em mais nada.
const EVENTO = 'alg-lideranca-2026-t1';

const SUPABASE_URL = 'https://hqcbpqkohgmlultnmbyy.supabase.co'; // AG-Converge (infra de eventos)
const SUPABASE_ANON =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhxY2JwcWtvaGdtbHVsdG5tYnl5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgyOTIyMTAsImV4cCI6MjA5Mzg2ODIxMH0.NCAvbQYVmLmcZuofj0B9Tkr7sv-tvz4QcTZLtjdWD-M';

// Pesquisa definitiva (Ricaliff, 2026-08-16). Uma tela por seção no wizard.
//   tipo 'escala'  = 1 a 5 (Muito ruim → Excelente)
//   tipo 'nps'     = 0 a 10, entra no eNPS
//   tipo 'texto'   = aberto; identificação é opcional e só aparece com a chave (como
//                    o comentário) — agregados públicos nunca carregam texto.
const ESCALA_ROTULOS = ['Muito ruim', 'Ruim', 'Regular', 'Bom', 'Excelente'];

const SECOES = [
  {
    id: 'identificacao', titulo: 'Identificação', sub: 'Opcional — pode pular sem responder.',
    perguntas: [
      { id: 'ident_nome', tipo: 'texto', max: 120, texto: 'Nome' },
      { id: 'ident_cargo', tipo: 'texto', max: 120, texto: 'Área / cargo' },
    ],
  },
  {
    id: 'nucleo', titulo: 'O Núcleo · O líder por dentro', sub: 'Como você avalia cada pauta?',
    perguntas: [
      { id: 'p_dna', tipo: 'escala', texto: 'O DNA da sua Liderança' },
      { id: 'p_autocuidado', tipo: 'escala', texto: 'Autocuidado, Energia e Longevidade' },
      { id: 'p_decisao', tipo: 'escala', texto: 'Decisão sob Pressão' },
      { id: 'p_foco', tipo: 'escala', texto: 'Foco no que Gera Resultado' },
    ],
  },
  {
    id: 'conexoes', titulo: 'As Conexões · O líder e o time', sub: 'Como você avalia cada pauta?',
    perguntas: [
      { id: 'p_presenca', tipo: 'escala', texto: 'Presença e Influência' },
      { id: 'p_conversas', tipo: 'escala', texto: 'Conversas Difíceis, Relações Fortes' },
      { id: 'p_feedback', tipo: 'escala', texto: 'Feedback que Desenvolve' },
      { id: 'p_conflito', tipo: 'escala', texto: 'Do Conflito ao Acordo' },
    ],
  },
  {
    id: 'escala_org', titulo: 'A Escala · O líder e a organização', sub: 'Como você avalia cada pauta?',
    perguntas: [
      { id: 'p_time', tipo: 'escala', texto: 'Formando o Time' },
      { id: 'p_cultura', tipo: 'escala', texto: 'Cultura e Clima Organizacional' },
      { id: 'p_visao', tipo: 'escala', texto: 'Visão Estratégica' },
      { id: 'p_vendedor', tipo: 'escala', texto: 'O Líder Vendedor' },
    ],
  },
  {
    id: 'bonus', titulo: 'Bônus · O líder e o futuro', sub: 'Como você avalia a pauta?',
    perguntas: [
      { id: 'p_ia', tipo: 'escala', texto: 'IA para a Gestão' },
    ],
  },
  {
    id: 'materiais', titulo: 'Materiais', sub: null,
    perguntas: [
      { id: 'm_apostila', tipo: 'escala', texto: 'Qualidade da apostila' },
      { id: 'm_clareza', tipo: 'escala', texto: 'Clareza e organização do conteúdo' },
      { id: 'm_utilidade', tipo: 'escala', texto: 'Utilidade para o dia a dia' },
    ],
  },
  {
    id: 'experiencia', titulo: 'Experiência geral', sub: null,
    perguntas: [
      { id: 'e_facilitador', tipo: 'escala', texto: 'Facilitador(es) / condução' },
      { id: 'e_ritmo', tipo: 'escala', texto: 'Ritmo e duração' },
      { id: 'e_logistica', tipo: 'escala', texto: 'Organização e logística' },
      { id: 'e_aplicabilidade', tipo: 'escala', texto: 'Aplicabilidade no seu trabalho' },
    ],
  },
  {
    id: 'nps', titulo: 'Recomendação', sub: '0–6 detrator · 7–8 neutro · 9–10 promotor',
    perguntas: [
      { id: 'nps_geral', tipo: 'nps',
        texto: 'De 0 a 10, o quanto você recomendaria este treinamento a um colega?',
        min: 'Não recomendaria', max: 'Com certeza' },
    ],
  },
  {
    id: 'comentario', titulo: 'Comentário', sub: 'Opcional.',
    perguntas: [
      { id: 'comentario', tipo: 'texto', max: 1000,
        texto: 'O que mais te marcou e o que podemos melhorar?' },
    ],
  },
];

const PERGUNTAS = SECOES.reduce(function (lista, s) {
  return lista.concat(s.perguntas.map(function (q) {
    return Object.assign({ secao: s.id }, q);
  }));
}, []);

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

module.exports = { EVENTO, SECOES, PERGUNTAS, ESCALA_ROTULOS, rpc };
