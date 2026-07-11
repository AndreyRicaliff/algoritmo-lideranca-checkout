# Pendências — Algoritmo da Liderança (checkout Asaas)

> Itens acordados com Ricaliff que ainda não viraram trabalho. Ao concluir: mover para
> DECISIONS.md (se houve decisão) ou apagar a linha, no mesmo commit do fix.

## 🔴 Segurança

- **2026-07-09 — Rotacionar a chave PROD do Asaas exposta em chat.** A chave de produção
  (recebedor AGBR TECNOLOGIA) foi colada em conversa e nunca rotacionada. Passos:
  (1) gerar nova API key no painel Asaas; (2) trocar onde estiver em uso (handoff do dev
  WordPress — confirmar onde a chave vive hoje); (3) revogar a antiga.
  Precisa do Ricaliff (painel Asaas). Contexto: memória `project_algoritmo_lideranca_checkout`.
