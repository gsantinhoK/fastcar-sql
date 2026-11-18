# Fast Car — Sistema Financeiro em SQL

Banco de dados em **PostgreSQL** para a gestão financeira de uma concessionária fictícia de veículos seminovos, a **Fast Car**. O projeto cobre compra e venda de veículos, estoque, contas a pagar e a receber com parcelamento, baixas parciais, estornos, contas bancárias e relatórios gerenciais que separam **regime de caixa** e **regime de competência**.

> Todos os dados são **sintéticos**: nomes, CPFs/CNPJs, chassis, placas, valores e e-mails (`example.com`) são inventados.
> A DRE é **gerencial e simplificada**. O projeto **não substitui um sistema contábil completo**.

## Sumário

- [Objetivo e escopo](#objetivo-e-escopo)
- [Tecnologias e pré-requisitos](#tecnologias-e-pré-requisitos)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Execução com Docker](#execução-com-docker)
- [Execução com PostgreSQL instalado](#execução-com-postgresql-instalado)
- [Relatórios disponíveis](#relatórios-disponíveis)
- [Exemplos de consultas e resultados esperados](#exemplos-de-consultas-e-resultados-esperados)
- [Caixa x competência](#caixa-x-competência)
- [Testes automatizados](#testes-automatizados)
- [Convenções](#convenções)
- [Limitações](#limitações)

## Objetivo e escopo

Demonstrar a modelagem e as regras de um controle financeiro real, com integridade garantida pelo próprio banco:

- **Cadastros:** clientes, fornecedores, vendedores, contas bancárias, categorias financeiras e centros de custo.
- **Veículos:** identificação única (chassi, placa, RENAVAM), compra, custos adicionais (manutenção, documentação, preparação, transporte) e situação no estoque.
- **Vendas:** à vista e parceladas, com comissão do vendedor, cancelamento e revenda.
- **Contas a pagar e a receber:** parcelas, vencimentos, pagamentos parciais ou integrais, juros, descontos, cancelamentos e estornos.
- **Tesouraria:** movimentos bancários imutáveis e transferências entre contas próprias.
- **Relatórios:** resumo e fluxo de caixa, DRE gerencial mensal, posição de contas, inadimplência, despesas por categoria e centro de custo, margem por veículo, comissões, estoque e comparação entre meses.

Os dados de exemplo cobrem **janeiro a junho de 2026**, com **data de referência fixa em 30/06/2026** (tabela `configuracao`), para que relatórios e testes sejam reproduzíveis.

## Tecnologias e pré-requisitos

| Item | Versão |
|---|---|
| PostgreSQL | **16** (validado em 16.15 e na imagem Docker `postgres:16.16`) |
| Cliente | `psql` (usa metacomandos como `\ir`, `\if` e `\echo`) |
| Docker (opcional) | Docker Engine com o plugin Compose v2 (`docker compose`) |

Os scripts usam recursos disponíveis desde o PostgreSQL 12 (colunas geradas, `EXECUTE FUNCTION` em gatilhos, índices com `INCLUDE`), mas **apenas a versão 16 foi testada**.

## Estrutura do projeto

```
fastcar-financeiro-sql/
├── README.md
├── .gitignore
├── compose.yaml                 # PostgreSQL 16 com sql/ e tests/ montados em /fastcar
├── .env.example                 # variáveis de exemplo (copie para .env)
├── sql/
│   ├── 01_schema.sql            # schema, tabelas, restrições, índices e comentários
│   ├── 02_functions.sql         # gatilhos de integridade e funções de negócio
│   ├── 03_seed.sql              # dados fictícios (jan–jun/2026)
│   ├── 04_views.sql             # views e funções de relatório
│   ├── 05_reports.sql           # relatórios prontos (período parametrizável)
│   └── run_all.sql              # executa 01 → 04 na ordem
├── tests/
│   └── financial_checks.sql     # 85 testes automatizados
└── docs/
    ├── data_dictionary.md       # tabelas, colunas, restrições, índices, views e funções
    ├── business_rules.md        # regras de cada operação e significado dos indicadores
    ├── financial_examples.md    # casos numéricos do seed explicados
    └── er_diagram.md            # diagrama de relacionamentos (Mermaid)
```

**Ordem de execução e dependências:** `01_schema` → `02_functions` (usa as tabelas) → `03_seed` (usa as funções) → `04_views` (usa tabelas e funções). Depois, `05_reports` e `tests/financial_checks` são somente leitura: os testes rodam em uma transação desfeita com `ROLLBACK`.

> Ajuste em relação à estrutura sugerida: acrescentei `sql/run_all.sql` para criar tudo com um único comando, mantendo os arquivos numerados para execução individual.

> **Atenção:** `01_schema.sql` executa `DROP SCHEMA IF EXISTS fastcar CASCADE`. Rode-o apenas em um banco de demonstração.

## Execução com Docker

Execute os comandos a partir da pasta do projeto.

```bash
# 1. Configure as variáveis locais (valores demonstrativos; troque a senha)
cp .env.example .env

# 2. Inicie o PostgreSQL e aguarde o status "healthy"
docker compose up -d
docker compose ps

# 3. Crie as estruturas e carregue os dados (01 → 04)
docker compose exec db psql -q -f /fastcar/sql/run_all.sql

# 4. Consulte os relatórios (padrão: 01/01/2026 a 30/06/2026)
docker compose exec db psql -f /fastcar/sql/05_reports.sql

# 4a. Relatórios de outro período e outra data-base de posições
docker compose exec db psql -v inicio=2026-04-01 -v fim=2026-06-30 -v data_base=2026-05-31 -f /fastcar/sql/05_reports.sql

# 5. Execute os testes (saída com código diferente de zero se algum reprovar)
docker compose exec db psql -f /fastcar/tests/financial_checks.sql

# 6. Abra um console SQL interativo
docker compose exec db psql
#    fastcar=# SET search_path TO fastcar;
#    fastcar=# SELECT * FROM vw_dre_mensal;

# 7. Encerre (o parâmetro -v também apaga o volume de dados)
docker compose down -v
```

- `PGUSER` e `PGDATABASE` já estão definidos no contêiner, por isso `psql` não precisa de `-U` nem de `-d`.
- Ao redirecionar a saída para um arquivo ou usar CI, acrescente `-T` (ex.: `docker compose exec -T db psql -f /fastcar/sql/05_reports.sql > saida.txt`).
- `run_all.sql` também pode ser executado sem `-q`; a opção só reduz as mensagens de cada comando.
- A porta é publicada apenas em `127.0.0.1`. Para conectar de uma ferramenta gráfica, use `postgresql://fastcar_admin:<sua_senha>@localhost:5432/fastcar` (altere a porta com `POSTGRES_PORT` no `.env`).

## Execução com PostgreSQL instalado

Use um usuário com permissão para criar bancos. Ajuste `-h`, `-p` e `-U` se necessário.

```bash
# 1. Crie um banco vazio
createdb fastcar

# 2. Crie as estruturas e carregue os dados, arquivo por arquivo:
psql -d fastcar -v ON_ERROR_STOP=1 -f sql/01_schema.sql
psql -d fastcar -v ON_ERROR_STOP=1 -f sql/02_functions.sql
psql -d fastcar -v ON_ERROR_STOP=1 -f sql/03_seed.sql
psql -d fastcar -v ON_ERROR_STOP=1 -f sql/04_views.sql

# ou, alternativamente, tudo de uma vez:
psql -d fastcar -q -f sql/run_all.sql

# 3. Relatórios (período padrão ou personalizado)
psql -d fastcar -f sql/05_reports.sql
psql -d fastcar -v inicio=2026-03-01 -v fim=2026-03-31 -f sql/05_reports.sql

# 4. Testes
psql -d fastcar -f tests/financial_checks.sql
```

Os testes silenciam a saída intermediária com `\o /dev/null`. No Windows, execute-os pelo Docker ou pelo WSL.

## Relatórios disponíveis

| Necessidade | Objeto | Regime |
|---|---|---|
| Resumo financeiro (saldo inicial, entradas, saídas, saldo final) de qualquer período | `fn_resumo_financeiro(inicio, fim)` | Caixa |
| Resumo mensal consolidado / por conta | `vw_resumo_financeiro_mensal`, `vw_resumo_financeiro_mensal_conta` | Caixa |
| Fluxo de caixa diário | `fn_fluxo_caixa_diario(inicio, fim)`, `vw_fluxo_caixa_diario` | Caixa |
| Fluxo de caixa mensal por grupo | `vw_fluxo_caixa_mensal`, `vw_fluxo_caixa_mensal_grupo` | Caixa |
| Extrato classificado | `vw_movimento_caixa` | Caixa |
| Saldo das contas em uma data | `fn_saldo_contas(data)` | Caixa |
| DRE gerencial de qualquer período | `fn_dre(inicio, fim)` | Competência |
| DRE mensal | `vw_dre_mensal` | Competência |
| Comparação entre meses (e com o caixa) | `vw_dre_comparativo_mensal` | Ambos |
| Razão de competência (origem de cada linha da DRE) | `vw_lancamento_competencia` | Competência |
| Contas a receber / a pagar em uma data-base | `fn_posicao_contas_receber(data)`, `fn_posicao_contas_pagar(data)` | Posição |
| Em aberto (vencidas x a vencer, após parciais) | `vw_contas_receber_aberto`, `vw_contas_pagar_aberto`, `vw_resumo_contas_aberto` | Posição |
| Inadimplência por cliente e faixa | `vw_inadimplencia_cliente`, `vw_inadimplencia_faixa` | Posição |
| Despesas por categoria e centro de custo | `vw_despesas_categoria_centro` (competência), `vw_pagamentos_categoria_centro` (caixa) | Ambos |
| Margem por veículo vendido | `vw_margem_veiculo_vendido` | Competência |
| Vendas e comissões por vendedor | `vw_vendas_comissoes_vendedor` | Competência |
| Estoque de veículos | `fn_estoque_veiculos(data)`, `vw_estoque_veiculos`, `vw_estoque_mensal` | Estoque |

O significado de cada indicador está em [`docs/business_rules.md`](docs/business_rules.md#6-indicadores-e-seu-significado).

## Exemplos de consultas e resultados esperados

Resultados obtidos com os dados do seed. Antes das consultas, execute `SET search_path TO fastcar;`.

### DRE gerencial do semestre

```sql
SELECT * FROM fn_dre('2026-01-01', '2026-06-30');
```

| ordem | linha | valor |
|---:|---|---:|
| 1 | (+) Receita bruta de vendas de veículos | 1197200.00 |
| 2 | (-) Cancelamentos de vendas | -99000.00 |
| 3 | (+) Outras receitas operacionais | 1450.00 |
| 4 | (=) Receita operacional líquida | 1099650.00 |
| 5 | (-) Custo dos veículos vendidos (CMV) | -919050.00 |
| 6 | (=) Lucro bruto | 180600.00 |
| 7 | (-) Despesas com vendas (comissões, marketing, garantia) | -42213.40 |
| 8 | (-) Despesas com pessoal | -68200.00 |
| 9 | (-) Despesas administrativas | -55674.00 |
| 10 | (=) Total de despesas operacionais | -166087.40 |
| 11 | (=) Resultado operacional | 14512.60 |
| 12 | (+) Receitas financeiras | 210.00 |
| 13 | (-) Despesas financeiras | -118.50 |
| 14 | (=) Resultado do período (antes de tributos sobre o lucro) | 14604.10 |

### Resultado mensal x geração de caixa

```sql
SELECT mes, receita_liquida, lucro_bruto, resultado_periodo, resultado_acumulado, geracao_caixa
  FROM vw_dre_comparativo_mensal;
```

| mes | receita_liquida | lucro_bruto | resultado_periodo | resultado_acumulado | geracao_caixa |
|---|---:|---:|---:|---:|---:|
| 2026-01-01 | 72900.00 | 12850.00 | -11987.00 | -11987.00 | -129439.00 |
| 2026-02-01 | 204800.00 | 37000.00 | 10494.50 | -1492.50 | -120137.00 |
| 2026-03-01 | 304450.00 | 49750.00 | 15482.30 | 13989.80 | -71955.50 |
| 2026-04-01 | -24500.00 | -2300.00 | -24864.50 | -10874.70 | -226385.70 |
| 2026-05-01 | 298200.00 | 42300.00 | 12214.30 | 1339.60 | 108185.00 |
| 2026-06-01 | 243800.00 | 41000.00 | 13264.50 | 14604.10 | 21072.80 |

Abril tem receita líquida negativa porque a venda cancelada de março (99.000) é revertida no mês do cancelamento, sem reescrever março.

### Resumo financeiro mensal (caixa consolidado)

```sql
SELECT * FROM vw_resumo_financeiro_mensal;
```

| mes | saldo_inicial | entradas | saidas | geracao_caixa | transferencias_liquidas | saldo_final |
|---|---:|---:|---:|---:|---:|---:|
| 2026-01-01 | 805000.00 | 72900.00 | 202339.00 | -129439.00 | 0.00 | 675561.00 |
| 2026-02-01 | 675561.00 | 129900.00 | 250037.00 | -120137.00 | 0.00 | 555424.00 |
| 2026-03-01 | 555424.00 | 138350.00 | 210305.50 | -71955.50 | 0.00 | 483468.50 |
| 2026-04-01 | 483468.50 | 57900.00 | 284285.70 | -226385.70 | 0.00 | 257082.80 |
| 2026-05-01 | 257082.80 | 331100.00 | 222915.00 | 108185.00 | 0.00 | 365267.80 |
| 2026-06-01 | 365267.80 | 181010.00 | 159937.20 | 21072.80 | 0.00 | 386340.60 |

### Resumo por conta no semestre

```sql
SELECT * FROM fn_resumo_financeiro('2026-01-01', '2026-06-30');
```

| conta_codigo | saldo_inicial | entradas | saidas | transferencias_recebidas | transferencias_enviadas | saldo_final |
|---|---:|---:|---:|---:|---:|---:|
| BCO_A | 650000.00 | 759800.00 | 1323819.40 | 70000.00 | 1500.00 | 154480.60 |
| BCO_B | 150000.00 | 136810.00 | 6000.00 | 0.00 | 60000.00 | 220810.00 |
| CAIXA | 5000.00 | 14550.00 | 0.00 | 1500.00 | 10000.00 | 11050.00 |
| TOTAL | 805000.00 | 911160.00 | 1329819.40 | 71500.00 | 71500.00 | 386340.60 |

### Contas em aberto em 30/06/2026

```sql
SELECT * FROM vw_resumo_contas_aberto;
```

| tipo | situacao | quantidade_titulos | valor_original | valor_baixado | saldo_aberto |
|---|---|---:|---:|---:|---:|
| RECEBER | A_VENCER | 18 | 198000.00 | 0.00 | 198000.00 |
| RECEBER | VENCIDO | 4 | 42000.00 | 4000.00 | 38000.00 |
| PAGAR | A_VENCER | 8 | 100856.50 | 0.00 | 100856.50 |
| PAGAR | VENCIDO | 1 | 880.00 | 0.00 | 880.00 |

O `valor_baixado` de 4.000 é o pagamento parcial da parcela 2 do Argo (saldo de 6.000 vencido).

### Inadimplência por faixa de atraso

```sql
SELECT * FROM vw_inadimplencia_faixa;
```

| faixa_atraso | titulos_vencidos | clientes | saldo_vencido | pct_carteira_aberta |
|---|---:|---:|---:|---:|
| 01-30 dias | 3 | 3 | 32000.00 | 13.56 |
| 31-60 dias | 1 | 1 | 6000.00 | 2.54 |
| 61-90 dias | 0 | 0 | 0 | 0.00 |
| Acima de 90 dias | 0 | 0 | 0 | 0.00 |

### Vendas e comissões por vendedor (semestre)

```sql
SELECT vendedor, sum(vendas_ativas) AS vendas, sum(vendas_canceladas) AS canceladas,
       sum(faturamento) AS faturamento, sum(comissao_devida) AS comissao,
       sum(comissao_paga) AS paga, sum(comissao_a_pagar) AS a_pagar
  FROM vw_vendas_comissoes_vendedor
 GROUP BY vendedor ORDER BY faturamento DESC;
```

| vendedor | vendas | canceladas | faturamento | comissao | paga | a_pagar |
|---|---:|---:|---:|---:|---:|---:|
| Ana Ribeiro | 4 | 0 | 425200.00 | 8504.00 | 5906.00 | 2598.00 |
| Carla Mendes | 2 | 1 | 354800.00 | 6386.40 | 6386.40 | 0.00 |
| Bruno Costa | 4 | 0 | 318200.00 | 4773.00 | 3064.50 | 1708.50 |

### Estoque em 30/06/2026

```sql
SELECT chassi, veiculo, situacao, dias_em_estoque, custo_total, preco_anunciado FROM vw_estoque_veiculos;
```

| chassi | veiculo | situacao | dias_em_estoque | custo_total | preco_anunciado |
|---|---|---|---:|---:|---:|
| FCAR2600000000010 | Renault Kwid 2023/2023 | DISPONIVEL | 63 | 45900.00 | 54900.00 |
| FCAR2600000000012 | Hyundai Creta 2021/2022 | DISPONIVEL | 32 | 89600.00 | 104900.00 |
| FCAR2600000000013 | Ford Ranger 2018/2018 | EM_PREPARACAO | 20 | 122500.00 | 139900.00 |
| FCAR2600000000014 | Renault Sandero 2020/2020 | EM_PREPARACAO | 10 | 41000.00 | 52900.00 |

Valor total do estoque a custo: **299.000,00**.

Outros casos comentados (venda parcelada com atraso, cheque devolvido, cancelamento e revenda, despesa parcelada, estorno de pagamento) estão em [`docs/financial_examples.md`](docs/financial_examples.md).

## Caixa x competência

- **Regime de caixa** responde "quanto dinheiro entrou e saiu". A fonte única é a tabela `movimento_bancario`, alimentada apenas por recebimentos, pagamentos, estornos e transferências.
- **Regime de competência** responde "quanto a empresa ganhou no período". A fonte única é `vw_lancamento_competencia`: receita e CMV na data da venda, despesas na data de competência, juros e descontos na data da baixa e reversões na data do cancelamento.

Regras essenciais:

1. **A compra de veículo não é despesa.** Ela vai para o estoque e, na venda, o custo (aquisição + manutenção, documentação, preparação e transporte) é reconhecido como **CMV**.
2. **Sem dupla contagem.** A venda gera a receita uma única vez. Parcelas (`titulo_receber`) são direitos e recebimentos são caixa: nenhum dos dois gera receita.
3. **Transferências entre contas próprias** não são receita nem despesa: somam zero no consolidado.
4. **Cancelamentos e estornos preservam o histórico.** Nada é apagado; a reversão é lançada na data em que ocorreu.

A ponte entre os regimes é verificada por teste (resultado = Δ caixa + a receber − a pagar + estoque):

```
14.604,10 = (386.340,60 − 805.000,00) + 236.000,00 − 101.736,50 + 299.000,00
```

Detalhes em [`docs/business_rules.md`](docs/business_rules.md).

## Testes automatizados

`tests/financial_checks.sql` executa **85 verificações** em uma transação finalizada com `ROLLBACK`: as simulações feitas pelos testes não alteram o banco. Ao final, mostra cada teste como APROVADO ou REPROVADO e sai com erro se algum reprovar.

| Grupo | O que verifica | Qtde |
|---|---|---:|
| A. Integridade | Títulos coerentes com compras, custos, vendas e comissões; um movimento por baixa; chaves estrangeiras; exclusões bloqueadas | 14 |
| B. Valores inválidos | `CHECK` de valores, documentos, chassi e datas; categorias incoerentes; alterações proibidas | 19 |
| C. Venda duplicada | Veículo vendido, em preparação ou número repetido; índice único parcial; revenda após cancelamento | 6 |
| D. Parciais e saldos | Saldo = valor − baixas; parciais do seed; posição histórica; pagamento além do saldo bloqueado | 12 |
| E. Dupla contagem | Receita = vendas; CMV = custo das vendas ativas; estoque fora da DRE; aditividade mensal | 10 |
| F. Transferências e estornos | Pares de movimentos; cheque devolvido; pagamento estornado; cancelamento de venda e de despesa | 12 |
| G. Reconciliação | Saldo inicial + movimentos = saldo final, por conta e mês; encadeamento entre meses; fluxo diário | 7 |
| H. Caixa x competência | Vendas = recebido + a receber; despesas = pago + a pagar; conservação do estoque; ponte de resultados | 5 |

Resultado esperado:

```
 total | aprovados | reprovados
-------+-----------+------------
    85 |        85 |          0
```

**Validação realizada** (18/11/2026): scripts executados em banco vazio no PostgreSQL 16.15 local e via `docker compose` com `postgres:16.16`, com 85/85 testes aprovados nos dois ambientes. A suíte foi executada duas vezes seguidas sem alterar os dados e reprovou (6 falhas, código de saída 3) quando os dados foram corrompidos de propósito.

## Convenções

- Nomes em **português**, minúsculos, `snake_case`, sem acentos; tabelas no **singular**.
- Chave primária `id`; chave estrangeira `<tabela>_id`.
- Prefixos: `pk_`, `fk_`, `uq_`, `ck_`, `ix_` (restrições e índices), `vw_` (views), `fn_` (funções), `fn_tg_` (funções de gatilho), `tg_` (gatilhos).
- Valores monetários em `numeric(14,2)`; percentuais em `numeric(5,2)`; datas de negócio em `date`.
- Situações em maiúsculas validadas por `CHECK` (`ATIVO`, `CANCELADO`, `EFETIVO`, `ESTORNADO` etc.).
- Arquivos SQL numerados na ordem de execução.
- As funções de negócio recebem **chaves de negócio** (chassi, CPF/CNPJ, número da venda, código da conta) para que o seed seja legível e não dependa de ids gerados.

Lista completa em [`docs/data_dictionary.md`](docs/data_dictionary.md).

## Limitações

- **Gerencial, não contábil:** sem plano de contas contábil, partidas dobradas, balanço patrimonial, fechamento de período nem obrigações acessórias.
- **Sem tributos** (ICMS, PIS/COFINS, IRPJ/CSLL, regime de margem de usados).
- **Juros e multas** são informados na baixa e reconhecidos na data do pagamento (não há cálculo automático nem apropriação diária).
- **Sem ajustes de estoque** (perdas, reavaliação, devolução ao fornecedor) e sem cancelamento de compras ou custos de veículos.
- **Vendas parceladas** são crediário próprio; financiamento bancário e consórcio não foram modelados.
- **Folha de pagamento** consolidada em um título mensal.
- **Sem controle de acesso** (papéis, permissões ou RLS) e sem conciliação com extratos bancários reais.
- CPF/CNPJ validados apenas quanto ao formato.

## Licença

Projeto de portfólio com dados fictícios. Defina a licença desejada (por exemplo, MIT) antes de publicar.
