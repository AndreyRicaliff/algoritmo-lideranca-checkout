# Handoff — Checkout Algoritmo da Liderança
**Atualizado:** 2026-06-22 · Fonte de verdade da implementação atual.

> Stack vigente: **Google Apps Script + Google Sheets + Asaas**.
> `GUIA-API-ASAAS.md` (WordPress/PHP) e o design spec em `docs/superpowers/` foram
> **substituídos** por esta abordagem — mantidos só como referência histórica.

---

## ✅ Pronto para o dev aplicar?
**Sim — pode aplicar tudo no WordPress.** Checkout configurado com **PIX + Cartão**.
⚠️ **O PIX só funciona após a aprovação da conta Asaas** (em análise). Até lá: **cartão funciona**;
PIX escolhido cai no fallback de WhatsApp. Ou seja: pode montar a página agora, mas **só abra a
venda à vista (PIX) depois da aprovação**.

**Para o dev, na ordem:** §5 (deploy WordPress) → §4 (Apps Script + chave) → teste (cartão) → abrir PIX quando aprovar.

---

## 1. O que é
Coletor de lead + pagamento da inscrição da formação. O lead cai numa **planilha Google**;
o pagamento roda no **Asaas** (checkout hospedado, zero PCI). Sem servidor próprio.

## 2. Arquitetura / fluxo
```
Form (leadpage)──POST──▶ Apps Script ──▶ grava lead no Sheets ("lead")
                                      └─▶ cria cliente + cobrança Asaas
                                          └─▶ redireciona p/ invoiceUrl (paga)
Asaas ──webhook──▶ Apps Script ──▶ atualiza linha p/ "pago"
Falha no Asaas ──▶ redireciona p/ WhatsApp (não perde a venda)
```

## 3. Arquivos
| Arquivo | Função |
|---|---|
| `apps-script/Codigo.gs` | Backend: lead + cobrança + webhook → Sheets |
| `apps-script/leadpage.html` | Lead page completa (conteúdo + imagens + form no hero) |
| `apps-script/obrigado.html` | Página pós-pagamento (successUrl) + Pixel Purchase |
| `apps-script/assets/` | Imagens (criativos — placeholder até as imagens reais) |
| `README.md` | Quickstart |

## 4. Setup (Apps Script)
1. Criar Planilha Google → Extensões → Apps Script → colar `Codigo.gs`.
2. Propriedades do Script:
   `ASAAS_API_KEY`, `ASAAS_AMBIENTE` (`sandbox`|`producao`), `WEBHOOK_TOKEN`,
   `SUCCESS_URL` (= /obrigado), `WHATSAPP_FALLBACK` (= `https://wa.me/5583999661686`),
   `CHECKOUT_DUE_DATE`.
3. Implantar como App da Web (executar como Eu, acesso Qualquer pessoa) → copiar URL `…/exec`.
4. Webhook no Asaas → `…/exec?token=WEBHOOK_TOKEN`, eventos `PAYMENT_CONFIRMED` e `PAYMENT_RECEIVED`.

## 5. Deploy no WordPress (checklist)
- [ ] Publicar `leadpage.html` como página **nativa** (Elementor Canvas / widget HTML) — **sem iframe**.
- [ ] Subir as imagens na **Biblioteca de Mídia** e trocar os `src` de `assets/*.png` pelas URLs.
- [ ] Trocar o `action` do form pela URL `…/exec` do Web App.
- [ ] Publicar `obrigado.html` em `/obrigado` (mesmo domínio dos dados comerciais do Asaas).
- [ ] Criar a página `/politica-de-privacidade` (link do consentimento LGPD).
- [ ] Conferir Meta Pixel disparando: PageView (nativo) + Lead/InitiateCheckout (form) + Purchase (/obrigado).

## 6. Pagamento
- **No checkout:** **PIX (à vista R$ 1.670) + Cartão (5x R$ 1.970)**.
- ⚠️ **PIX depende da aprovação da conta Asaas** (em análise). Antes disso, escolha de PIX falha
  e cai no fallback de WhatsApp; **cartão funciona já**. Boleto segue suportado no backend
  (`Codigo.gs`) mas não está no form — para oferecê-lo, basta adicionar um radio `value="boleto"`.
- **Valores cobrados (reais):** à vista R$ 1.670 (PIX) · Cartão R$ 1.970 em 5x.
- **Âncora de desconto (visual):** ~~2.672~~→1.670 · ~~3.152~~→1.970 + selo "Turma Inaugural".
  ⚠️ = **37,5% off**, não 60%. % final **indefinido** (ver §8). Risco CDC se a âncora nunca foi praticada.

## 7. Status dos testes (2026-06-22, API de produção, registros de teste deletados)
| Item | Resultado |
|---|---|
| Criar cliente | ✅ OK |
| **Boleto** | ✅ **Funcionando** (gera fatura + boleto) |
| **Cartão** | ✅ **Funcionando** (cria fatura/checkout 5x; captura real a confirmar num pagamento) |
| **PIX** | ❌ **Bloqueado** — *"conta precisa estar aprovada"* (em análise no Asaas) |
| Webhook ponta-a-ponta | ⏳ não testado (precisa de pagamento real ou sandbox) |
| CPF validator (`Codigo.gs`) | ✅ testado |
| Sintaxe `Codigo.gs` | ✅ ok |

## 8. Pendências / bloqueadores
1. **APROVAR a conta Asaas** (AG, em análise) → faz o **PIX funcionar** (é o à-vista do checkout).
   Cartão já funciona, então a venda no cartão pode rodar antes; a venda à vista (PIX) só após a aprovação.
2. **Definir o % do desconto:** manter 2.672/3.152 (37,5%) ou subir âncoras p/ 60% real (~4.175 / ~4.925).
3. **Imagens reais** (hero/instrutores) — hoje criativos + avatares de iniciais.
4. **Deploy WordPress** + **teste ponta-a-ponta** (idealmente em **sandbox**; com a chave de produção, pagar = real).
5. **Confirmar o 13º módulo** (landing lista 12; plano diz 13).

## 9. Segurança / LGPD
- Chave Asaas só nas Propriedades do Script (nunca no front/git). A chave de **produção** foi
  compartilhada por chat → **rotacionar após o go-live**.
- Testar em **sandbox** antes de produção (a chave atual de produção cobra de verdade).
- Form com checkbox de consentimento + link à política. Não logar CPF/pagamento em claro.

## 10. Tracking (Meta Pixel)
PageView (nativo do site) · Lead + InitiateCheckout (envio do form) · Purchase (/obrigado).
Fonte de verdade da venda = status "pago" no Sheets (webhook), não o Pixel.
