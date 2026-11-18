# Dicionário de dados

Gerado a partir do catálogo do PostgreSQL (comentários `COMMENT ON` de `sql/01_schema.sql`) após a execução dos scripts. Schema: `fastcar`.

## Convenções de nomenclatura

| Elemento | Padrão | Exemplo |
|---|---|---|
| Schema | `fastcar` | `fastcar.venda` |
| Tabela | português, singular, `snake_case`, sem acentos | `titulo_pagar` |
| Chave primária | coluna `id`, restrição `pk_<tabela>` | `pk_venda` |
| Chave estrangeira | coluna `<tabela_referenciada>_id`, restrição `fk_<tabela>_<referência>` | `fk_venda_cliente` |
| Unicidade | `uq_<tabela>_<colunas>` | `uq_veiculo_chassi` |
| Verificação | `ck_<tabela>_<regra>` | `ck_venda_cancelamento` |
| Índice | `ix_<tabela>_<colunas>` (único: `uq_`) | `ix_movimento_bancario_conta_data` |
| View | `vw_<assunto>` | `vw_dre_mensal` |
| Função | `fn_<verbo>_<objeto>`; gatilho `fn_tg_*` | `fn_registrar_venda` |
| Gatilho | `tg_<tabela>_<finalidade>` | `tg_recebimento_valida` |
| Valor monetário | `numeric(14,2)` | `valor_venda` |
| Percentual | `numeric(5,2)` | `percentual_comissao` |
| Datas de negócio | `date`, prefixo `data_` | `data_competencia` |
| Situação | `varchar` com `CHECK` de valores em maiúsculas | `ATIVO`, `CANCELADO` |
| Arquivos SQL | prefixo numérico na ordem de execução | `01_schema.sql` |

## Tabelas

| Tabela | Descrição |
|---|---|
| [`configuracao`](#configuracao) | Parâmetros globais (linha única). Guarda a data de referência usada por relatórios de vencimento e estoque. |
| [`centro_custo`](#centro_custo) | Áreas da empresa às quais receitas e despesas são atribuídas (ex.: Administrativo, Comercial, Oficina). |
| [`categoria_financeira`](#categoria_financeira) | Plano de categorias. A natureza define o tratamento: RECEITA, DESPESA (vai à DRE pelo grupo_dre) ou ESTOQUE (ativo; só chega à DRE como CMV quando o veículo é vendido). |
| [`cliente`](#cliente) | Compradores de veículos e devedores de contas a receber. |
| [`fornecedor`](#fornecedor) | Quem vende veículos para a loja e quem presta serviços ou fornece bens (oficinas, despachantes, imobiliária etc.). |
| [`vendedor`](#vendedor) | Equipe comercial que recebe comissão sobre vendas. |
| [`conta_bancaria`](#conta_bancaria) | Contas próprias da empresa (bancos, caixa físico, aplicações). |
| [`veiculo`](#veiculo) | Veículos que passaram pelo estoque. A situação é controlada por gatilhos a partir das vendas. |
| [`compra_veiculo`](#compra_veiculo) | Aquisição de veículo para estoque. É ativo (estoque), não despesa: só chega à DRE como CMV quando o veículo é vendido. |
| [`custo_veiculo`](#custo_veiculo) | Custos adicionais incorporados ao custo do veículo em estoque (manutenção, documentação, preparação, transporte). Entram no CMV na venda. |
| [`venda`](#venda) | Venda de veículo. Fonte única da receita bruta e do CMV na DRE. Cancelamentos são registrados, nunca apagados. |
| [`titulo_receber`](#titulo_receber) | Contas a receber (uma linha por parcela). Representa o direito de receber; não é receita na DRE quando vem de venda de veículo. |
| [`titulo_pagar`](#titulo_pagar) | Contas a pagar (uma linha por parcela): compras de veículos, custos de veículos, comissões e despesas operacionais. |
| [`recebimento`](#recebimento) | Baixa (total ou parcial) de um título a receber. Cada recebimento gera um movimento bancário de entrada. |
| [`pagamento`](#pagamento) | Baixa (total ou parcial) de um título a pagar. Cada pagamento gera um movimento bancário de saída. |
| [`transferencia`](#transferencia) | Transferência entre contas próprias. Gera uma saída e uma entrada; não é receita nem despesa. |
| [`movimento_bancario`](#movimento_bancario) | Extrato de todas as contas: fonte única do regime de caixa. Imutável: correções são feitas por estorno. |

### configuracao

Parâmetros globais (linha única). Guarda a data de referência usada por relatórios de vencimento e estoque.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `smallint` | não | `1` | Sempre 1: garante uma única linha de configuração. |
| `data_referencia` | `date` | não |  | Data-base dos relatórios (vencidos, a vencer, dias em estoque). Fixada para tornar exemplos e testes reproduzíveis. |
| `descricao` | `character varying(200)` | sim |  | Observação livre sobre a configuração. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_configuracao_linha_unica` | `CHECK ((id = 1))` |
| `pk_configuracao` | `PRIMARY KEY (id)` |

### centro_custo

Áreas da empresa às quais receitas e despesas são atribuídas (ex.: Administrativo, Comercial, Oficina).

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `smallint` | não | identidade | Identificador interno. |
| `codigo` | `character varying(10)` | não |  | Código curto em maiúsculas (ex.: ADM, COM, OFI). |
| `nome` | `character varying(60)` | não |  | Nome do centro de custo. |
| `ativo` | `boolean` | não | `true` | Indica se o centro de custo aceita novos lançamentos. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_centro_custo_codigo` | `CHECK (((codigo)::text ~ '^[A-Z]{2,10}$'::text))` |
| `pk_centro_custo` | `PRIMARY KEY (id)` |
| `uq_centro_custo_codigo` | `UNIQUE (codigo)` |
| `uq_centro_custo_nome` | `UNIQUE (nome)` |

### categoria_financeira

Plano de categorias. A natureza define o tratamento: RECEITA, DESPESA (vai à DRE pelo grupo_dre) ou ESTOQUE (ativo; só chega à DRE como CMV quando o veículo é vendido).

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `integer` | não | identidade | Identificador interno. |
| `codigo` | `character varying(10)` | não |  | Código hierárquico (ex.: 3.04). Os códigos 1.01, 2.01, 2.02 e 3.01 são usados pelas funções do sistema. |
| `nome` | `character varying(80)` | não |  | Nome da categoria. |
| `natureza` | `character varying(10)` | não |  | RECEITA, DESPESA ou ESTOQUE. |
| `grupo_dre` | `character varying(30)` | sim |  | Linha da DRE gerencial. Nulo para ESTOQUE e para a receita de venda de veículos (reconhecida a partir da tabela venda). |
| `ativo` | `boolean` | não | `true` | Indica se a categoria aceita novos lançamentos. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_categoria_financeira_grupo_coerente` | `CHECK (((((natureza)::text = 'ESTOQUE'::text) AND (grupo_dre IS NULL)) OR (((natureza)::text = 'DESPESA'::text) AND ((grupo_dre)::text = ANY ((ARRAY['DESPESA_VENDAS'::character varying, 'DESPESA_PESSOAL'::character varying, 'DESPESA_ADMINISTRATIVA'::character varying])::text[]))) OR (((natureza)::text = 'RECEITA'::text) AND ((grupo_dre IS NULL) OR ((grupo_dre)::text = 'OUTRAS_RECEITAS'::text)))))` |
| `ck_categoria_financeira_grupo_dre` | `CHECK (((grupo_dre)::text = ANY ((ARRAY['OUTRAS_RECEITAS'::character varying, 'DESPESA_VENDAS'::character varying, 'DESPESA_PESSOAL'::character varying, 'DESPESA_ADMINISTRATIVA'::character varying])::text[])))` |
| `ck_categoria_financeira_natureza` | `CHECK (((natureza)::text = ANY ((ARRAY['RECEITA'::character varying, 'DESPESA'::character varying, 'ESTOQUE'::character varying])::text[])))` |
| `pk_categoria_financeira` | `PRIMARY KEY (id)` |
| `uq_categoria_financeira_codigo` | `UNIQUE (codigo)` |
| `uq_categoria_financeira_nome` | `UNIQUE (nome)` |

### cliente

Compradores de veículos e devedores de contas a receber.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `integer` | não | identidade | Identificador interno. |
| `tipo_pessoa` | `character(1)` | não |  | F = pessoa física (CPF), J = pessoa jurídica (CNPJ). |
| `nome` | `character varying(120)` | não |  | Nome ou razão social. |
| `documento` | `character varying(14)` | não |  | CPF (11 dígitos) ou CNPJ (14 dígitos), somente números. Dígitos verificadores não são validados (dados sintéticos). |
| `email` | `character varying(120)` | sim |  | E-mail de contato. |
| `telefone` | `character varying(20)` | sim |  | Telefone de contato. |
| `cidade` | `character varying(60)` | sim |  | Cidade. |
| `uf` | `character(2)` | sim |  | Unidade federativa (sigla). |
| `data_cadastro` | `date` | não |  | Data do cadastro. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_cliente_documento` | `CHECK ((((tipo_pessoa = 'F'::bpchar) AND ((documento)::text ~ '^[0-9]{11}$'::text)) OR ((tipo_pessoa = 'J'::bpchar) AND ((documento)::text ~ '^[0-9]{14}$'::text))))` |
| `ck_cliente_email` | `CHECK (((email)::text ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'::text))` |
| `ck_cliente_tipo_pessoa` | `CHECK ((tipo_pessoa = ANY (ARRAY['F'::bpchar, 'J'::bpchar])))` |
| `ck_cliente_uf` | `CHECK ((uf ~ '^[A-Z]{2}$'::text))` |
| `pk_cliente` | `PRIMARY KEY (id)` |
| `uq_cliente_documento` | `UNIQUE (documento)` |

### fornecedor

Quem vende veículos para a loja e quem presta serviços ou fornece bens (oficinas, despachantes, imobiliária etc.).

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `integer` | não | identidade | Identificador interno. |
| `tipo_pessoa` | `character(1)` | não |  | F = pessoa física, J = pessoa jurídica. |
| `nome` | `character varying(120)` | não |  | Nome ou razão social. |
| `documento` | `character varying(14)` | não |  | CPF ou CNPJ, somente números. |
| `ramo` | `character varying(60)` | não |  | Ramo de atividade (ex.: Oficina mecânica, Despachante). |
| `email` | `character varying(120)` | sim |  | E-mail de contato. |
| `telefone` | `character varying(20)` | sim |  | Telefone de contato. |
| `data_cadastro` | `date` | não |  | Data do cadastro. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_fornecedor_documento` | `CHECK ((((tipo_pessoa = 'F'::bpchar) AND ((documento)::text ~ '^[0-9]{11}$'::text)) OR ((tipo_pessoa = 'J'::bpchar) AND ((documento)::text ~ '^[0-9]{14}$'::text))))` |
| `ck_fornecedor_email` | `CHECK (((email)::text ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'::text))` |
| `ck_fornecedor_tipo_pessoa` | `CHECK ((tipo_pessoa = ANY (ARRAY['F'::bpchar, 'J'::bpchar])))` |
| `pk_fornecedor` | `PRIMARY KEY (id)` |
| `uq_fornecedor_documento` | `UNIQUE (documento)` |

### vendedor

Equipe comercial que recebe comissão sobre vendas.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `integer` | não | identidade | Identificador interno. |
| `nome` | `character varying(120)` | não |  | Nome do vendedor. |
| `cpf` | `character(11)` | não |  | CPF, somente números. |
| `email` | `character varying(120)` | sim |  | E-mail corporativo. |
| `percentual_comissao` | `numeric(5,2)` | não |  | Percentual de comissão vigente (0 a 10). É copiado para a venda no momento do registro. |
| `data_admissao` | `date` | não |  | Data de admissão. |
| `ativo` | `boolean` | não | `true` | Indica se pode registrar novas vendas. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_vendedor_cpf` | `CHECK ((cpf ~ '^[0-9]{11}$'::text))` |
| `ck_vendedor_email` | `CHECK (((email)::text ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'::text))` |
| `ck_vendedor_percentual_comissao` | `CHECK (((percentual_comissao >= (0)::numeric) AND (percentual_comissao <= (10)::numeric)))` |
| `pk_vendedor` | `PRIMARY KEY (id)` |
| `uq_vendedor_cpf` | `UNIQUE (cpf)` |

### conta_bancaria

Contas próprias da empresa (bancos, caixa físico, aplicações).

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `smallint` | não | identidade | Identificador interno. |
| `codigo` | `character varying(10)` | não |  | Código curto usado nas funções (ex.: BCO_A). |
| `descricao` | `character varying(60)` | não |  | Descrição da conta. |
| `tipo` | `character varying(10)` | não |  | CORRENTE, CAIXA ou APLICACAO. |
| `banco` | `character varying(60)` | sim |  | Nome do banco (fictício). |
| `agencia` | `character varying(10)` | sim |  | Agência. |
| `numero_conta` | `character varying(20)` | sim |  | Número da conta. |
| `saldo_inicial` | `numeric(14,2)` | não |  | Saldo no fim do dia data_saldo_inicial, ponto de partida da conciliação. |
| `data_saldo_inicial` | `date` | não |  | Data do saldo inicial. Movimentos só são aceitos após essa data. |
| `ativo` | `boolean` | não | `true` | Indica se a conta aceita movimentos. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_conta_bancaria_dados_banco` | `CHECK ((((tipo)::text = 'CAIXA'::text) OR ((banco IS NOT NULL) AND (agencia IS NOT NULL) AND (numero_conta IS NOT NULL))))` |
| `ck_conta_bancaria_tipo` | `CHECK (((tipo)::text = ANY ((ARRAY['CORRENTE'::character varying, 'CAIXA'::character varying, 'APLICACAO'::character varying])::text[])))` |
| `pk_conta_bancaria` | `PRIMARY KEY (id)` |
| `uq_conta_bancaria_codigo` | `UNIQUE (codigo)` |
| `uq_conta_bancaria_numero` | `UNIQUE (banco, agencia, numero_conta)` |

### veiculo

Veículos que passaram pelo estoque. A situação é controlada por gatilhos a partir das vendas.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `integer` | não | identidade | Identificador interno. |
| `chassi` | `character(17)` | não |  | Número de chassi (VIN) com 17 caracteres, sem I, O e Q. Identificação única do veículo. |
| `placa` | `character varying(7)` | sim |  | Placa no padrão Mercosul ou antigo, sem hífen. |
| `renavam` | `character(11)` | sim |  | Código RENAVAM com 11 dígitos. |
| `marca` | `character varying(40)` | não |  | Marca. |
| `modelo` | `character varying(60)` | não |  | Modelo. |
| `versao` | `character varying(60)` | sim |  | Versão/acabamento. |
| `ano_fabricacao` | `smallint` | não |  | Ano de fabricação. |
| `ano_modelo` | `smallint` | não |  | Ano do modelo (igual ou um ano após a fabricação). |
| `cor` | `character varying(30)` | sim |  | Cor. |
| `quilometragem` | `integer` | não |  | Quilometragem na entrada do estoque. |
| `situacao` | `character varying(15)` | não | `'EM_PREPARACAO'::character varying` | EM_PREPARACAO, DISPONIVEL ou VENDIDO. |
| `preco_anunciado` | `numeric(14,2)` | sim |  | Preço de tabela anunciado (referência; o valor negociado fica na venda). |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_veiculo_ano_fabricacao` | `CHECK (((ano_fabricacao >= 1980) AND (ano_fabricacao <= 2100)))` |
| `ck_veiculo_ano_modelo` | `CHECK (((ano_modelo >= ano_fabricacao) AND (ano_modelo <= (ano_fabricacao + 1))))` |
| `ck_veiculo_chassi` | `CHECK ((chassi ~ '^[A-HJ-NPR-Z0-9]{17}$'::text))` |
| `ck_veiculo_placa` | `CHECK (((placa)::text ~ '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$'::text))` |
| `ck_veiculo_preco_anunciado` | `CHECK ((preco_anunciado > (0)::numeric))` |
| `ck_veiculo_quilometragem` | `CHECK ((quilometragem >= 0))` |
| `ck_veiculo_renavam` | `CHECK ((renavam ~ '^[0-9]{11}$'::text))` |
| `ck_veiculo_situacao` | `CHECK (((situacao)::text = ANY ((ARRAY['EM_PREPARACAO'::character varying, 'DISPONIVEL'::character varying, 'VENDIDO'::character varying])::text[])))` |
| `pk_veiculo` | `PRIMARY KEY (id)` |
| `uq_veiculo_chassi` | `UNIQUE (chassi)` |
| `uq_veiculo_placa` | `UNIQUE (placa)` |
| `uq_veiculo_renavam` | `UNIQUE (renavam)` |

**Gatilhos:** `tg_veiculo_situacao` → `fn_tg_veiculo_situacao`

### compra_veiculo

Aquisição de veículo para estoque. É ativo (estoque), não despesa: só chega à DRE como CMV quando o veículo é vendido.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `integer` | não | identidade | Identificador interno. |
| `numero_compra` | `character varying(20)` | não |  | Número do documento de compra (ex.: C2026-001). Também é o documento dos títulos a pagar gerados. |
| `veiculo_id` | `integer` | não |  | Veículo adquirido (uma compra por veículo). |
| `fornecedor_id` | `integer` | não |  | Vendedor do veículo para a loja. |
| `data_compra` | `date` | não |  | Data de aquisição (entrada no estoque). |
| `valor_compra` | `numeric(14,2)` | não |  | Custo de aquisição. |
| `quantidade_parcelas` | `smallint` | não | `1` | Número de parcelas a pagar ao fornecedor. |
| `observacao` | `character varying(200)` | sim |  | Observação livre. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_compra_veiculo_parcelas` | `CHECK (((quantidade_parcelas >= 1) AND (quantidade_parcelas <= 24)))` |
| `ck_compra_veiculo_valor` | `CHECK ((valor_compra > (0)::numeric))` |
| `fk_compra_veiculo_fornecedor` | `FOREIGN KEY (fornecedor_id) REFERENCES fastcar.fornecedor(id)` |
| `fk_compra_veiculo_veiculo` | `FOREIGN KEY (veiculo_id) REFERENCES fastcar.veiculo(id)` |
| `pk_compra_veiculo` | `PRIMARY KEY (id)` |
| `uq_compra_veiculo_numero` | `UNIQUE (numero_compra)` |
| `uq_compra_veiculo_veiculo` | `UNIQUE (veiculo_id)` |

**Índices adicionais**

| Nome | Definição |
|---|---|
| `ix_compra_veiculo_fornecedor` | `INDEX ix_compra_veiculo_fornecedor ON compra_veiculo USING btree (fornecedor_id)` |

**Gatilhos:** `tg_compra_veiculo_imutavel` → `fn_tg_bloqueia_alteracao`

### custo_veiculo

Custos adicionais incorporados ao custo do veículo em estoque (manutenção, documentação, preparação, transporte). Entram no CMV na venda.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `bigint` | não | identidade | Identificador interno. |
| `veiculo_id` | `integer` | não |  | Veículo que recebeu o custo. |
| `fornecedor_id` | `integer` | não |  | Prestador do serviço. |
| `tipo` | `character varying(15)` | não |  | MANUTENCAO, DOCUMENTACAO, PREPARACAO ou TRANSPORTE. |
| `descricao` | `character varying(150)` | não |  | Descrição do serviço. |
| `data_custo` | `date` | não |  | Data em que o custo foi incorrido. Deve ser anterior à venda. |
| `valor` | `numeric(14,2)` | não |  | Valor do custo. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_custo_veiculo_tipo` | `CHECK (((tipo)::text = ANY ((ARRAY['MANUTENCAO'::character varying, 'DOCUMENTACAO'::character varying, 'PREPARACAO'::character varying, 'TRANSPORTE'::character varying])::text[])))` |
| `ck_custo_veiculo_valor` | `CHECK ((valor > (0)::numeric))` |
| `fk_custo_veiculo_fornecedor` | `FOREIGN KEY (fornecedor_id) REFERENCES fastcar.fornecedor(id)` |
| `fk_custo_veiculo_veiculo` | `FOREIGN KEY (veiculo_id) REFERENCES fastcar.veiculo(id)` |
| `pk_custo_veiculo` | `PRIMARY KEY (id)` |

**Índices adicionais**

| Nome | Definição |
|---|---|
| `ix_custo_veiculo_veiculo` | `INDEX ix_custo_veiculo_veiculo ON custo_veiculo USING btree (veiculo_id, data_custo)` |

**Gatilhos:** `tg_custo_veiculo_imutavel` → `fn_tg_bloqueia_alteracao`, `tg_custo_veiculo_valida` → `fn_tg_custo_veiculo_valida`

### venda

Venda de veículo. Fonte única da receita bruta e do CMV na DRE. Cancelamentos são registrados, nunca apagados.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `integer` | não | identidade | Identificador interno. |
| `numero_venda` | `character varying(20)` | não |  | Número da venda (ex.: V2026-001). Também é o documento dos títulos a receber. |
| `veiculo_id` | `integer` | não |  | Veículo vendido. Só pode haver uma venda ATIVA por veículo. |
| `cliente_id` | `integer` | não |  | Comprador. |
| `vendedor_id` | `integer` | não |  | Vendedor responsável (recebe a comissão). |
| `data_venda` | `date` | não |  | Data da venda: data de reconhecimento da receita e do CMV (competência). |
| `valor_venda` | `numeric(14,2)` | não |  | Valor total negociado. |
| `valor_entrada` | `numeric(14,2)` | não |  | Parte paga na data da venda (parcela 0). Igual ao valor da venda quando é à vista. |
| `quantidade_parcelas` | `smallint` | não |  | Parcelas mensais após a entrada (0 = à vista). |
| `custo_veiculo_vendido` | `numeric(14,2)` | não |  | Fotografia do custo total (aquisição + custos adicionais) na data da venda; é o CMV reconhecido. |
| `percentual_comissao` | `numeric(5,2)` | não |  | Percentual de comissão copiado do vendedor na data da venda. |
| `valor_comissao` | `numeric(14,2)` | não |  | Comissão calculada (valor_venda x percentual / 100, arredondado em 2 casas). |
| `situacao` | `character varying(10)` | não | `'ATIVA'::character varying` | ATIVA ou CANCELADA. |
| `data_cancelamento` | `date` | sim |  | Data do cancelamento; a reversão de receita e CMV é reconhecida nesse mês. |
| `motivo_cancelamento` | `character varying(200)` | sim |  | Justificativa do cancelamento. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_venda_cancelamento` | `CHECK (((((situacao)::text = 'ATIVA'::text) AND (data_cancelamento IS NULL) AND (motivo_cancelamento IS NULL)) OR (((situacao)::text = 'CANCELADA'::text) AND (data_cancelamento >= data_venda) AND (motivo_cancelamento IS NOT NULL))))` |
| `ck_venda_comissao` | `CHECK ((valor_comissao = round(((valor_venda * percentual_comissao) / (100)::numeric), 2)))` |
| `ck_venda_custo` | `CHECK ((custo_veiculo_vendido > (0)::numeric))` |
| `ck_venda_entrada` | `CHECK (((valor_entrada >= (0)::numeric) AND (valor_entrada <= valor_venda)))` |
| `ck_venda_parcelas` | `CHECK ((((quantidade_parcelas = 0) AND (valor_entrada = valor_venda)) OR (((quantidade_parcelas >= 1) AND (quantidade_parcelas <= 48)) AND (valor_entrada < valor_venda))))` |
| `ck_venda_percentual_comissao` | `CHECK (((percentual_comissao >= (0)::numeric) AND (percentual_comissao <= (10)::numeric)))` |
| `ck_venda_situacao` | `CHECK (((situacao)::text = ANY ((ARRAY['ATIVA'::character varying, 'CANCELADA'::character varying])::text[])))` |
| `ck_venda_valor` | `CHECK ((valor_venda > (0)::numeric))` |
| `fk_venda_cliente` | `FOREIGN KEY (cliente_id) REFERENCES fastcar.cliente(id)` |
| `fk_venda_veiculo` | `FOREIGN KEY (veiculo_id) REFERENCES fastcar.veiculo(id)` |
| `fk_venda_vendedor` | `FOREIGN KEY (vendedor_id) REFERENCES fastcar.vendedor(id)` |
| `pk_venda` | `PRIMARY KEY (id)` |
| `uq_venda_numero` | `UNIQUE (numero_venda)` |

**Índices adicionais**

| Nome | Definição |
|---|---|
| `ix_venda_cliente` | `INDEX ix_venda_cliente ON venda USING btree (cliente_id)` |
| `ix_venda_data_venda` | `INDEX ix_venda_data_venda ON venda USING btree (data_venda)` |
| `ix_venda_vendedor_data` | `INDEX ix_venda_vendedor_data ON venda USING btree (vendedor_id, data_venda)` |
| `uq_venda_veiculo_ativa` | `UNIQUE INDEX uq_venda_veiculo_ativa ON venda USING btree (veiculo_id) WHERE ((situacao)::text = 'ATIVA'::text)` |

**Gatilhos:** `tg_venda_antes` → `fn_tg_venda_antes`, `tg_venda_depois` → `fn_tg_venda_depois`, `tg_venda_sem_exclusao` → `fn_tg_bloqueia_exclusao`

### titulo_receber

Contas a receber (uma linha por parcela). Representa o direito de receber; não é receita na DRE quando vem de venda de veículo.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `bigint` | não | identidade | Identificador interno. |
| `documento` | `character varying(30)` | não |  | Documento de origem (número da venda ou código do serviço). |
| `numero_parcela` | `smallint` | não |  | Número da parcela. 0 = entrada ou pagamento à vista de uma venda. |
| `total_parcelas` | `smallint` | não |  | Quantidade de parcelas mensais do documento (sem contar a entrada). |
| `cliente_id` | `integer` | não |  | Devedor. |
| `venda_id` | `integer` | sim |  | Venda de origem, quando houver. |
| `categoria_id` | `integer` | não |  | Categoria financeira (natureza RECEITA). |
| `centro_custo_id` | `smallint` | não |  | Centro de custo responsável. |
| `descricao` | `character varying(150)` | não |  | Descrição do título. |
| `data_emissao` | `date` | não |  | Data de emissão. |
| `data_competencia` | `date` | não |  | Data do fato gerador (usada na DRE para receitas que não vêm de venda de veículo). |
| `data_vencimento` | `date` | não |  | Data de vencimento. |
| `valor` | `numeric(14,2)` | não |  | Valor original da parcela. |
| `situacao` | `character varying(10)` | não | `'ATIVO'::character varying` | ATIVO ou CANCELADO. Situações como VENCIDO e QUITADO são calculadas nas consultas. |
| `data_cancelamento` | `date` | sim |  | Data do cancelamento. |
| `motivo_cancelamento` | `character varying(200)` | sim |  | Justificativa do cancelamento. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_titulo_receber_cancelamento` | `CHECK (((((situacao)::text = 'ATIVO'::text) AND (data_cancelamento IS NULL) AND (motivo_cancelamento IS NULL)) OR (((situacao)::text = 'CANCELADO'::text) AND (data_cancelamento >= data_emissao) AND (motivo_cancelamento IS NOT NULL))))` |
| `ck_titulo_receber_parcela` | `CHECK ((((numero_parcela >= 0) AND (numero_parcela <= total_parcelas)) AND ((total_parcelas >= 0) AND (total_parcelas <= 48))))` |
| `ck_titulo_receber_parcela_zero` | `CHECK (((numero_parcela > 0) OR (venda_id IS NOT NULL)))` |
| `ck_titulo_receber_situacao` | `CHECK (((situacao)::text = ANY ((ARRAY['ATIVO'::character varying, 'CANCELADO'::character varying])::text[])))` |
| `ck_titulo_receber_valor` | `CHECK ((valor > (0)::numeric))` |
| `ck_titulo_receber_vencimento` | `CHECK ((data_vencimento >= data_emissao))` |
| `fk_titulo_receber_categoria` | `FOREIGN KEY (categoria_id) REFERENCES fastcar.categoria_financeira(id)` |
| `fk_titulo_receber_centro_custo` | `FOREIGN KEY (centro_custo_id) REFERENCES fastcar.centro_custo(id)` |
| `fk_titulo_receber_cliente` | `FOREIGN KEY (cliente_id) REFERENCES fastcar.cliente(id)` |
| `fk_titulo_receber_venda` | `FOREIGN KEY (venda_id) REFERENCES fastcar.venda(id)` |
| `pk_titulo_receber` | `PRIMARY KEY (id)` |
| `uq_titulo_receber_documento_parcela` | `UNIQUE (documento, numero_parcela)` |

**Índices adicionais**

| Nome | Definição |
|---|---|
| `ix_titulo_receber_cliente` | `INDEX ix_titulo_receber_cliente ON titulo_receber USING btree (cliente_id, data_vencimento)` |
| `ix_titulo_receber_vencimento_ativo` | `INDEX ix_titulo_receber_vencimento_ativo ON titulo_receber USING btree (data_vencimento) WHERE ((situacao)::text = 'ATIVO'::text)` |
| `ix_titulo_receber_venda` | `INDEX ix_titulo_receber_venda ON titulo_receber USING btree (venda_id)` |

**Gatilhos:** `tg_titulo_receber_sem_exclusao` → `fn_tg_bloqueia_exclusao`, `tg_titulo_receber_valida` → `fn_tg_titulo_receber_valida`

### titulo_pagar

Contas a pagar (uma linha por parcela): compras de veículos, custos de veículos, comissões e despesas operacionais.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `bigint` | não | identidade | Identificador interno. |
| `documento` | `character varying(30)` | não |  | Documento de origem (nota, contrato, número da compra, COM-<venda>, nota do custo de veículo). |
| `numero_parcela` | `smallint` | não |  | Número da parcela (1..total_parcelas). |
| `total_parcelas` | `smallint` | não |  | Quantidade de parcelas do documento. |
| `fornecedor_id` | `integer` | sim |  | Fornecedor credor (opcional; ex.: folha consolidada não tem fornecedor). |
| `vendedor_id` | `integer` | sim |  | Vendedor credor, nos títulos de comissão. |
| `categoria_id` | `integer` | não |  | Categoria financeira (natureza DESPESA ou ESTOQUE). |
| `centro_custo_id` | `smallint` | não |  | Centro de custo. |
| `compra_veiculo_id` | `integer` | sim |  | Compra de veículo de origem (categoria de estoque). |
| `custo_veiculo_id` | `bigint` | sim |  | Custo de veículo de origem (categoria de estoque). |
| `venda_id` | `integer` | sim |  | Venda que originou a comissão. |
| `descricao` | `character varying(150)` | não |  | Descrição do título. |
| `data_emissao` | `date` | não |  | Data de emissão. |
| `data_competencia` | `date` | não |  | Mês em que a despesa é reconhecida na DRE (regime de competência). |
| `data_vencimento` | `date` | não |  | Data de vencimento. |
| `valor` | `numeric(14,2)` | não |  | Valor original da parcela. |
| `situacao` | `character varying(10)` | não | `'ATIVO'::character varying` | ATIVO ou CANCELADO. |
| `data_cancelamento` | `date` | sim |  | Data do cancelamento; a reversão da despesa é reconhecida nesse mês. |
| `motivo_cancelamento` | `character varying(200)` | sim |  | Justificativa do cancelamento. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_titulo_pagar_cancelamento` | `CHECK (((((situacao)::text = 'ATIVO'::text) AND (data_cancelamento IS NULL) AND (motivo_cancelamento IS NULL)) OR (((situacao)::text = 'CANCELADO'::text) AND (data_cancelamento >= data_emissao) AND (motivo_cancelamento IS NOT NULL))))` |
| `ck_titulo_pagar_comissao` | `CHECK (((venda_id IS NULL) OR (vendedor_id IS NOT NULL)))` |
| `ck_titulo_pagar_favorecido` | `CHECK ((num_nonnulls(fornecedor_id, vendedor_id) <= 1))` |
| `ck_titulo_pagar_origem` | `CHECK ((num_nonnulls(compra_veiculo_id, custo_veiculo_id, venda_id) <= 1))` |
| `ck_titulo_pagar_parcela` | `CHECK ((((numero_parcela >= 1) AND (numero_parcela <= total_parcelas)) AND (total_parcelas <= 48)))` |
| `ck_titulo_pagar_situacao` | `CHECK (((situacao)::text = ANY ((ARRAY['ATIVO'::character varying, 'CANCELADO'::character varying])::text[])))` |
| `ck_titulo_pagar_valor` | `CHECK ((valor > (0)::numeric))` |
| `ck_titulo_pagar_vencimento` | `CHECK ((data_vencimento >= data_emissao))` |
| `fk_titulo_pagar_categoria` | `FOREIGN KEY (categoria_id) REFERENCES fastcar.categoria_financeira(id)` |
| `fk_titulo_pagar_centro_custo` | `FOREIGN KEY (centro_custo_id) REFERENCES fastcar.centro_custo(id)` |
| `fk_titulo_pagar_compra_veiculo` | `FOREIGN KEY (compra_veiculo_id) REFERENCES fastcar.compra_veiculo(id)` |
| `fk_titulo_pagar_custo_veiculo` | `FOREIGN KEY (custo_veiculo_id) REFERENCES fastcar.custo_veiculo(id)` |
| `fk_titulo_pagar_fornecedor` | `FOREIGN KEY (fornecedor_id) REFERENCES fastcar.fornecedor(id)` |
| `fk_titulo_pagar_venda` | `FOREIGN KEY (venda_id) REFERENCES fastcar.venda(id)` |
| `fk_titulo_pagar_vendedor` | `FOREIGN KEY (vendedor_id) REFERENCES fastcar.vendedor(id)` |
| `pk_titulo_pagar` | `PRIMARY KEY (id)` |
| `uq_titulo_pagar_documento_parcela` | `UNIQUE (documento, numero_parcela)` |

**Índices adicionais**

| Nome | Definição |
|---|---|
| `ix_titulo_pagar_competencia` | `INDEX ix_titulo_pagar_competencia ON titulo_pagar USING btree (data_competencia, categoria_id)` |
| `ix_titulo_pagar_compra` | `INDEX ix_titulo_pagar_compra ON titulo_pagar USING btree (compra_veiculo_id) WHERE (compra_veiculo_id IS NOT NULL)` |
| `ix_titulo_pagar_custo` | `INDEX ix_titulo_pagar_custo ON titulo_pagar USING btree (custo_veiculo_id) WHERE (custo_veiculo_id IS NOT NULL)` |
| `ix_titulo_pagar_fornecedor` | `INDEX ix_titulo_pagar_fornecedor ON titulo_pagar USING btree (fornecedor_id)` |
| `ix_titulo_pagar_vencimento_ativo` | `INDEX ix_titulo_pagar_vencimento_ativo ON titulo_pagar USING btree (data_vencimento) WHERE ((situacao)::text = 'ATIVO'::text)` |
| `ix_titulo_pagar_venda` | `INDEX ix_titulo_pagar_venda ON titulo_pagar USING btree (venda_id) WHERE (venda_id IS NOT NULL)` |

**Gatilhos:** `tg_titulo_pagar_sem_exclusao` → `fn_tg_bloqueia_exclusao`, `tg_titulo_pagar_valida` → `fn_tg_titulo_pagar_valida`

### recebimento

Baixa (total ou parcial) de um título a receber. Cada recebimento gera um movimento bancário de entrada.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `bigint` | não | identidade | Identificador interno. |
| `titulo_receber_id` | `bigint` | não |  | Título baixado. |
| `conta_bancaria_id` | `smallint` | não |  | Conta que recebeu o dinheiro. |
| `data_recebimento` | `date` | não |  | Data do crédito (regime de caixa). |
| `valor_principal` | `numeric(14,2)` | não |  | Quanto do título foi liquidado (reduz o saldo em aberto). Inclui o desconto concedido. |
| `valor_juros_multa` | `numeric(14,2)` | não | `0` | Juros e multa por atraso cobrados (receita financeira). |
| `valor_desconto` | `numeric(14,2)` | não | `0` | Desconto concedido (despesa financeira). |
| `valor_total` | `numeric(14,2)` | sim | gerada: `((valor_principal + valor_juros_multa) - valor_desconto)` | Dinheiro efetivamente recebido = principal + juros/multa - desconto (coluna gerada). |
| `forma_pagamento` | `character varying(10)` | não |  | PIX, TED, BOLETO, DINHEIRO, CARTAO ou CHEQUE. |
| `situacao` | `character varying(10)` | não | `'EFETIVO'::character varying` | EFETIVO ou ESTORNADO. |
| `data_estorno` | `date` | sim |  | Data do estorno (ex.: cheque devolvido, devolução ao cliente). |
| `motivo_estorno` | `character varying(200)` | sim |  | Justificativa do estorno. |
| `observacao` | `character varying(200)` | sim |  | Observação livre. |
| `criado_em` | `timestamp with time zone` | não | `now()` | Data e hora técnica do registro. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_recebimento_desconto` | `CHECK (((valor_desconto >= (0)::numeric) AND (valor_desconto < (valor_principal + valor_juros_multa))))` |
| `ck_recebimento_estorno` | `CHECK (((((situacao)::text = 'EFETIVO'::text) AND (data_estorno IS NULL) AND (motivo_estorno IS NULL)) OR (((situacao)::text = 'ESTORNADO'::text) AND (data_estorno >= data_recebimento) AND (motivo_estorno IS NOT NULL))))` |
| `ck_recebimento_forma` | `CHECK (((forma_pagamento)::text = ANY ((ARRAY['PIX'::character varying, 'TED'::character varying, 'BOLETO'::character varying, 'DINHEIRO'::character varying, 'CARTAO'::character varying, 'CHEQUE'::character varying])::text[])))` |
| `ck_recebimento_juros` | `CHECK ((valor_juros_multa >= (0)::numeric))` |
| `ck_recebimento_principal` | `CHECK ((valor_principal > (0)::numeric))` |
| `ck_recebimento_situacao` | `CHECK (((situacao)::text = ANY ((ARRAY['EFETIVO'::character varying, 'ESTORNADO'::character varying])::text[])))` |
| `fk_recebimento_conta` | `FOREIGN KEY (conta_bancaria_id) REFERENCES fastcar.conta_bancaria(id)` |
| `fk_recebimento_titulo` | `FOREIGN KEY (titulo_receber_id) REFERENCES fastcar.titulo_receber(id)` |
| `pk_recebimento` | `PRIMARY KEY (id)` |

**Índices adicionais**

| Nome | Definição |
|---|---|
| `ix_recebimento_data` | `INDEX ix_recebimento_data ON recebimento USING btree (data_recebimento)` |
| `ix_recebimento_titulo` | `INDEX ix_recebimento_titulo ON recebimento USING btree (titulo_receber_id) INCLUDE (valor_principal, situacao)` |

**Gatilhos:** `tg_recebimento_sem_exclusao` → `fn_tg_bloqueia_exclusao`, `tg_recebimento_valida` → `fn_tg_recebimento_valida`

### pagamento

Baixa (total ou parcial) de um título a pagar. Cada pagamento gera um movimento bancário de saída.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `bigint` | não | identidade | Identificador interno. |
| `titulo_pagar_id` | `bigint` | não |  | Título baixado. |
| `conta_bancaria_id` | `smallint` | não |  | Conta debitada. |
| `data_pagamento` | `date` | não |  | Data do débito (regime de caixa). |
| `valor_principal` | `numeric(14,2)` | não |  | Quanto do título foi liquidado (reduz o saldo em aberto). Inclui o desconto obtido. |
| `valor_juros_multa` | `numeric(14,2)` | não | `0` | Juros e multa pagos por atraso (despesa financeira). |
| `valor_desconto` | `numeric(14,2)` | não | `0` | Desconto obtido (receita financeira). |
| `valor_total` | `numeric(14,2)` | sim | gerada: `((valor_principal + valor_juros_multa) - valor_desconto)` | Dinheiro efetivamente pago = principal + juros/multa - desconto (coluna gerada). |
| `forma_pagamento` | `character varying(10)` | não |  | PIX, TED, BOLETO, DINHEIRO ou DEBITO. |
| `situacao` | `character varying(10)` | não | `'EFETIVO'::character varying` | EFETIVO ou ESTORNADO. |
| `data_estorno` | `date` | sim |  | Data do estorno (devolução do valor pelo credor). |
| `motivo_estorno` | `character varying(200)` | sim |  | Justificativa do estorno. |
| `observacao` | `character varying(200)` | sim |  | Observação livre. |
| `criado_em` | `timestamp with time zone` | não | `now()` | Data e hora técnica do registro. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_pagamento_desconto` | `CHECK (((valor_desconto >= (0)::numeric) AND (valor_desconto < (valor_principal + valor_juros_multa))))` |
| `ck_pagamento_estorno` | `CHECK (((((situacao)::text = 'EFETIVO'::text) AND (data_estorno IS NULL) AND (motivo_estorno IS NULL)) OR (((situacao)::text = 'ESTORNADO'::text) AND (data_estorno >= data_pagamento) AND (motivo_estorno IS NOT NULL))))` |
| `ck_pagamento_forma` | `CHECK (((forma_pagamento)::text = ANY ((ARRAY['PIX'::character varying, 'TED'::character varying, 'BOLETO'::character varying, 'DINHEIRO'::character varying, 'DEBITO'::character varying])::text[])))` |
| `ck_pagamento_juros` | `CHECK ((valor_juros_multa >= (0)::numeric))` |
| `ck_pagamento_principal` | `CHECK ((valor_principal > (0)::numeric))` |
| `ck_pagamento_situacao` | `CHECK (((situacao)::text = ANY ((ARRAY['EFETIVO'::character varying, 'ESTORNADO'::character varying])::text[])))` |
| `fk_pagamento_conta` | `FOREIGN KEY (conta_bancaria_id) REFERENCES fastcar.conta_bancaria(id)` |
| `fk_pagamento_titulo` | `FOREIGN KEY (titulo_pagar_id) REFERENCES fastcar.titulo_pagar(id)` |
| `pk_pagamento` | `PRIMARY KEY (id)` |

**Índices adicionais**

| Nome | Definição |
|---|---|
| `ix_pagamento_data` | `INDEX ix_pagamento_data ON pagamento USING btree (data_pagamento)` |
| `ix_pagamento_titulo` | `INDEX ix_pagamento_titulo ON pagamento USING btree (titulo_pagar_id) INCLUDE (valor_principal, situacao)` |

**Gatilhos:** `tg_pagamento_sem_exclusao` → `fn_tg_bloqueia_exclusao`, `tg_pagamento_valida` → `fn_tg_pagamento_valida`

### transferencia

Transferência entre contas próprias. Gera uma saída e uma entrada; não é receita nem despesa.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `bigint` | não | identidade | Identificador interno. |
| `conta_origem_id` | `smallint` | não |  | Conta debitada. |
| `conta_destino_id` | `smallint` | não |  | Conta creditada (diferente da origem). |
| `data_transferencia` | `date` | não |  | Data da transferência. |
| `valor` | `numeric(14,2)` | não |  | Valor transferido. |
| `descricao` | `character varying(150)` | não |  | Descrição. |
| `criado_em` | `timestamp with time zone` | não | `now()` | Data e hora técnica do registro. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_transferencia_contas` | `CHECK ((conta_origem_id <> conta_destino_id))` |
| `ck_transferencia_valor` | `CHECK ((valor > (0)::numeric))` |
| `fk_transferencia_destino` | `FOREIGN KEY (conta_destino_id) REFERENCES fastcar.conta_bancaria(id)` |
| `fk_transferencia_origem` | `FOREIGN KEY (conta_origem_id) REFERENCES fastcar.conta_bancaria(id)` |
| `pk_transferencia` | `PRIMARY KEY (id)` |

**Gatilhos:** `tg_transferencia_imutavel` → `fn_tg_bloqueia_alteracao`

### movimento_bancario

Extrato de todas as contas: fonte única do regime de caixa. Imutável: correções são feitas por estorno.

| Coluna | Tipo | Nulo | Padrão | Descrição |
|---|---|---|---|---|
| `id` | `bigint` | não | identidade | Identificador interno. |
| `conta_bancaria_id` | `smallint` | não |  | Conta movimentada. |
| `data_movimento` | `date` | não |  | Data do crédito ou débito. |
| `tipo` | `character varying(7)` | não |  | ENTRADA ou SAIDA. |
| `natureza` | `character varying(20)` | não |  | RECEBIMENTO, ESTORNO_RECEBIMENTO, PAGAMENTO, ESTORNO_PAGAMENTO ou TRANSFERENCIA. |
| `valor` | `numeric(14,2)` | não |  | Valor sempre positivo; o sentido vem de tipo. |
| `historico` | `character varying(200)` | não |  | Texto do extrato. |
| `recebimento_id` | `bigint` | sim |  | Recebimento de origem. |
| `pagamento_id` | `bigint` | sim |  | Pagamento de origem. |
| `transferencia_id` | `bigint` | sim |  | Transferência de origem. |
| `criado_em` | `timestamp with time zone` | não | `now()` | Data e hora técnica do registro. |

**Restrições**

| Nome | Definição |
|---|---|
| `ck_movimento_bancario_natureza` | `CHECK (((((natureza)::text = 'RECEBIMENTO'::text) AND ((tipo)::text = 'ENTRADA'::text) AND (recebimento_id IS NOT NULL)) OR (((natureza)::text = 'ESTORNO_RECEBIMENTO'::text) AND ((tipo)::text = 'SAIDA'::text) AND (recebimento_id IS NOT NULL)) OR (((natureza)::text = 'PAGAMENTO'::text) AND ((tipo)::text = 'SAIDA'::text) AND (pagamento_id IS NOT NULL)) OR (((natureza)::text = 'ESTORNO_PAGAMENTO'::text) AND ((tipo)::text = 'ENTRADA'::text) AND (pagamento_id IS NOT NULL)) OR (((natureza)::text = 'TRANSFERENCIA'::text) AND (transferencia_id IS NOT NULL))))` |
| `ck_movimento_bancario_origem` | `CHECK ((num_nonnulls(recebimento_id, pagamento_id, transferencia_id) = 1))` |
| `ck_movimento_bancario_tipo` | `CHECK (((tipo)::text = ANY ((ARRAY['ENTRADA'::character varying, 'SAIDA'::character varying])::text[])))` |
| `ck_movimento_bancario_valor` | `CHECK ((valor > (0)::numeric))` |
| `fk_movimento_bancario_conta` | `FOREIGN KEY (conta_bancaria_id) REFERENCES fastcar.conta_bancaria(id)` |
| `fk_movimento_bancario_pagamento` | `FOREIGN KEY (pagamento_id) REFERENCES fastcar.pagamento(id)` |
| `fk_movimento_bancario_recebimento` | `FOREIGN KEY (recebimento_id) REFERENCES fastcar.recebimento(id)` |
| `fk_movimento_bancario_transferencia` | `FOREIGN KEY (transferencia_id) REFERENCES fastcar.transferencia(id)` |
| `pk_movimento_bancario` | `PRIMARY KEY (id)` |
| `uq_movimento_bancario_pagamento` | `UNIQUE (pagamento_id, natureza)` |
| `uq_movimento_bancario_recebimento` | `UNIQUE (recebimento_id, natureza)` |
| `uq_movimento_bancario_transferencia` | `UNIQUE (transferencia_id, tipo)` |

**Índices adicionais**

| Nome | Definição |
|---|---|
| `ix_movimento_bancario_conta_data` | `INDEX ix_movimento_bancario_conta_data ON movimento_bancario USING btree (conta_bancaria_id, data_movimento)` |
| `ix_movimento_bancario_data` | `INDEX ix_movimento_bancario_data ON movimento_bancario USING btree (data_movimento)` |

**Gatilhos:** `tg_movimento_bancario_imutavel` → `fn_tg_bloqueia_alteracao`, `tg_movimento_bancario_valida` → `fn_tg_movimento_bancario_valida`

## Views

| View | Descrição |
|---|---|
| `vw_contas_pagar_aberto` | Títulos a pagar com saldo em aberto na data de referência (VENCIDO ou A_VENCER), já descontados os pagamentos parciais. |
| `vw_contas_receber_aberto` | Títulos a receber com saldo em aberto na data de referência (VENCIDO ou A_VENCER), já descontados os recebimentos parciais. |
| `vw_despesas_categoria_centro` | Despesas operacionais por mês de competência, categoria e centro de custo (valores positivos, líquidos de cancelamentos). |
| `vw_dre_comparativo_mensal` | Evolução mensal do resultado (competência) e comparação com a geração de caixa do mês. |
| `vw_dre_mensal` | DRE gerencial mensal (competência). Custos e despesas com sinal negativo. |
| `vw_estoque_mensal` | Quantidade e valor de custo do estoque no último dia de cada mês. |
| `vw_estoque_veiculos` | Estoque na data de referência: custo de cada veículo, dias parado e margem potencial pelo preço anunciado. |
| `vw_fluxo_caixa_diario` | Fluxo de caixa diário consolidado de janeiro até a data de referência. |
| `vw_fluxo_caixa_mensal` | Fluxo de caixa mensal consolidado por grupo (valores com sinal: negativos são saídas). Transferências líquidas somam zero. |
| `vw_fluxo_caixa_mensal_grupo` | Fluxo de caixa mensal por grupo (recebimento de vendas, aquisição de veículos, despesas etc.). Valores incluem estornos. |
| `vw_inadimplencia_cliente` | Saldo vencido por cliente e faixa de atraso na data de referência. |
| `vw_inadimplencia_faixa` | Inadimplência por faixa de atraso e participação na carteira a receber em aberto. |
| `vw_lancamento_competencia` | Razão gerencial do regime de competência. Fonte única da DRE. Não contém compras de veículos, custos capitalizados, parcelas, recebimentos de principal nem transferências. |
| `vw_margem_veiculo_vendido` | Margem por veículo vendido (vendas ativas): lucro bruto = venda - custo total; margem de contribuição desconta a comissão. |
| `vw_mes_analise` | Meses analisados: do primeiro mês após o saldo inicial até o mês da data de referência. |
| `vw_movimento_caixa` | Extrato de todas as contas com sinal (+ entrada, - saída), categoria, centro de custo e grupo de fluxo. Estornos aparecem no sentido contrário, na data do estorno. |
| `vw_pagamentos_categoria_centro` | Saídas de caixa por mês de pagamento, categoria e centro de custo (líquidas de estornos, com juros). |
| `vw_resumo_contas_aberto` | Totais em aberto a receber e a pagar, separados em VENCIDO e A_VENCER. |
| `vw_resumo_financeiro_mensal` | Resumo de caixa consolidado por mês. Transferências internas somam zero no consolidado. |
| `vw_resumo_financeiro_mensal_conta` | Resumo de caixa mês a mês por conta, com linha TOTAL consolidada. |
| `vw_vendas_comissoes_vendedor` | Vendas, faturamento, lucro bruto e comissões por vendedor e mês da venda. Vendas canceladas são contadas à parte e não geram comissão devida. |

## Funções

| Função | Descrição |
|---|---|
| `fn_cancelar_titulo_pagar(p_documento text, p_numero_parcela integer, p_data date, p_motivo text)` | Cancela título a pagar sem pagamentos efetivos. A despesa é revertida na DRE no mês do cancelamento. |
| `fn_cancelar_titulo_receber(p_documento text, p_numero_parcela integer, p_data date, p_motivo text)` | Cancela título a receber avulso sem recebimentos efetivos. Parcelas de venda só são canceladas via fn_cancelar_venda. |
| `fn_cancelar_venda(p_numero_venda text, p_data date, p_motivo text)` | Cancela a venda: estorna recebimentos (devolução), cancela parcelas e comissão e devolve o veículo ao estoque. |
| `fn_custo_veiculo(p_veiculo_id integer, p_data date)` | Custo do veículo (aquisição + custos adicionais) acumulado até a data informada. |
| `fn_data_referencia()` | Data de referência dos relatórios (tabela configuracao). Usa a data atual se não configurada. |
| `fn_disponibilizar_veiculo(p_chassi text)` | Libera para venda um veículo EM_PREPARACAO (passa a DISPONIVEL). |
| `fn_dre(p_inicio date, p_fim date)` | DRE gerencial simplificada (regime de competência) para qualquer período. Valores negativos reduzem o resultado. |
| `fn_estoque_veiculos(p_data date)` | Veículos em estoque em uma data e seu custo (aquisição + custos adicionais até a data). |
| `fn_estornar_pagamento(p_pagamento_id bigint, p_data date, p_motivo text)` | Estorna um pagamento: marca como ESTORNADO e gera entrada na mesma conta. O saldo do título volta a ficar em aberto. |
| `fn_estornar_recebimento(p_recebimento_id bigint, p_data date, p_motivo text)` | Estorna um recebimento: marca como ESTORNADO e gera saída na mesma conta. O saldo do título volta a ficar em aberto. |
| `fn_faixa_atraso(p_dias integer)` | Classifica dias de atraso em faixas: A vencer, 01-30, 31-60, 61-90 e acima de 90 dias. |
| `fn_fluxo_caixa_diario(p_inicio date, p_fim date)` | Fluxo de caixa diário consolidado (dias com movimento), com saldo acumulado de todas as contas. |
| `fn_gerar_titulos_pagar(p_documento text, p_descricao text, p_categoria_id integer, p_centro_custo_id smallint, p_fornecedor_id integer, p_vendedor_id integer, p_compra_veiculo_id integer, p_custo_veiculo_id bigint, p_venda_id integer, p_data_emissao date, p_data_competencia date, p_primeiro_venc date, p_valor_total numeric, p_parcelas integer)` | Gera parcelas mensais de um título a pagar; a última parcela absorve a diferença de arredondamento. |
| `fn_id_categoria(p_codigo text)` | Retorna o id da categoria ativa pelo código; erro se não existir. |
| `fn_id_centro_custo(p_codigo text)` | Retorna o id do centro de custo ativo pelo código; erro se não existir. |
| `fn_id_cliente(p_documento text)` | Retorna o id do cliente pelo CPF/CNPJ; erro se não existir. |
| `fn_id_conta(p_codigo text)` | Retorna o id da conta bancária ativa pelo código; erro se não existir. |
| `fn_id_fornecedor(p_documento text)` | Retorna o id do fornecedor pelo CPF/CNPJ (nulo se o documento for nulo); erro se não existir. |
| `fn_id_veiculo(p_chassi text)` | Retorna o id do veículo pelo chassi; erro se não existir. |
| `fn_lancar_conta_pagar(p_documento text, p_descricao text, p_categoria text, p_centro_custo text, p_fornecedor_documento text, p_data_competencia date, p_primeiro_vencimento date, p_valor_total numeric, p_parcelas integer, p_data_emissao date)` | Lança despesa operacional em uma ou mais parcelas mensais. A despesa vai à DRE pela data de competência. |
| `fn_lancar_conta_receber(p_documento text, p_descricao text, p_categoria text, p_centro_custo text, p_cliente_documento text, p_data_competencia date, p_data_vencimento date, p_valor numeric)` | Lança conta a receber que não vem de venda de veículo (ex.: serviço de despachante). Vai à DRE pela competência. |
| `fn_posicao_contas_pagar(p_data_base date)` | Posição de cada título a pagar em uma data-base: valor, pago, saldo, dias de atraso, situação e faixa. |
| `fn_posicao_contas_receber(p_data_base date)` | Posição de cada título a receber em uma data-base: valor, recebido, saldo, dias de atraso, situação e faixa. |
| `fn_registrar_compra_veiculo(p_numero_compra text, p_fornecedor_documento text, p_data_compra date, p_valor_compra numeric, p_parcelas integer, p_primeiro_vencimento date, p_chassi text, p_placa text, p_renavam text, p_marca text, p_modelo text, p_versao text, p_ano_fabricacao integer, p_ano_modelo integer, p_cor text, p_quilometragem integer, p_preco_anunciado numeric)` | Cadastra o veículo (EM_PREPARACAO), registra a compra e gera os títulos a pagar. O valor vai para o estoque, não para a DRE. |
| `fn_registrar_custo_veiculo(p_documento text, p_chassi text, p_fornecedor_documento text, p_tipo text, p_descricao text, p_data_custo date, p_valor numeric, p_data_vencimento date)` | Registra custo adicional capitalizado no veículo em estoque e o título a pagar correspondente. |
| `fn_registrar_pagamento(p_documento text, p_numero_parcela integer, p_data date, p_conta text, p_valor_principal numeric, p_juros_multa numeric, p_desconto numeric, p_forma text, p_observacao text)` | Baixa total ou parcial de título a pagar e movimento bancário de saída (principal + juros/multa - desconto). |
| `fn_registrar_recebimento(p_documento text, p_numero_parcela integer, p_data date, p_conta text, p_valor_principal numeric, p_juros_multa numeric, p_desconto numeric, p_forma text, p_observacao text)` | Baixa total ou parcial de título a receber e movimento bancário de entrada (principal + juros/multa - desconto). |
| `fn_registrar_transferencia(p_conta_origem text, p_conta_destino text, p_data date, p_valor numeric, p_descricao text)` | Transferência entre contas próprias: uma saída na origem e uma entrada no destino. Não afeta a DRE. |
| `fn_registrar_venda(p_numero_venda text, p_chassi text, p_cliente_documento text, p_vendedor_cpf text, p_data_venda date, p_valor_venda numeric, p_valor_entrada numeric, p_parcelas integer, p_primeiro_vencimento date)` | Registra a venda (receita e CMV por competência), a entrada/parcelas a receber e o título de comissão. Não movimenta caixa. |
| `fn_resumo_financeiro(p_inicio date, p_fim date)` | Resumo de caixa do período por conta e TOTAL: saldo inicial, entradas, saídas, transferências e saldo final. |
| `fn_saldo_contas(p_data date)` | Saldo de cada conta ao final do dia informado (saldo inicial + movimentos até a data). |
| `fn_saldo_titulo_pagar(p_titulo_id bigint)` | Saldo em aberto do título a pagar: valor - principal das baixas efetivas. |
| `fn_saldo_titulo_receber(p_titulo_id bigint)` | Saldo em aberto do título a receber: valor - principal das baixas efetivas. |

Funções de gatilho (`fn_tg_*`) estão listadas junto de cada tabela. Funções sem descrição são auxiliares; veja os comentários em `sql/02_functions.sql`.
