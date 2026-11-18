# Exemplos financeiros

Casos reais do seed (`sql/03_seed.sql`), com o efeito em **caixa**, **competência (DRE)**, **estoque** e **posições**. Todos os valores foram obtidos executando os scripts em um banco vazio (PostgreSQL 16) e podem ser conferidos com as consultas indicadas. Data de referência: **30/06/2026**.

Antes de executar as consultas: `SET search_path TO fastcar;`

---

## 1. Venda à vista: Onix (V2026-001)

| Data | Evento | Caixa | DRE | Estoque |
|---|---|---:|---:|---:|
| 05/01 | Compra por 58.000, paga no dia | −58.000,00 | — | +58.000,00 |
| 07/01 e 09/01 | Documentação 850 + preparação 1.200 (pagas em 15/01 e 20/01) | −2.050,00 | — | +2.050,00 |
| 24/01 | Venda à vista por 72.900, recebida no dia | +72.900,00 | receita +72.900,00 / CMV −60.050,00 | −60.050,00 |
| 24/01 | Comissão de 2% (Ana), vence em 10/02 | — | −1.458,00 | — |
| 10/02 | Pagamento da comissão | −1.458,00 | — | — |

- Lucro bruto = 72.900 − 60.050 = **12.850,00** (margem bruta 17,63%).
- Margem de contribuição = 12.850 − 1.458 = **11.392,00**.
- A compra de 58.000 **nunca** aparece na DRE como despesa: entra no estoque e sai como CMV na venda.

```sql
SELECT * FROM vw_margem_veiculo_vendido WHERE numero_venda = 'V2026-001';
```

## 2. Venda parcelada com atraso e pagamento parcial: Compass (V2026-004)

Venda em 14/03 por 154.900: entrada de 54.900 + 5 parcelas de 20.000.

| Parcela | Vencimento | Recebimentos | Saldo em 30/06 | Situação |
|---|---|---|---:|---|
| 0 (entrada) | 14/03 | 54.900,00 em 14/03 | 0,00 | QUITADO |
| 1 | 14/04 | 20.000,00 em 14/04 | 0,00 | QUITADO |
| 2 | 14/05 | 12.000,00 em 14/05 + 8.000,00 com juros de 160,00 em 05/06 | 0,00 | QUITADO |
| 3 | 14/06 | — | 20.000,00 | VENCIDO (16 dias) |
| 4 | 14/07 | — | 20.000,00 | A_VENCER |
| 5 | 14/08 | — | 20.000,00 | A_VENCER |

- **DRE:** a receita de 154.900 e o CMV de 130.500 entram **inteiros em março**. As parcelas não geram receita.
- **Caixa:** entra conforme os recebimentos. Em 05/06 entraram 8.160 (8.000 de principal + 160 de juros).
- **Juros:** os 160 são **receita financeira de junho** (data do recebimento) e não reduzem o saldo da parcela.
- **Posição histórica:** em 31/05, a parcela 2 tinha saldo de 8.000 vencido e recebimento parcial.

```sql
SELECT documento, numero_parcela, data_vencimento, valor_titulo, valor_recebido, saldo_aberto, situacao
  FROM fn_posicao_contas_receber('2026-06-30') WHERE documento = 'V2026-004';

SELECT documento, numero_parcela, saldo_aberto, situacao, recebido_parcial
  FROM fn_posicao_contas_receber('2026-05-31') WHERE documento = 'V2026-004' AND numero_parcela = 2;
```

## 3. Saldo após pagamento parcial: Argo (V2026-007, parcela 2)

A parcela de 10.000, vencida em 18/06, recebeu 4.000 em 25/06. Em 30/06: valor 10.000, recebido 4.000, **saldo 6.000**, VENCIDO há 12 dias, `recebido_parcial = true`.

```sql
SELECT * FROM fn_posicao_contas_receber('2026-06-30') WHERE recebido_parcial;
```

## 4. Cheque devolvido: Gol (V2026-005, parcela 2)

| Data | Evento | Caixa (BCO_B) | Saldo da parcela |
|---|---|---:|---:|
| 05/05 | Recebimento em cheque | +6.000,00 | 0,00 |
| 08/05 | Estorno: cheque sem fundos | −6.000,00 | 6.000,00 |

- O recebimento original continua registrado, com situação `ESTORNADO`, data e motivo.
- O extrato mostra os dois movimentos (efeito líquido zero), preservando o histórico.
- A parcela voltou a ficar em aberto e, em 30/06, está **vencida há 56 dias** (faixa 31-60). Somada à parcela 3, vencida há 25 dias, o cliente Gustavo tem 12.000 vencidos.

```sql
SELECT * FROM vw_inadimplencia_cliente;
```

## 5. Cancelamento de venda e revenda: Renegade (V2026-006 → V2026-009)

Venda em 27/03 por 99.000 (entrada de 39.000 + 3 × 20.000), cancelada em 06/04 por desistência do cliente.

| Data | Lançamento | DRE | Caixa (BCO_A) |
|---|---|---:|---:|
| 27/03 | Receita bruta | +99.000,00 | — |
| 27/03 | CMV (82.000 + 2.000 de manutenção) | −84.000,00 | — |
| 27/03 | Comissão de 1,8% (Carla) | −1.782,00 | — |
| 27/03 | Entrada recebida | — | +39.000,00 |
| 06/04 | Cancelamento da venda | −99.000,00 | — |
| 06/04 | Reversão do CMV (veículo volta ao estoque) | +84.000,00 | — |
| 06/04 | Cancelamento da comissão (ainda não paga) | +1.782,00 | — |
| 06/04 | Devolução da entrada (estorno) | — | −39.000,00 |

- **Março não é reescrito:** continua mostrando o lucro de 13.218 dessa venda. A reversão aparece em **abril**, que por isso tem receita líquida negativa (−24.500) e margens nulas.
- Efeito líquido do semestre: **zero** em DRE e em caixa.
- As três parcelas e a comissão ficam `CANCELADO`, com data e motivo.
- Em 12/05 o veículo foi **revendido** (V2026-009) por 97.500, com CMV de 84.000. O veículo tem uma venda cancelada e uma ativa, e o índice único parcial permite isso.

```sql
SELECT * FROM fn_dre('2026-04-01', '2026-04-30');
SELECT data_competencia, linha_dre, valor, historico FROM vw_lancamento_competencia
 WHERE origem IN ('VENDA', 'CANCELAMENTO_VENDA')
   AND origem_id = (SELECT id FROM venda WHERE numero_venda = 'V2026-006');
```

## 6. Salários: competência x caixa

| Folha | Competência (DRE) | Pagamento (caixa) |
|---|---|---|
| Janeiro: 10.900,00 | janeiro | 05/02 |
| Junho: 11.600,00 | junho | **em aberto**, vence em 05/07 |

A despesa de junho já reduz o resultado de junho, mas ainda não saiu do caixa: aparece em contas a pagar A_VENCER.

## 7. Despesa parcelada: feirão de março

Custo de 4.500 em 3 × 1.500 (20/03, 20/04 e 20/05). **DRE:** 4.500 em março. **Caixa:** 1.500 em março, abril e maio.

## 8. Pagamento estornado e refeito: marketing de abril

| Data | Movimento | Valor |
|---|---|---:|
| 25/04 | Pagamento (boleto com dados errados) | −2.400,00 |
| 27/04 | Estorno: valor devolvido pela agência | +2.400,00 |
| 28/04 | Novo pagamento via PIX | −2.400,00 |

Saldo do título: 0. Saída líquida: 2.400. A DRE registra a despesa **uma vez** (2.400 em abril).

## 9. Despesa cancelada no mesmo mês: rádio de junho

Título de 1.800 lançado em 01/06 e cancelado em 12/06. A DRE de junho mostra +1.800 de despesa e −1.800 de reversão: **efeito zero**. O pagamento do título cancelado é bloqueado.

## 10. Transferências entre contas próprias

| Data | Origem → destino | Valor |
|---|---|---:|
| 06/03 | CAIXA → BCO_A (depósito do dinheiro da entrada do Gol) | 10.000,00 |
| 30/04 | BCO_B → BCO_A (concentração de saldo) | 60.000,00 |
| 29/06 | BCO_A → CAIXA (reforço de troco) | 1.500,00 |

Cada transferência gera uma saída e uma entrada. No resumo por conta, aparecem em `transferencias_recebidas`/`enviadas`; no consolidado, somam zero; na DRE, não aparecem.

```sql
SELECT * FROM fn_resumo_financeiro('2026-01-01', '2026-06-30');
```

## 11. Resultado financeiro

| Data | Fato | DRE |
|---|---|---:|
| 05/05 | Desconto por antecipação da parcela 3 do HB20 | −100,00 |
| 20/05 | Multa/juros de energia de abril paga com 5 dias de atraso | −18,50 |
| 05/06 | Juros da parcela 2 do Compass | +160,00 |
| 12/06 | Juros da parcela 4 do HB20 (2 dias de atraso) | +50,00 |

Maio: **−118,50**; junho: **+210,00**.

## 12. Por que o caixa difere do resultado? (janeiro)

| | Valor |
|---|---:|
| Resultado de janeiro (competência) | **−11.987,00** |
| Geração de caixa de janeiro | **−129.439,00** |

A diferença de 117.452 é explicada pelas posições no fim do mês:

```
Resultado = Δ caixa      + a receber − a pagar    + estoque
−11.987   = −129.439,00  + 0,00      − 50.348,00  + 167.800,00
```

- **Estoque de 167.800:** HB20 e Corolla comprados e preparados, mas ainda não vendidos. Saiu caixa e ainda não houve CMV.
- **A pagar de 50.348:** folha, contabilidade, energia, comissão, custos e a 2ª parcela do HB20, já reconhecidos (ou em estoque), mas ainda não pagos.

No semestre, a mesma identidade é verificada pelo teste automatizado 85:

```
14.604,10 = −418.659,40 + 236.000,00 − 101.736,50 + 299.000,00
```

## 13. Posição final (30/06/2026)

| Indicador | Valor |
|---|---:|
| Saldo em contas (BCO_A 154.480,60 + BCO_B 220.810,00 + CAIXA 11.050,00) | 386.340,60 |
| A receber em aberto (22 títulos) | 236.000,00 |
| … dos quais vencidos (4 títulos, 3 clientes) | 38.000,00 |
| A pagar em aberto (9 títulos) | 101.736,50 |
| … dos quais vencido (energia de maio) | 880,00 |
| Estoque (4 veículos, a custo) | 299.000,00 |
| Resultado do semestre (DRE gerencial) | 14.604,10 |
