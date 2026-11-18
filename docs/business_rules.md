# Regras de negócio

Este documento descreve como cada operação da Fast Car é registrada e como ela afeta o **caixa**, a **competência** (DRE gerencial), o **estoque** e as **posições** de contas a receber e a pagar. Os números citados vêm dos dados fictícios de `sql/03_seed.sql`.

> **Aviso:** a DRE deste projeto é **gerencial e simplificada**. O projeto não substitui um sistema contábil completo, não faz escrituração em partidas dobradas e não calcula tributos.

## 1. Princípios

| # | Princípio | Como é garantido |
|---|---|---|
| P1 | **Uma fonte por regime.** O caixa vem só de `movimento_bancario`; a competência vem só de `vw_lancamento_competencia`. | As views de caixa leem apenas movimentos; a DRE lê apenas o razão de competência. |
| P2 | **Cada fato econômico é reconhecido uma vez.** | A venda gera receita; suas parcelas e recebimentos não geram receita de novo (testes do grupo E). |
| P3 | **Compra de veículo é estoque, não despesa.** | Categorias de natureza `ESTOQUE` nunca entram na DRE; só viram CMV na venda. |
| P4 | **O histórico não é apagado nem reescrito.** | Gatilhos bloqueiam `DELETE` e alterações de valores; correções são feitas por cancelamento ou estorno, datados. |
| P5 | **Toda operação com várias etapas é atômica.** | As funções de negócio rodam em uma única transação; se uma etapa falha, nada persiste. O seed inteiro roda entre `BEGIN` e `COMMIT`. |
| P6 | **Datas reproduzíveis.** | Os relatórios de vencimento usam a data de referência da tabela `configuracao` (2026-06-30), não `current_date`. |

## 2. Regime de caixa x regime de competência

| | Regime de caixa | Regime de competência |
|---|---|---|
| Pergunta | Quanto dinheiro entrou e saiu? | Quanto a empresa ganhou ou gastou no período? |
| Data usada | Data do crédito/débito (`data_movimento`) | Data do fato gerador (`data_venda`, `data_competencia`) |
| Fonte | `movimento_bancario` | `vw_lancamento_competencia` |
| Relatórios | `fn_resumo_financeiro`, `vw_resumo_financeiro_mensal`, `vw_fluxo_caixa_*` | `fn_dre`, `vw_dre_mensal`, `vw_dre_comparativo_mensal` |
| Compra de veículo | Saída quando paga | Não entra (é estoque) |
| Venda de veículo | Entrada quando cada parcela é recebida | Receita integral e CMV na data da venda |
| Despesa | Saída quando paga | Na data de competência, paga ou não |
| Transferência entre contas | Saída em uma conta e entrada em outra (consolidado = 0) | Não entra |

A ponte entre os dois regimes, verificada no teste 85, é:

```
Resultado acumulado = Δ caixa + saldo a receber − saldo a pagar + valor do estoque
14.604,10           = −418.659,40 + 236.000,00 − 101.736,50 + 299.000,00
```

(Em 31/12/2025 não havia saldos a receber, a pagar nem estoque; só dinheiro em conta.)

## 3. Regras por operação

### 3.1 Compra de veículo — `fn_registrar_compra_veiculo`

1. Cadastra o veículo com situação `EM_PREPARACAO`.
2. Registra a compra (`compra_veiculo`, uma por veículo).
3. Gera um ou mais títulos a pagar na categoria `2.01 Aquisição de veículos para estoque` (natureza `ESTOQUE`).

| Efeito | Caixa | Competência | Estoque |
|---|---|---|---|
| Registro da compra | — | — | + valor da compra |
| Pagamento de cada parcela | − valor pago | — | — |

Títulos de compra não podem ser cancelados (o custo já está no estoque). Uma correção exigiria um ajuste de estoque, que está fora do escopo.

### 3.2 Custos adicionais por veículo — `fn_registrar_custo_veiculo`

- Tipos: `MANUTENCAO`, `DOCUMENTACAO`, `PREPARACAO`, `TRANSPORTE`.
- São **capitalizados**: somam-se ao custo do veículo em estoque e chegam à DRE como parte do CMV na venda.
- Só são aceitos para veículos **não vendidos** e com data igual ou posterior à compra.
- Gasto com veículo **já vendido** (ex.: garantia) é despesa do período: lance em `3.08 Garantia e pós-venda` com `fn_lancar_conta_pagar`. No seed: reparo de ar-condicionado do Onix vendido em janeiro, R$ 650 em maio.

### 3.3 Liberação para venda — `fn_disponibilizar_veiculo`

`EM_PREPARACAO` → `DISPONIVEL`. Só veículos `DISPONIVEL` podem ser vendidos.

### 3.4 Venda — `fn_registrar_venda`

1. Valida o veículo (`DISPONIVEL`, com a linha bloqueada para evitar duas vendas simultâneas) e as datas.
2. Grava a venda. O gatilho calcula `custo_veiculo_vendido` = aquisição + custos até a data da venda (fotografia do CMV) e muda o veículo para `VENDIDO`.
3. Gera os títulos a receber:
   - **parcela 0** = entrada, ou o valor integral se for à vista, com vencimento na data da venda;
   - **parcelas 1..N** mensais; a última absorve a diferença de arredondamento (a soma é sempre exata).
4. Gera o título de **comissão** (categoria `3.01`) para o vendedor: `valor_venda × percentual / 100`, competência na data da venda e vencimento no dia 10 do mês seguinte.

| Efeito | Caixa | Competência | Estoque | A receber |
|---|---|---|---|---|
| Registro da venda | — | + receita bruta; − CMV; − comissão | − custo do veículo | + valor da venda |
| Recebimento de parcela | + valor recebido | só juros/descontos | — | − principal |

**Sem dupla contagem:** a receita vem só da tabela `venda`. A categoria `1.01` é exclusiva dos títulos gerados por vendas (gatilho), e a DRE ignora títulos com `venda_id`.

**Venda duplicada:** bloqueada em três camadas:

1. o gatilho exige veículo `DISPONIVEL`;
2. o índice único parcial `uq_venda_veiculo_ativa` impede duas vendas `ATIVA` do mesmo veículo;
3. `numero_venda` é único.

### 3.5 Recebimentos e pagamentos (totais ou parciais) — `fn_registrar_recebimento` / `fn_registrar_pagamento`

- `valor_principal` é quanto do título foi liquidado; `valor_juros_multa` e `valor_desconto` são separados.
- Dinheiro movimentado (`valor_total`, coluna gerada) = principal + juros/multa − desconto.
- **Saldo em aberto** = valor do título − soma do principal das baixas **efetivas**.
- O principal não pode exceder o saldo em aberto. O título fica bloqueado durante a validação, então duas baixas simultâneas não ultrapassam o saldo.
- O título precisa estar `ATIVO`; a data da baixa não pode ser anterior à emissão nem ao saldo inicial da conta.
- Cada baixa gera exatamente um movimento bancário.
- **Juros/multa** recebidos são receita financeira, e **desconto concedido** é despesa financeira, na data da baixa. Para pagamentos, o sinal se inverte. Atraso não gera juros automaticamente: o valor é informado na baixa.

| Situação calculada | Regra |
|---|---|
| `QUITADO` | saldo = 0 |
| `VENCIDO` | saldo > 0 e vencimento < data-base |
| `A_VENCER` | saldo > 0 e vencimento ≥ data-base (vence hoje = a vencer) |
| Parcial | `recebido_parcial`/`pago_parcial` = já houve baixa e ainda há saldo |

### 3.6 Estorno — `fn_estornar_recebimento` / `fn_estornar_pagamento`

- A baixa original é preservada e marcada `ESTORNADO`, com data e motivo.
- Um **novo** movimento no sentido contrário é criado na mesma conta, na data do estorno.
- O saldo do título volta a ficar em aberto.
- Juros e descontos da baixa estornada são revertidos na DRE na data do estorno.
- Estornar duas vezes é bloqueado.
- Exemplos no seed: cheque devolvido do cliente do Gol (maio) e pagamento de marketing com boleto errado, devolvido e refeito (abril).

### 3.7 Cancelamento de venda — `fn_cancelar_venda`

Em uma única transação:

1. marca a venda como `CANCELADA` (o gatilho devolve o veículo para `DISPONIVEL`);
2. estorna todos os recebimentos efetivos da venda (devolução do dinheiro ao cliente);
3. cancela as parcelas a receber e o título de comissão.

Na DRE, a receita, o CMV e a comissão são **revertidos no mês do cancelamento**. O mês da venda original não é reescrito, então um relatório já fechado continua igual.

Se a comissão **já foi paga**, o cancelamento é recusado: estorne antes o pagamento da comissão (devolução pelo vendedor). Assim, a despesa de comissão nunca fica sem venda correspondente.

O veículo pode ser revendido depois. No seed, o Renegade (V2026-006) foi cancelado em 06/04 e revendido em 12/05 (V2026-009).

### 3.8 Cancelamento de títulos — `fn_cancelar_titulo_pagar` / `fn_cancelar_titulo_receber`

- Só é possível sem baixas efetivas (estorne antes).
- Títulos de compra e de custo de veículo não podem ser cancelados.
- Parcelas e comissões de venda só são canceladas pelo cancelamento da venda.
- Na DRE, a despesa ou receita é revertida no mês do cancelamento. No seed, a campanha de rádio de junho foi lançada e cancelada no próprio mês: efeito zero.

### 3.9 Transferência entre contas próprias — `fn_registrar_transferencia`

- Cria uma saída na conta de origem e uma entrada na conta de destino, de mesmo valor e data.
- Não é receita nem despesa: aparece em colunas próprias (`transferencias_recebidas`/`enviadas`) e soma zero no consolidado.
- Origem e destino precisam ser diferentes.

### 3.10 Despesas operacionais — `fn_lancar_conta_pagar`

- A despesa entra na DRE pela `data_competencia`, independentemente do pagamento.
- Pode ser parcelada: no seed, o feirão de março custou R$ 4.500, reconhecidos integralmente em março e pagos em 3 × R$ 1.500.
- Categorias: `3.02` marketing, `3.03` salários, `3.04` aluguel, `3.05` energia/telecom, `3.06` serviços de terceiros, `3.07` tarifas bancárias e `3.08` garantia. Comissões (`3.01`) nascem só das vendas.

### 3.11 Outras receitas — `fn_lancar_conta_receber`

Receitas que não são venda de veículo (ex.: serviço de despachante, `1.02`) entram na DRE pela competência do título, e o recebimento é só caixa.

## 4. CMV: como o custo do veículo vendido é reconhecido

```
CMV da venda = valor da compra + Σ custos adicionais com data ≤ data da venda
```

- O valor é fotografado em `venda.custo_veiculo_vendido` pelo gatilho; não é informado pelo usuário.
- Custos lançados depois da venda são bloqueados enquanto o veículo estiver vendido.
- Em um cancelamento, o CMV é revertido e o veículo volta ao estoque com o mesmo custo. Na revenda, o CMV é recalculado, incluindo custos que tenham sido lançados nesse meio-tempo.
- O teste 83 confere a conservação do estoque: compras + custos = estoque final + CMV líquido.

## 5. Integridade e imutabilidade

| Objeto | INSERT | UPDATE | DELETE |
|---|---|---|---|
| `movimento_bancario`, `transferencia`, `compra_veiculo`, `custo_veiculo` | por função | bloqueado | bloqueado |
| `venda` | por função (gatilho valida) | só cancelamento | bloqueado |
| `titulo_receber`, `titulo_pagar` | por função (gatilho valida categoria) | só cancelamento | bloqueado |
| `recebimento`, `pagamento` | por função (gatilho valida saldo) | só estorno | bloqueado |
| `veiculo` | por função | dados descritivos; a situação segue as regras de estado | — |

Gatilhos garantem as regras mesmo em `INSERT`/`UPDATE` diretos, fora das funções.

## 6. Indicadores e seu significado

| Indicador | Fórmula | Leitura |
|---|---|---|
| Saldo inicial / final | saldo inicial das contas + movimentos até a data | Dinheiro disponível em bancos e caixa |
| Entradas / saídas | movimentos do período, sem transferências | Dinheiro que entrou/saiu de fato (inclui estornos no sentido contrário) |
| Geração de caixa | entradas − saídas | Positivo = o caixa cresceu com as operações |
| Receita bruta | Σ vendas na data da venda | Volume vendido no mês |
| Cancelamentos | − Σ vendas canceladas na data do cancelamento | Reversões reconhecidas no mês |
| Receita operacional líquida | receita bruta + cancelamentos + outras receitas | Receita efetiva do período |
| CMV | − custo dos veículos vendidos (+ reversões) | Quanto custaram os carros vendidos |
| Lucro bruto | receita líquida + CMV | Ganho na revenda antes das despesas |
| Margem bruta % | lucro bruto / receita líquida | Nula quando a receita líquida é ≤ 0 |
| Despesas operacionais | vendas + pessoal + administrativas | Custo da estrutura do período |
| Resultado operacional | lucro bruto + despesas operacionais | Resultado da operação |
| Resultado financeiro | juros e multas ± descontos | Efeito de atrasos e antecipações |
| Resultado do período | operacional + financeiro | Lucro gerencial antes de tributos sobre o lucro |
| Margem de contribuição por veículo | venda − custo total − comissão | Quanto cada carro deixa para cobrir a estrutura |
| Dias em estoque | data da venda (ou data-base) − data da compra | Giro do estoque |
| Saldo em aberto | valor − principal das baixas efetivas | Quanto ainda falta receber ou pagar |
| Faixa de atraso | dias entre vencimento e data-base | 01-30, 31-60, 61-90, acima de 90 dias |
| % da carteira | saldo vencido da faixa / total a receber em aberto | Concentração de inadimplência |
| Diferença competência x caixa | resultado do mês − geração de caixa do mês | Explicada por estoque, prazos de recebimento e de pagamento |

## 7. Limitações conhecidas

- **Não é contabilidade oficial:** sem plano de contas contábil, partidas dobradas, balancete, encerramento de exercício nem SPED.
- **Sem tributos:** não há ICMS, PIS/COFINS, IRPJ/CSLL nem regime de margem de veículos usados. O resultado é "antes de tributos sobre o lucro".
- **Juros não são automáticos:** multa e juros de atraso são informados manualmente na baixa e reconhecidos no regime de caixa (na data da baixa), não por competência diária.
- **Sem ajuste de estoque:** não há baixa por perda ou sinistro, reavaliação ou devolução ao fornecedor.
- **Financiamento bancário e consórcio** não são modelados: as vendas parceladas são crediário próprio da loja.
- **Folha consolidada:** salários e encargos são um título mensal único, sem detalhamento por colaborador.
- **Moeda única (BRL)** e sem conciliação com extratos bancários reais (OFX/CNAB).
- **Controle de acesso** (papéis, permissões e RLS) não foi implementado.
- CPF/CNPJ são validados apenas no formato (quantidade de dígitos), não nos dígitos verificadores.
