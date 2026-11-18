# Diagrama de relacionamentos

Diagrama em [Mermaid](https://mermaid.js.org/) (o GitHub renderiza automaticamente). Para manter a leitura, cada entidade mostra as chaves e as colunas principais; a lista completa está em [`data_dictionary.md`](data_dictionary.md).

```mermaid
erDiagram
    FORNECEDOR     ||--o{ COMPRA_VEICULO     : "vende veículo"
    VEICULO        ||--|| COMPRA_VEICULO     : "adquirido em"
    VEICULO        ||--o{ CUSTO_VEICULO      : "recebe custos"
    FORNECEDOR     ||--o{ CUSTO_VEICULO      : "presta serviço"
    VEICULO        ||--o{ VENDA              : "vendido em (1 ativa)"
    CLIENTE        ||--o{ VENDA              : "compra"
    VENDEDOR       ||--o{ VENDA              : "vende"

    VENDA          ||--|{ TITULO_RECEBER     : "gera entrada e parcelas"
    CLIENTE        ||--o{ TITULO_RECEBER     : "deve"
    VENDA          ||--o| TITULO_PAGAR       : "gera comissão"
    VENDEDOR       ||--o{ TITULO_PAGAR       : "recebe comissão"
    COMPRA_VEICULO ||--|{ TITULO_PAGAR       : "gera parcelas"
    CUSTO_VEICULO  ||--|| TITULO_PAGAR       : "gera título"
    FORNECEDOR     |o--o{ TITULO_PAGAR       : "é credor"

    CATEGORIA_FINANCEIRA ||--o{ TITULO_RECEBER : "classifica"
    CATEGORIA_FINANCEIRA ||--o{ TITULO_PAGAR   : "classifica"
    CENTRO_CUSTO   ||--o{ TITULO_RECEBER     : "aloca"
    CENTRO_CUSTO   ||--o{ TITULO_PAGAR       : "aloca"

    TITULO_RECEBER ||--o{ RECEBIMENTO        : "baixado por"
    TITULO_PAGAR   ||--o{ PAGAMENTO          : "baixado por"
    CONTA_BANCARIA ||--o{ RECEBIMENTO        : "recebe"
    CONTA_BANCARIA ||--o{ PAGAMENTO          : "paga"

    RECEBIMENTO    ||--|{ MOVIMENTO_BANCARIO : "entrada e estorno"
    PAGAMENTO      ||--|{ MOVIMENTO_BANCARIO : "saída e estorno"
    TRANSFERENCIA  ||--|{ MOVIMENTO_BANCARIO : "saída + entrada"
    CONTA_BANCARIA ||--o{ MOVIMENTO_BANCARIO : "extrato"
    CONTA_BANCARIA ||--o{ TRANSFERENCIA      : "origem/destino"

    CLIENTE {
        int     id PK
        char    tipo_pessoa
        varchar documento UK "CPF ou CNPJ"
        varchar nome
    }
    FORNECEDOR {
        int     id PK
        varchar documento UK
        varchar nome
        varchar ramo
    }
    VENDEDOR {
        int     id PK
        char    cpf UK
        numeric percentual_comissao
    }
    VEICULO {
        int     id PK
        char    chassi UK
        varchar placa UK
        char    renavam UK
        varchar situacao "EM_PREPARACAO, DISPONIVEL, VENDIDO"
        numeric preco_anunciado
    }
    COMPRA_VEICULO {
        int     id PK
        varchar numero_compra UK
        int     veiculo_id FK "UK: 1 compra por veículo"
        int     fornecedor_id FK
        date    data_compra
        numeric valor_compra
    }
    CUSTO_VEICULO {
        bigint  id PK
        int     veiculo_id FK
        int     fornecedor_id FK
        varchar tipo "MANUTENCAO, DOCUMENTACAO, PREPARACAO, TRANSPORTE"
        date    data_custo
        numeric valor
    }
    VENDA {
        int     id PK
        varchar numero_venda UK
        int     veiculo_id FK
        int     cliente_id FK
        int     vendedor_id FK
        date    data_venda
        numeric valor_venda
        numeric custo_veiculo_vendido "CMV"
        numeric valor_comissao
        varchar situacao "ATIVA, CANCELADA"
        date    data_cancelamento
    }
    CATEGORIA_FINANCEIRA {
        int     id PK
        varchar codigo UK
        varchar natureza "RECEITA, DESPESA, ESTOQUE"
        varchar grupo_dre
    }
    CENTRO_CUSTO {
        smallint id PK
        varchar  codigo UK
    }
    TITULO_RECEBER {
        bigint  id PK
        varchar documento "UK com numero_parcela"
        smallint numero_parcela "0 = entrada"
        int     cliente_id FK
        int     venda_id FK
        int     categoria_id FK
        smallint centro_custo_id FK
        date    data_competencia
        date    data_vencimento
        numeric valor
        varchar situacao "ATIVO, CANCELADO"
    }
    TITULO_PAGAR {
        bigint  id PK
        varchar documento "UK com numero_parcela"
        smallint numero_parcela
        int     fornecedor_id FK
        int     vendedor_id FK
        int     categoria_id FK
        smallint centro_custo_id FK
        int     compra_veiculo_id FK
        bigint  custo_veiculo_id FK
        int     venda_id FK
        date    data_competencia
        date    data_vencimento
        numeric valor
        varchar situacao "ATIVO, CANCELADO"
    }
    RECEBIMENTO {
        bigint  id PK
        bigint  titulo_receber_id FK
        smallint conta_bancaria_id FK
        date    data_recebimento
        numeric valor_principal
        numeric valor_juros_multa
        numeric valor_desconto
        numeric valor_total "gerada"
        varchar situacao "EFETIVO, ESTORNADO"
    }
    PAGAMENTO {
        bigint  id PK
        bigint  titulo_pagar_id FK
        smallint conta_bancaria_id FK
        date    data_pagamento
        numeric valor_principal
        numeric valor_juros_multa
        numeric valor_desconto
        numeric valor_total "gerada"
        varchar situacao "EFETIVO, ESTORNADO"
    }
    CONTA_BANCARIA {
        smallint id PK
        varchar  codigo UK
        numeric  saldo_inicial
        date     data_saldo_inicial
    }
    TRANSFERENCIA {
        bigint   id PK
        smallint conta_origem_id FK
        smallint conta_destino_id FK
        date     data_transferencia
        numeric  valor
    }
    MOVIMENTO_BANCARIO {
        bigint   id PK
        smallint conta_bancaria_id FK
        date     data_movimento
        varchar  tipo "ENTRADA, SAIDA"
        varchar  natureza
        numeric  valor
        bigint   recebimento_id FK
        bigint   pagamento_id FK
        bigint   transferencia_id FK
    }
```

A tabela `configuracao` (linha única com a data de referência) não tem relacionamentos e foi omitida.

## Como ler os fluxos

```mermaid
flowchart LR
    subgraph comp["Regime de competência (DRE)"]
        V[venda] -->|receita e CMV| DRE[vw_lancamento_competencia]
        TPd[titulo_pagar de DESPESA] -->|data_competencia| DRE
        TRo[titulo_receber avulso] -->|outras receitas| DRE
        J[juros e descontos das baixas] --> DRE
    end
    subgraph caixa["Regime de caixa"]
        R[recebimento] --> MB[movimento_bancario]
        P[pagamento] --> MB
        T[transferencia] -->|saída + entrada| MB
    end
    subgraph estoque["Estoque (ativo)"]
        C[compra_veiculo] --> E[custo do veículo]
        CV[custo_veiculo] --> E
        E -->|na venda vira| V
    end
```

- A **compra** e os **custos** do veículo formam o custo em estoque; só chegam à DRE como **CMV** na data da venda.
- A **venda** é a única origem da receita de veículos. Suas parcelas (`titulo_receber`) são direitos a receber, e os recebimentos são caixa: nenhum dos dois gera receita de novo.
- Todo dinheiro passa por `movimento_bancario`, que é a única fonte dos relatórios de caixa.
