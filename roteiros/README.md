# Roteiros das pesquisas

Cada arquivo `.json` aqui é **uma pesquisa**: as perguntas, o título e o dia que ela cobre.
O site não lê estes arquivos em runtime — eles são a fonte versionada, e `scripts/nova-pesquisa.mjs`
os transforma numa migration que carrega a pesquisa no banco.

## Criar uma pesquisa

```bash
node scripts/nova-pesquisa.mjs roteiros/alg-lideranca-2026-t2-d1.json
```

O script valida o roteiro, gera `supabase/migrations/<data>_pesquisa_<slug>.sql` e mostra o que
fazer com ela. A migration sai **100% ASCII**, com todo acento em escape `\uXXXX` — é isso que
permite aplicar pelo canal do Supabase sem transformar "Liderança" em "Lideran�a"
(a história completa está em `supabase/migrations/20260817b_nps_errcodes_ascii.sql`).

Aplicar: pelo SQL Editor do Supabase (cole o arquivo e execute) ou pedindo ao Claude.
Depois, o cartaz sai pronto em `/qr?e=<slug>` e o painel lista a pesquisa em `/resultados`.

## Campos

| Campo | O que é |
|---|---|
| `evento` | slug único, minúsculo, só letras/números/hífen. É o que vai na URL do QR |
| `titulo` | nome exibido no painel e no cartaz (ex.: `2ª turma — Dia 1`) |
| `periodo` | texto livre só para exibição (ex.: `18/09/2026`) |
| `dia` | `AAAA-MM-DD`. É como `/pesquisa` sem parâmetro descobre a pesquisa de hoje |
| `aberto` | `true` coleta; `false` congela (o painel continua mostrando os resultados) |
| `escalaRotulos` | os 5 rótulos da escala 1–5, do pior ao melhor |
| `secoes` | uma tela por seção no wizard, na ordem em que aparecem |

### Tipos de pergunta

- **`escala`** — 1 a 5, entra nas médias e no gráfico de distribuição.
- **`nps`** — 0 a 10, é a que vira o eNPS. Use **uma por pesquisa**; o painel pega a primeira.
- **`texto`** — campo aberto. `max` limita os caracteres.

O `id` de cada pergunta é `[a-z0-9_]`, até 40 caracteres, **único dentro da pesquisa**. Ele é a
chave no banco: manter o mesmo `id` entre dias diferentes é o que permite comparar a mesma pauta
ao longo da turma; mudar o texto sem mudar o `id` reescreve o rótulo histórico no painel.

### Duas convenções que o sistema trata de forma especial

- `id: "comentario"` — o banco **apaga a sessão** dessa linha, então o comentário não pode ser
  ligado a quem respondeu. É o que garante o anonimato. Chame a pergunta de comentário assim.
- `id` começando com `ident_` — vira a lista "quem se identificou", sempre em ordem alfabética e
  **sem horário**, para não reconstruir o vínculo pela linha do tempo.

## Uma pesquisa por dia

A 2ª turma usa um slug por dia (`...-t2-d1`, `-d2`, `-d3`). Isso mantém os eNPS separados, dá um
QR por dia e evita que o celular de quem respondeu ontem traga as respostas de ontem — o wizard
guarda o rascunho numa chave prefixada pela pesquisa.
