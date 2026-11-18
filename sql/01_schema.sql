-- =============================================================================
-- Fast Car - Sistema Financeiro em SQL
-- Arquivo : sql/01_schema.sql
-- Objetivo: criar o schema "fastcar" com tabelas, restrições e índices.
-- Banco   : PostgreSQL 16 (testado em 16.15)
--
-- ATENÇÃO: este script REMOVE e recria o schema "fastcar" (DROP SCHEMA IF EXISTS fastcar CASCADE).
--          Execute-o somente em um banco de demonstração.
--
-- Convenções:
--   * nomes em português, minúsculos, snake_case e sem acentos;
--   * tabelas no singular (cliente, venda, titulo_pagar);
--   * chave primária "id"; chave estrangeira "<tabela>_id";
--   * restrições nomeadas: pk_, fk_, uq_, ck_; índices: ix_ (comum) e uq_ (único);
--   * valores monetários em numeric(14,2); percentuais em numeric(5,2);
--   * datas de negócio em date; auditoria técnica em timestamptz.
-- =============================================================================

\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS fastcar CASCADE;
CREATE SCHEMA fastcar;
COMMENT ON SCHEMA fastcar IS 'Sistema financeiro gerencial da concessionária fictícia Fast Car.';

SET search_path TO fastcar, public;

-- -----------------------------------------------------------------------------
-- Configuração
-- -----------------------------------------------------------------------------
CREATE TABLE configuracao (
    id               smallint    NOT NULL DEFAULT 1,
    data_referencia  date        NOT NULL,
    descricao        varchar(200),
    CONSTRAINT pk_configuracao PRIMARY KEY (id),
    CONSTRAINT ck_configuracao_linha_unica CHECK (id = 1)
);
COMMENT ON TABLE configuracao IS 'Parâmetros globais (linha única). Guarda a data de referência usada por relatórios de vencimento e estoque.';
COMMENT ON COLUMN configuracao.id IS 'Sempre 1: garante uma única linha de configuração.';
COMMENT ON COLUMN configuracao.data_referencia IS 'Data-base dos relatórios (vencidos, a vencer, dias em estoque). Fixada para tornar exemplos e testes reproduzíveis.';
COMMENT ON COLUMN configuracao.descricao IS 'Observação livre sobre a configuração.';

-- -----------------------------------------------------------------------------
-- Cadastros de apoio
-- -----------------------------------------------------------------------------
CREATE TABLE centro_custo (
    id      smallint    GENERATED ALWAYS AS IDENTITY,
    codigo  varchar(10) NOT NULL,
    nome    varchar(60) NOT NULL,
    ativo   boolean     NOT NULL DEFAULT true,
    CONSTRAINT pk_centro_custo PRIMARY KEY (id),
    CONSTRAINT uq_centro_custo_codigo UNIQUE (codigo),
    CONSTRAINT uq_centro_custo_nome UNIQUE (nome),
    CONSTRAINT ck_centro_custo_codigo CHECK (codigo ~ '^[A-Z]{2,10}$')
);
COMMENT ON TABLE centro_custo IS 'Áreas da empresa às quais receitas e despesas são atribuídas (ex.: Administrativo, Comercial, Oficina).';
COMMENT ON COLUMN centro_custo.id IS 'Identificador interno.';
COMMENT ON COLUMN centro_custo.codigo IS 'Código curto em maiúsculas (ex.: ADM, COM, OFI).';
COMMENT ON COLUMN centro_custo.nome IS 'Nome do centro de custo.';
COMMENT ON COLUMN centro_custo.ativo IS 'Indica se o centro de custo aceita novos lançamentos.';

CREATE TABLE categoria_financeira (
    id         integer     GENERATED ALWAYS AS IDENTITY,
    codigo     varchar(10) NOT NULL,
    nome       varchar(80) NOT NULL,
    natureza   varchar(10) NOT NULL,
    grupo_dre  varchar(30),
    ativo      boolean     NOT NULL DEFAULT true,
    CONSTRAINT pk_categoria_financeira PRIMARY KEY (id),
    CONSTRAINT uq_categoria_financeira_codigo UNIQUE (codigo),
    CONSTRAINT uq_categoria_financeira_nome UNIQUE (nome),
    CONSTRAINT ck_categoria_financeira_natureza CHECK (natureza IN ('RECEITA', 'DESPESA', 'ESTOQUE')),
    CONSTRAINT ck_categoria_financeira_grupo_dre CHECK (
        grupo_dre IN ('OUTRAS_RECEITAS', 'DESPESA_VENDAS', 'DESPESA_PESSOAL', 'DESPESA_ADMINISTRATIVA')),
    CONSTRAINT ck_categoria_financeira_grupo_coerente CHECK (
           (natureza = 'ESTOQUE' AND grupo_dre IS NULL)
        OR (natureza = 'DESPESA' AND grupo_dre IN ('DESPESA_VENDAS', 'DESPESA_PESSOAL', 'DESPESA_ADMINISTRATIVA'))
        OR (natureza = 'RECEITA' AND (grupo_dre IS NULL OR grupo_dre = 'OUTRAS_RECEITAS')))
);
COMMENT ON TABLE categoria_financeira IS 'Plano de categorias. A natureza define o tratamento: RECEITA, DESPESA (vai à DRE pelo grupo_dre) ou ESTOQUE (ativo; só chega à DRE como CMV quando o veículo é vendido).';
COMMENT ON COLUMN categoria_financeira.id IS 'Identificador interno.';
COMMENT ON COLUMN categoria_financeira.codigo IS 'Código hierárquico (ex.: 3.04). Os códigos 1.01, 2.01, 2.02 e 3.01 são usados pelas funções do sistema.';
COMMENT ON COLUMN categoria_financeira.nome IS 'Nome da categoria.';
COMMENT ON COLUMN categoria_financeira.natureza IS 'RECEITA, DESPESA ou ESTOQUE.';
COMMENT ON COLUMN categoria_financeira.grupo_dre IS 'Linha da DRE gerencial. Nulo para ESTOQUE e para a receita de venda de veículos (reconhecida a partir da tabela venda).';
COMMENT ON COLUMN categoria_financeira.ativo IS 'Indica se a categoria aceita novos lançamentos.';

CREATE TABLE cliente (
    id             integer      GENERATED ALWAYS AS IDENTITY,
    tipo_pessoa    char(1)      NOT NULL,
    nome           varchar(120) NOT NULL,
    documento      varchar(14)  NOT NULL,
    email          varchar(120),
    telefone       varchar(20),
    cidade         varchar(60),
    uf             char(2),
    data_cadastro  date         NOT NULL,
    CONSTRAINT pk_cliente PRIMARY KEY (id),
    CONSTRAINT uq_cliente_documento UNIQUE (documento),
    CONSTRAINT ck_cliente_tipo_pessoa CHECK (tipo_pessoa IN ('F', 'J')),
    CONSTRAINT ck_cliente_documento CHECK (
           (tipo_pessoa = 'F' AND documento ~ '^[0-9]{11}$')
        OR (tipo_pessoa = 'J' AND documento ~ '^[0-9]{14}$')),
    CONSTRAINT ck_cliente_email CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    CONSTRAINT ck_cliente_uf CHECK (uf ~ '^[A-Z]{2}$')
);
COMMENT ON TABLE cliente IS 'Compradores de veículos e devedores de contas a receber.';
COMMENT ON COLUMN cliente.id IS 'Identificador interno.';
COMMENT ON COLUMN cliente.tipo_pessoa IS 'F = pessoa física (CPF), J = pessoa jurídica (CNPJ).';
COMMENT ON COLUMN cliente.nome IS 'Nome ou razão social.';
COMMENT ON COLUMN cliente.documento IS 'CPF (11 dígitos) ou CNPJ (14 dígitos), somente números. Dígitos verificadores não são validados (dados sintéticos).';
COMMENT ON COLUMN cliente.email IS 'E-mail de contato.';
COMMENT ON COLUMN cliente.telefone IS 'Telefone de contato.';
COMMENT ON COLUMN cliente.cidade IS 'Cidade.';
COMMENT ON COLUMN cliente.uf IS 'Unidade federativa (sigla).';
COMMENT ON COLUMN cliente.data_cadastro IS 'Data do cadastro.';

CREATE TABLE fornecedor (
    id             integer      GENERATED ALWAYS AS IDENTITY,
    tipo_pessoa    char(1)      NOT NULL,
    nome           varchar(120) NOT NULL,
    documento      varchar(14)  NOT NULL,
    ramo           varchar(60)  NOT NULL,
    email          varchar(120),
    telefone       varchar(20),
    data_cadastro  date         NOT NULL,
    CONSTRAINT pk_fornecedor PRIMARY KEY (id),
    CONSTRAINT uq_fornecedor_documento UNIQUE (documento),
    CONSTRAINT ck_fornecedor_tipo_pessoa CHECK (tipo_pessoa IN ('F', 'J')),
    CONSTRAINT ck_fornecedor_documento CHECK (
           (tipo_pessoa = 'F' AND documento ~ '^[0-9]{11}$')
        OR (tipo_pessoa = 'J' AND documento ~ '^[0-9]{14}$')),
    CONSTRAINT ck_fornecedor_email CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
);
COMMENT ON TABLE fornecedor IS 'Quem vende veículos para a loja e quem presta serviços ou fornece bens (oficinas, despachantes, imobiliária etc.).';
COMMENT ON COLUMN fornecedor.id IS 'Identificador interno.';
COMMENT ON COLUMN fornecedor.tipo_pessoa IS 'F = pessoa física, J = pessoa jurídica.';
COMMENT ON COLUMN fornecedor.nome IS 'Nome ou razão social.';
COMMENT ON COLUMN fornecedor.documento IS 'CPF ou CNPJ, somente números.';
COMMENT ON COLUMN fornecedor.ramo IS 'Ramo de atividade (ex.: Oficina mecânica, Despachante).';
COMMENT ON COLUMN fornecedor.email IS 'E-mail de contato.';
COMMENT ON COLUMN fornecedor.telefone IS 'Telefone de contato.';
COMMENT ON COLUMN fornecedor.data_cadastro IS 'Data do cadastro.';

CREATE TABLE vendedor (
    id                   integer      GENERATED ALWAYS AS IDENTITY,
    nome                 varchar(120) NOT NULL,
    cpf                  char(11)     NOT NULL,
    email                varchar(120),
    percentual_comissao  numeric(5,2) NOT NULL,
    data_admissao        date         NOT NULL,
    ativo                boolean      NOT NULL DEFAULT true,
    CONSTRAINT pk_vendedor PRIMARY KEY (id),
    CONSTRAINT uq_vendedor_cpf UNIQUE (cpf),
    CONSTRAINT ck_vendedor_cpf CHECK (cpf ~ '^[0-9]{11}$'),
    CONSTRAINT ck_vendedor_percentual_comissao CHECK (percentual_comissao BETWEEN 0 AND 10),
    CONSTRAINT ck_vendedor_email CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
);
COMMENT ON TABLE vendedor IS 'Equipe comercial que recebe comissão sobre vendas.';
COMMENT ON COLUMN vendedor.id IS 'Identificador interno.';
COMMENT ON COLUMN vendedor.nome IS 'Nome do vendedor.';
COMMENT ON COLUMN vendedor.cpf IS 'CPF, somente números.';
COMMENT ON COLUMN vendedor.email IS 'E-mail corporativo.';
COMMENT ON COLUMN vendedor.percentual_comissao IS 'Percentual de comissão vigente (0 a 10). É copiado para a venda no momento do registro.';
COMMENT ON COLUMN vendedor.data_admissao IS 'Data de admissão.';
COMMENT ON COLUMN vendedor.ativo IS 'Indica se pode registrar novas vendas.';

CREATE TABLE conta_bancaria (
    id                  smallint      GENERATED ALWAYS AS IDENTITY,
    codigo              varchar(10)   NOT NULL,
    descricao           varchar(60)   NOT NULL,
    tipo                varchar(10)   NOT NULL,
    banco               varchar(60),
    agencia             varchar(10),
    numero_conta        varchar(20),
    saldo_inicial       numeric(14,2) NOT NULL,
    data_saldo_inicial  date          NOT NULL,
    ativo               boolean       NOT NULL DEFAULT true,
    CONSTRAINT pk_conta_bancaria PRIMARY KEY (id),
    CONSTRAINT uq_conta_bancaria_codigo UNIQUE (codigo),
    CONSTRAINT uq_conta_bancaria_numero UNIQUE (banco, agencia, numero_conta),
    CONSTRAINT ck_conta_bancaria_tipo CHECK (tipo IN ('CORRENTE', 'CAIXA', 'APLICACAO')),
    CONSTRAINT ck_conta_bancaria_dados_banco CHECK (
        tipo = 'CAIXA' OR (banco IS NOT NULL AND agencia IS NOT NULL AND numero_conta IS NOT NULL))
);
COMMENT ON TABLE conta_bancaria IS 'Contas próprias da empresa (bancos, caixa físico, aplicações).';
COMMENT ON COLUMN conta_bancaria.id IS 'Identificador interno.';
COMMENT ON COLUMN conta_bancaria.codigo IS 'Código curto usado nas funções (ex.: BCO_A).';
COMMENT ON COLUMN conta_bancaria.descricao IS 'Descrição da conta.';
COMMENT ON COLUMN conta_bancaria.tipo IS 'CORRENTE, CAIXA ou APLICACAO.';
COMMENT ON COLUMN conta_bancaria.banco IS 'Nome do banco (fictício).';
COMMENT ON COLUMN conta_bancaria.agencia IS 'Agência.';
COMMENT ON COLUMN conta_bancaria.numero_conta IS 'Número da conta.';
COMMENT ON COLUMN conta_bancaria.saldo_inicial IS 'Saldo no fim do dia data_saldo_inicial, ponto de partida da conciliação.';
COMMENT ON COLUMN conta_bancaria.data_saldo_inicial IS 'Data do saldo inicial. Movimentos só são aceitos após essa data.';
COMMENT ON COLUMN conta_bancaria.ativo IS 'Indica se a conta aceita movimentos.';

-- -----------------------------------------------------------------------------
-- Veículos, compras e custos
-- -----------------------------------------------------------------------------
CREATE TABLE veiculo (
    id               integer       GENERATED ALWAYS AS IDENTITY,
    chassi           char(17)      NOT NULL,
    placa            varchar(7),
    renavam          char(11),
    marca            varchar(40)   NOT NULL,
    modelo           varchar(60)   NOT NULL,
    versao           varchar(60),
    ano_fabricacao   smallint      NOT NULL,
    ano_modelo       smallint      NOT NULL,
    cor              varchar(30),
    quilometragem    integer       NOT NULL,
    situacao         varchar(15)   NOT NULL DEFAULT 'EM_PREPARACAO',
    preco_anunciado  numeric(14,2),
    CONSTRAINT pk_veiculo PRIMARY KEY (id),
    CONSTRAINT uq_veiculo_chassi UNIQUE (chassi),
    CONSTRAINT uq_veiculo_placa UNIQUE (placa),
    CONSTRAINT uq_veiculo_renavam UNIQUE (renavam),
    CONSTRAINT ck_veiculo_chassi CHECK (chassi ~ '^[A-HJ-NPR-Z0-9]{17}$'),
    CONSTRAINT ck_veiculo_placa CHECK (placa ~ '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$'),
    CONSTRAINT ck_veiculo_renavam CHECK (renavam ~ '^[0-9]{11}$'),
    CONSTRAINT ck_veiculo_ano_fabricacao CHECK (ano_fabricacao BETWEEN 1980 AND 2100),
    CONSTRAINT ck_veiculo_ano_modelo CHECK (ano_modelo BETWEEN ano_fabricacao AND ano_fabricacao + 1),
    CONSTRAINT ck_veiculo_quilometragem CHECK (quilometragem >= 0),
    CONSTRAINT ck_veiculo_situacao CHECK (situacao IN ('EM_PREPARACAO', 'DISPONIVEL', 'VENDIDO')),
    CONSTRAINT ck_veiculo_preco_anunciado CHECK (preco_anunciado > 0)
);
COMMENT ON TABLE veiculo IS 'Veículos que passaram pelo estoque. A situação é controlada por gatilhos a partir das vendas.';
COMMENT ON COLUMN veiculo.id IS 'Identificador interno.';
COMMENT ON COLUMN veiculo.chassi IS 'Número de chassi (VIN) com 17 caracteres, sem I, O e Q. Identificação única do veículo.';
COMMENT ON COLUMN veiculo.placa IS 'Placa no padrão Mercosul ou antigo, sem hífen.';
COMMENT ON COLUMN veiculo.renavam IS 'Código RENAVAM com 11 dígitos.';
COMMENT ON COLUMN veiculo.marca IS 'Marca.';
COMMENT ON COLUMN veiculo.modelo IS 'Modelo.';
COMMENT ON COLUMN veiculo.versao IS 'Versão/acabamento.';
COMMENT ON COLUMN veiculo.ano_fabricacao IS 'Ano de fabricação.';
COMMENT ON COLUMN veiculo.ano_modelo IS 'Ano do modelo (igual ou um ano após a fabricação).';
COMMENT ON COLUMN veiculo.cor IS 'Cor.';
COMMENT ON COLUMN veiculo.quilometragem IS 'Quilometragem na entrada do estoque.';
COMMENT ON COLUMN veiculo.situacao IS 'EM_PREPARACAO, DISPONIVEL ou VENDIDO.';
COMMENT ON COLUMN veiculo.preco_anunciado IS 'Preço de tabela anunciado (referência; o valor negociado fica na venda).';

CREATE TABLE compra_veiculo (
    id                   integer       GENERATED ALWAYS AS IDENTITY,
    numero_compra        varchar(20)   NOT NULL,
    veiculo_id           integer       NOT NULL,
    fornecedor_id        integer       NOT NULL,
    data_compra          date          NOT NULL,
    valor_compra         numeric(14,2) NOT NULL,
    quantidade_parcelas  smallint      NOT NULL DEFAULT 1,
    observacao           varchar(200),
    CONSTRAINT pk_compra_veiculo PRIMARY KEY (id),
    CONSTRAINT uq_compra_veiculo_numero UNIQUE (numero_compra),
    CONSTRAINT uq_compra_veiculo_veiculo UNIQUE (veiculo_id),
    CONSTRAINT fk_compra_veiculo_veiculo FOREIGN KEY (veiculo_id) REFERENCES veiculo (id),
    CONSTRAINT fk_compra_veiculo_fornecedor FOREIGN KEY (fornecedor_id) REFERENCES fornecedor (id),
    CONSTRAINT ck_compra_veiculo_valor CHECK (valor_compra > 0),
    CONSTRAINT ck_compra_veiculo_parcelas CHECK (quantidade_parcelas BETWEEN 1 AND 24)
);
COMMENT ON TABLE compra_veiculo IS 'Aquisição de veículo para estoque. É ativo (estoque), não despesa: só chega à DRE como CMV quando o veículo é vendido.';
COMMENT ON COLUMN compra_veiculo.id IS 'Identificador interno.';
COMMENT ON COLUMN compra_veiculo.numero_compra IS 'Número do documento de compra (ex.: C2026-001). Também é o documento dos títulos a pagar gerados.';
COMMENT ON COLUMN compra_veiculo.veiculo_id IS 'Veículo adquirido (uma compra por veículo).';
COMMENT ON COLUMN compra_veiculo.fornecedor_id IS 'Vendedor do veículo para a loja.';
COMMENT ON COLUMN compra_veiculo.data_compra IS 'Data de aquisição (entrada no estoque).';
COMMENT ON COLUMN compra_veiculo.valor_compra IS 'Custo de aquisição.';
COMMENT ON COLUMN compra_veiculo.quantidade_parcelas IS 'Número de parcelas a pagar ao fornecedor.';
COMMENT ON COLUMN compra_veiculo.observacao IS 'Observação livre.';

CREATE TABLE custo_veiculo (
    id             bigint        GENERATED ALWAYS AS IDENTITY,
    veiculo_id     integer       NOT NULL,
    fornecedor_id  integer       NOT NULL,
    tipo           varchar(15)   NOT NULL,
    descricao      varchar(150)  NOT NULL,
    data_custo     date          NOT NULL,
    valor          numeric(14,2) NOT NULL,
    CONSTRAINT pk_custo_veiculo PRIMARY KEY (id),
    CONSTRAINT fk_custo_veiculo_veiculo FOREIGN KEY (veiculo_id) REFERENCES veiculo (id),
    CONSTRAINT fk_custo_veiculo_fornecedor FOREIGN KEY (fornecedor_id) REFERENCES fornecedor (id),
    CONSTRAINT ck_custo_veiculo_tipo CHECK (tipo IN ('MANUTENCAO', 'DOCUMENTACAO', 'PREPARACAO', 'TRANSPORTE')),
    CONSTRAINT ck_custo_veiculo_valor CHECK (valor > 0)
);
COMMENT ON TABLE custo_veiculo IS 'Custos adicionais incorporados ao custo do veículo em estoque (manutenção, documentação, preparação, transporte). Entram no CMV na venda.';
COMMENT ON COLUMN custo_veiculo.id IS 'Identificador interno.';
COMMENT ON COLUMN custo_veiculo.veiculo_id IS 'Veículo que recebeu o custo.';
COMMENT ON COLUMN custo_veiculo.fornecedor_id IS 'Prestador do serviço.';
COMMENT ON COLUMN custo_veiculo.tipo IS 'MANUTENCAO, DOCUMENTACAO, PREPARACAO ou TRANSPORTE.';
COMMENT ON COLUMN custo_veiculo.descricao IS 'Descrição do serviço.';
COMMENT ON COLUMN custo_veiculo.data_custo IS 'Data em que o custo foi incorrido. Deve ser anterior à venda.';
COMMENT ON COLUMN custo_veiculo.valor IS 'Valor do custo.';

-- -----------------------------------------------------------------------------
-- Vendas
-- -----------------------------------------------------------------------------
CREATE TABLE venda (
    id                     integer       GENERATED ALWAYS AS IDENTITY,
    numero_venda           varchar(20)   NOT NULL,
    veiculo_id             integer       NOT NULL,
    cliente_id             integer       NOT NULL,
    vendedor_id            integer       NOT NULL,
    data_venda             date          NOT NULL,
    valor_venda            numeric(14,2) NOT NULL,
    valor_entrada          numeric(14,2) NOT NULL,
    quantidade_parcelas    smallint      NOT NULL,
    custo_veiculo_vendido  numeric(14,2) NOT NULL,
    percentual_comissao    numeric(5,2)  NOT NULL,
    valor_comissao         numeric(14,2) NOT NULL,
    situacao               varchar(10)   NOT NULL DEFAULT 'ATIVA',
    data_cancelamento      date,
    motivo_cancelamento    varchar(200),
    CONSTRAINT pk_venda PRIMARY KEY (id),
    CONSTRAINT uq_venda_numero UNIQUE (numero_venda),
    CONSTRAINT fk_venda_veiculo FOREIGN KEY (veiculo_id) REFERENCES veiculo (id),
    CONSTRAINT fk_venda_cliente FOREIGN KEY (cliente_id) REFERENCES cliente (id),
    CONSTRAINT fk_venda_vendedor FOREIGN KEY (vendedor_id) REFERENCES vendedor (id),
    CONSTRAINT ck_venda_valor CHECK (valor_venda > 0),
    CONSTRAINT ck_venda_entrada CHECK (valor_entrada >= 0 AND valor_entrada <= valor_venda),
    CONSTRAINT ck_venda_parcelas CHECK (
           (quantidade_parcelas = 0 AND valor_entrada = valor_venda)
        OR (quantidade_parcelas BETWEEN 1 AND 48 AND valor_entrada < valor_venda)),
    CONSTRAINT ck_venda_custo CHECK (custo_veiculo_vendido > 0),
    CONSTRAINT ck_venda_percentual_comissao CHECK (percentual_comissao BETWEEN 0 AND 10),
    CONSTRAINT ck_venda_comissao CHECK (valor_comissao = round(valor_venda * percentual_comissao / 100, 2)),
    CONSTRAINT ck_venda_situacao CHECK (situacao IN ('ATIVA', 'CANCELADA')),
    CONSTRAINT ck_venda_cancelamento CHECK (
           (situacao = 'ATIVA' AND data_cancelamento IS NULL AND motivo_cancelamento IS NULL)
        OR (situacao = 'CANCELADA' AND data_cancelamento >= data_venda AND motivo_cancelamento IS NOT NULL))
);
COMMENT ON TABLE venda IS 'Venda de veículo. Fonte única da receita bruta e do CMV na DRE. Cancelamentos são registrados, nunca apagados.';
COMMENT ON COLUMN venda.id IS 'Identificador interno.';
COMMENT ON COLUMN venda.numero_venda IS 'Número da venda (ex.: V2026-001). Também é o documento dos títulos a receber.';
COMMENT ON COLUMN venda.veiculo_id IS 'Veículo vendido. Só pode haver uma venda ATIVA por veículo.';
COMMENT ON COLUMN venda.cliente_id IS 'Comprador.';
COMMENT ON COLUMN venda.vendedor_id IS 'Vendedor responsável (recebe a comissão).';
COMMENT ON COLUMN venda.data_venda IS 'Data da venda: data de reconhecimento da receita e do CMV (competência).';
COMMENT ON COLUMN venda.valor_venda IS 'Valor total negociado.';
COMMENT ON COLUMN venda.valor_entrada IS 'Parte paga na data da venda (parcela 0). Igual ao valor da venda quando é à vista.';
COMMENT ON COLUMN venda.quantidade_parcelas IS 'Parcelas mensais após a entrada (0 = à vista).';
COMMENT ON COLUMN venda.custo_veiculo_vendido IS 'Fotografia do custo total (aquisição + custos adicionais) na data da venda; é o CMV reconhecido.';
COMMENT ON COLUMN venda.percentual_comissao IS 'Percentual de comissão copiado do vendedor na data da venda.';
COMMENT ON COLUMN venda.valor_comissao IS 'Comissão calculada (valor_venda x percentual / 100, arredondado em 2 casas).';
COMMENT ON COLUMN venda.situacao IS 'ATIVA ou CANCELADA.';
COMMENT ON COLUMN venda.data_cancelamento IS 'Data do cancelamento; a reversão de receita e CMV é reconhecida nesse mês.';
COMMENT ON COLUMN venda.motivo_cancelamento IS 'Justificativa do cancelamento.';

-- -----------------------------------------------------------------------------
-- Contas a receber e a pagar
-- -----------------------------------------------------------------------------
CREATE TABLE titulo_receber (
    id                   bigint        GENERATED ALWAYS AS IDENTITY,
    documento            varchar(30)   NOT NULL,
    numero_parcela       smallint      NOT NULL,
    total_parcelas       smallint      NOT NULL,
    cliente_id           integer       NOT NULL,
    venda_id             integer,
    categoria_id         integer       NOT NULL,
    centro_custo_id      smallint      NOT NULL,
    descricao            varchar(150)  NOT NULL,
    data_emissao         date          NOT NULL,
    data_competencia     date          NOT NULL,
    data_vencimento      date          NOT NULL,
    valor                numeric(14,2) NOT NULL,
    situacao             varchar(10)   NOT NULL DEFAULT 'ATIVO',
    data_cancelamento    date,
    motivo_cancelamento  varchar(200),
    CONSTRAINT pk_titulo_receber PRIMARY KEY (id),
    CONSTRAINT uq_titulo_receber_documento_parcela UNIQUE (documento, numero_parcela),
    CONSTRAINT fk_titulo_receber_cliente FOREIGN KEY (cliente_id) REFERENCES cliente (id),
    CONSTRAINT fk_titulo_receber_venda FOREIGN KEY (venda_id) REFERENCES venda (id),
    CONSTRAINT fk_titulo_receber_categoria FOREIGN KEY (categoria_id) REFERENCES categoria_financeira (id),
    CONSTRAINT fk_titulo_receber_centro_custo FOREIGN KEY (centro_custo_id) REFERENCES centro_custo (id),
    CONSTRAINT ck_titulo_receber_parcela CHECK (numero_parcela BETWEEN 0 AND total_parcelas AND total_parcelas BETWEEN 0 AND 48),
    CONSTRAINT ck_titulo_receber_parcela_zero CHECK (numero_parcela > 0 OR venda_id IS NOT NULL),
    CONSTRAINT ck_titulo_receber_valor CHECK (valor > 0),
    CONSTRAINT ck_titulo_receber_vencimento CHECK (data_vencimento >= data_emissao),
    CONSTRAINT ck_titulo_receber_situacao CHECK (situacao IN ('ATIVO', 'CANCELADO')),
    CONSTRAINT ck_titulo_receber_cancelamento CHECK (
           (situacao = 'ATIVO' AND data_cancelamento IS NULL AND motivo_cancelamento IS NULL)
        OR (situacao = 'CANCELADO' AND data_cancelamento >= data_emissao AND motivo_cancelamento IS NOT NULL))
);
COMMENT ON TABLE titulo_receber IS 'Contas a receber (uma linha por parcela). Representa o direito de receber; não é receita na DRE quando vem de venda de veículo.';
COMMENT ON COLUMN titulo_receber.id IS 'Identificador interno.';
COMMENT ON COLUMN titulo_receber.documento IS 'Documento de origem (número da venda ou código do serviço).';
COMMENT ON COLUMN titulo_receber.numero_parcela IS 'Número da parcela. 0 = entrada ou pagamento à vista de uma venda.';
COMMENT ON COLUMN titulo_receber.total_parcelas IS 'Quantidade de parcelas mensais do documento (sem contar a entrada).';
COMMENT ON COLUMN titulo_receber.cliente_id IS 'Devedor.';
COMMENT ON COLUMN titulo_receber.venda_id IS 'Venda de origem, quando houver.';
COMMENT ON COLUMN titulo_receber.categoria_id IS 'Categoria financeira (natureza RECEITA).';
COMMENT ON COLUMN titulo_receber.centro_custo_id IS 'Centro de custo responsável.';
COMMENT ON COLUMN titulo_receber.descricao IS 'Descrição do título.';
COMMENT ON COLUMN titulo_receber.data_emissao IS 'Data de emissão.';
COMMENT ON COLUMN titulo_receber.data_competencia IS 'Data do fato gerador (usada na DRE para receitas que não vêm de venda de veículo).';
COMMENT ON COLUMN titulo_receber.data_vencimento IS 'Data de vencimento.';
COMMENT ON COLUMN titulo_receber.valor IS 'Valor original da parcela.';
COMMENT ON COLUMN titulo_receber.situacao IS 'ATIVO ou CANCELADO. Situações como VENCIDO e QUITADO são calculadas nas consultas.';
COMMENT ON COLUMN titulo_receber.data_cancelamento IS 'Data do cancelamento.';
COMMENT ON COLUMN titulo_receber.motivo_cancelamento IS 'Justificativa do cancelamento.';

CREATE TABLE titulo_pagar (
    id                   bigint        GENERATED ALWAYS AS IDENTITY,
    documento            varchar(30)   NOT NULL,
    numero_parcela       smallint      NOT NULL,
    total_parcelas       smallint      NOT NULL,
    fornecedor_id        integer,
    vendedor_id          integer,
    categoria_id         integer       NOT NULL,
    centro_custo_id      smallint      NOT NULL,
    compra_veiculo_id    integer,
    custo_veiculo_id     bigint,
    venda_id             integer,
    descricao            varchar(150)  NOT NULL,
    data_emissao         date          NOT NULL,
    data_competencia     date          NOT NULL,
    data_vencimento      date          NOT NULL,
    valor                numeric(14,2) NOT NULL,
    situacao             varchar(10)   NOT NULL DEFAULT 'ATIVO',
    data_cancelamento    date,
    motivo_cancelamento  varchar(200),
    CONSTRAINT pk_titulo_pagar PRIMARY KEY (id),
    CONSTRAINT uq_titulo_pagar_documento_parcela UNIQUE (documento, numero_parcela),
    CONSTRAINT fk_titulo_pagar_fornecedor FOREIGN KEY (fornecedor_id) REFERENCES fornecedor (id),
    CONSTRAINT fk_titulo_pagar_vendedor FOREIGN KEY (vendedor_id) REFERENCES vendedor (id),
    CONSTRAINT fk_titulo_pagar_categoria FOREIGN KEY (categoria_id) REFERENCES categoria_financeira (id),
    CONSTRAINT fk_titulo_pagar_centro_custo FOREIGN KEY (centro_custo_id) REFERENCES centro_custo (id),
    CONSTRAINT fk_titulo_pagar_compra_veiculo FOREIGN KEY (compra_veiculo_id) REFERENCES compra_veiculo (id),
    CONSTRAINT fk_titulo_pagar_custo_veiculo FOREIGN KEY (custo_veiculo_id) REFERENCES custo_veiculo (id),
    CONSTRAINT fk_titulo_pagar_venda FOREIGN KEY (venda_id) REFERENCES venda (id),
    CONSTRAINT ck_titulo_pagar_favorecido CHECK (num_nonnulls(fornecedor_id, vendedor_id) <= 1),
    CONSTRAINT ck_titulo_pagar_origem CHECK (num_nonnulls(compra_veiculo_id, custo_veiculo_id, venda_id) <= 1),
    CONSTRAINT ck_titulo_pagar_comissao CHECK (venda_id IS NULL OR vendedor_id IS NOT NULL),
    CONSTRAINT ck_titulo_pagar_parcela CHECK (numero_parcela BETWEEN 1 AND total_parcelas AND total_parcelas <= 48),
    CONSTRAINT ck_titulo_pagar_valor CHECK (valor > 0),
    CONSTRAINT ck_titulo_pagar_vencimento CHECK (data_vencimento >= data_emissao),
    CONSTRAINT ck_titulo_pagar_situacao CHECK (situacao IN ('ATIVO', 'CANCELADO')),
    CONSTRAINT ck_titulo_pagar_cancelamento CHECK (
           (situacao = 'ATIVO' AND data_cancelamento IS NULL AND motivo_cancelamento IS NULL)
        OR (situacao = 'CANCELADO' AND data_cancelamento >= data_emissao AND motivo_cancelamento IS NOT NULL))
);
COMMENT ON TABLE titulo_pagar IS 'Contas a pagar (uma linha por parcela): compras de veículos, custos de veículos, comissões e despesas operacionais.';
COMMENT ON COLUMN titulo_pagar.id IS 'Identificador interno.';
COMMENT ON COLUMN titulo_pagar.documento IS 'Documento de origem (nota, contrato, número da compra, COM-<venda>, nota do custo de veículo).';
COMMENT ON COLUMN titulo_pagar.numero_parcela IS 'Número da parcela (1..total_parcelas).';
COMMENT ON COLUMN titulo_pagar.total_parcelas IS 'Quantidade de parcelas do documento.';
COMMENT ON COLUMN titulo_pagar.fornecedor_id IS 'Fornecedor credor (opcional; ex.: folha consolidada não tem fornecedor).';
COMMENT ON COLUMN titulo_pagar.vendedor_id IS 'Vendedor credor, nos títulos de comissão.';
COMMENT ON COLUMN titulo_pagar.categoria_id IS 'Categoria financeira (natureza DESPESA ou ESTOQUE).';
COMMENT ON COLUMN titulo_pagar.centro_custo_id IS 'Centro de custo.';
COMMENT ON COLUMN titulo_pagar.compra_veiculo_id IS 'Compra de veículo de origem (categoria de estoque).';
COMMENT ON COLUMN titulo_pagar.custo_veiculo_id IS 'Custo de veículo de origem (categoria de estoque).';
COMMENT ON COLUMN titulo_pagar.venda_id IS 'Venda que originou a comissão.';
COMMENT ON COLUMN titulo_pagar.descricao IS 'Descrição do título.';
COMMENT ON COLUMN titulo_pagar.data_emissao IS 'Data de emissão.';
COMMENT ON COLUMN titulo_pagar.data_competencia IS 'Mês em que a despesa é reconhecida na DRE (regime de competência).';
COMMENT ON COLUMN titulo_pagar.data_vencimento IS 'Data de vencimento.';
COMMENT ON COLUMN titulo_pagar.valor IS 'Valor original da parcela.';
COMMENT ON COLUMN titulo_pagar.situacao IS 'ATIVO ou CANCELADO.';
COMMENT ON COLUMN titulo_pagar.data_cancelamento IS 'Data do cancelamento; a reversão da despesa é reconhecida nesse mês.';
COMMENT ON COLUMN titulo_pagar.motivo_cancelamento IS 'Justificativa do cancelamento.';

-- -----------------------------------------------------------------------------
-- Baixas (recebimentos e pagamentos)
-- -----------------------------------------------------------------------------
CREATE TABLE recebimento (
    id                 bigint        GENERATED ALWAYS AS IDENTITY,
    titulo_receber_id  bigint        NOT NULL,
    conta_bancaria_id  smallint      NOT NULL,
    data_recebimento   date          NOT NULL,
    valor_principal    numeric(14,2) NOT NULL,
    valor_juros_multa  numeric(14,2) NOT NULL DEFAULT 0,
    valor_desconto     numeric(14,2) NOT NULL DEFAULT 0,
    valor_total        numeric(14,2) GENERATED ALWAYS AS (valor_principal + valor_juros_multa - valor_desconto) STORED,
    forma_pagamento    varchar(10)   NOT NULL,
    situacao           varchar(10)   NOT NULL DEFAULT 'EFETIVO',
    data_estorno       date,
    motivo_estorno     varchar(200),
    observacao         varchar(200),
    criado_em          timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_recebimento PRIMARY KEY (id),
    CONSTRAINT fk_recebimento_titulo FOREIGN KEY (titulo_receber_id) REFERENCES titulo_receber (id),
    CONSTRAINT fk_recebimento_conta FOREIGN KEY (conta_bancaria_id) REFERENCES conta_bancaria (id),
    CONSTRAINT ck_recebimento_principal CHECK (valor_principal > 0),
    CONSTRAINT ck_recebimento_juros CHECK (valor_juros_multa >= 0),
    CONSTRAINT ck_recebimento_desconto CHECK (valor_desconto >= 0 AND valor_desconto < valor_principal + valor_juros_multa),
    CONSTRAINT ck_recebimento_forma CHECK (forma_pagamento IN ('PIX', 'TED', 'BOLETO', 'DINHEIRO', 'CARTAO', 'CHEQUE')),
    CONSTRAINT ck_recebimento_situacao CHECK (situacao IN ('EFETIVO', 'ESTORNADO')),
    CONSTRAINT ck_recebimento_estorno CHECK (
           (situacao = 'EFETIVO' AND data_estorno IS NULL AND motivo_estorno IS NULL)
        OR (situacao = 'ESTORNADO' AND data_estorno >= data_recebimento AND motivo_estorno IS NOT NULL))
);
COMMENT ON TABLE recebimento IS 'Baixa (total ou parcial) de um título a receber. Cada recebimento gera um movimento bancário de entrada.';
COMMENT ON COLUMN recebimento.id IS 'Identificador interno.';
COMMENT ON COLUMN recebimento.titulo_receber_id IS 'Título baixado.';
COMMENT ON COLUMN recebimento.conta_bancaria_id IS 'Conta que recebeu o dinheiro.';
COMMENT ON COLUMN recebimento.data_recebimento IS 'Data do crédito (regime de caixa).';
COMMENT ON COLUMN recebimento.valor_principal IS 'Quanto do título foi liquidado (reduz o saldo em aberto). Inclui o desconto concedido.';
COMMENT ON COLUMN recebimento.valor_juros_multa IS 'Juros e multa por atraso cobrados (receita financeira).';
COMMENT ON COLUMN recebimento.valor_desconto IS 'Desconto concedido (despesa financeira).';
COMMENT ON COLUMN recebimento.valor_total IS 'Dinheiro efetivamente recebido = principal + juros/multa - desconto (coluna gerada).';
COMMENT ON COLUMN recebimento.forma_pagamento IS 'PIX, TED, BOLETO, DINHEIRO, CARTAO ou CHEQUE.';
COMMENT ON COLUMN recebimento.situacao IS 'EFETIVO ou ESTORNADO.';
COMMENT ON COLUMN recebimento.data_estorno IS 'Data do estorno (ex.: cheque devolvido, devolução ao cliente).';
COMMENT ON COLUMN recebimento.motivo_estorno IS 'Justificativa do estorno.';
COMMENT ON COLUMN recebimento.observacao IS 'Observação livre.';
COMMENT ON COLUMN recebimento.criado_em IS 'Data e hora técnica do registro.';

CREATE TABLE pagamento (
    id                 bigint        GENERATED ALWAYS AS IDENTITY,
    titulo_pagar_id    bigint        NOT NULL,
    conta_bancaria_id  smallint      NOT NULL,
    data_pagamento     date          NOT NULL,
    valor_principal    numeric(14,2) NOT NULL,
    valor_juros_multa  numeric(14,2) NOT NULL DEFAULT 0,
    valor_desconto     numeric(14,2) NOT NULL DEFAULT 0,
    valor_total        numeric(14,2) GENERATED ALWAYS AS (valor_principal + valor_juros_multa - valor_desconto) STORED,
    forma_pagamento    varchar(10)   NOT NULL,
    situacao           varchar(10)   NOT NULL DEFAULT 'EFETIVO',
    data_estorno       date,
    motivo_estorno     varchar(200),
    observacao         varchar(200),
    criado_em          timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_pagamento PRIMARY KEY (id),
    CONSTRAINT fk_pagamento_titulo FOREIGN KEY (titulo_pagar_id) REFERENCES titulo_pagar (id),
    CONSTRAINT fk_pagamento_conta FOREIGN KEY (conta_bancaria_id) REFERENCES conta_bancaria (id),
    CONSTRAINT ck_pagamento_principal CHECK (valor_principal > 0),
    CONSTRAINT ck_pagamento_juros CHECK (valor_juros_multa >= 0),
    CONSTRAINT ck_pagamento_desconto CHECK (valor_desconto >= 0 AND valor_desconto < valor_principal + valor_juros_multa),
    CONSTRAINT ck_pagamento_forma CHECK (forma_pagamento IN ('PIX', 'TED', 'BOLETO', 'DINHEIRO', 'DEBITO')),
    CONSTRAINT ck_pagamento_situacao CHECK (situacao IN ('EFETIVO', 'ESTORNADO')),
    CONSTRAINT ck_pagamento_estorno CHECK (
           (situacao = 'EFETIVO' AND data_estorno IS NULL AND motivo_estorno IS NULL)
        OR (situacao = 'ESTORNADO' AND data_estorno >= data_pagamento AND motivo_estorno IS NOT NULL))
);
COMMENT ON TABLE pagamento IS 'Baixa (total ou parcial) de um título a pagar. Cada pagamento gera um movimento bancário de saída.';
COMMENT ON COLUMN pagamento.id IS 'Identificador interno.';
COMMENT ON COLUMN pagamento.titulo_pagar_id IS 'Título baixado.';
COMMENT ON COLUMN pagamento.conta_bancaria_id IS 'Conta debitada.';
COMMENT ON COLUMN pagamento.data_pagamento IS 'Data do débito (regime de caixa).';
COMMENT ON COLUMN pagamento.valor_principal IS 'Quanto do título foi liquidado (reduz o saldo em aberto). Inclui o desconto obtido.';
COMMENT ON COLUMN pagamento.valor_juros_multa IS 'Juros e multa pagos por atraso (despesa financeira).';
COMMENT ON COLUMN pagamento.valor_desconto IS 'Desconto obtido (receita financeira).';
COMMENT ON COLUMN pagamento.valor_total IS 'Dinheiro efetivamente pago = principal + juros/multa - desconto (coluna gerada).';
COMMENT ON COLUMN pagamento.forma_pagamento IS 'PIX, TED, BOLETO, DINHEIRO ou DEBITO.';
COMMENT ON COLUMN pagamento.situacao IS 'EFETIVO ou ESTORNADO.';
COMMENT ON COLUMN pagamento.data_estorno IS 'Data do estorno (devolução do valor pelo credor).';
COMMENT ON COLUMN pagamento.motivo_estorno IS 'Justificativa do estorno.';
COMMENT ON COLUMN pagamento.observacao IS 'Observação livre.';
COMMENT ON COLUMN pagamento.criado_em IS 'Data e hora técnica do registro.';

-- -----------------------------------------------------------------------------
-- Tesouraria
-- -----------------------------------------------------------------------------
CREATE TABLE transferencia (
    id                  bigint        GENERATED ALWAYS AS IDENTITY,
    conta_origem_id     smallint      NOT NULL,
    conta_destino_id    smallint      NOT NULL,
    data_transferencia  date          NOT NULL,
    valor               numeric(14,2) NOT NULL,
    descricao           varchar(150)  NOT NULL,
    criado_em           timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_transferencia PRIMARY KEY (id),
    CONSTRAINT fk_transferencia_origem FOREIGN KEY (conta_origem_id) REFERENCES conta_bancaria (id),
    CONSTRAINT fk_transferencia_destino FOREIGN KEY (conta_destino_id) REFERENCES conta_bancaria (id),
    CONSTRAINT ck_transferencia_contas CHECK (conta_origem_id <> conta_destino_id),
    CONSTRAINT ck_transferencia_valor CHECK (valor > 0)
);
COMMENT ON TABLE transferencia IS 'Transferência entre contas próprias. Gera uma saída e uma entrada; não é receita nem despesa.';
COMMENT ON COLUMN transferencia.id IS 'Identificador interno.';
COMMENT ON COLUMN transferencia.conta_origem_id IS 'Conta debitada.';
COMMENT ON COLUMN transferencia.conta_destino_id IS 'Conta creditada (diferente da origem).';
COMMENT ON COLUMN transferencia.data_transferencia IS 'Data da transferência.';
COMMENT ON COLUMN transferencia.valor IS 'Valor transferido.';
COMMENT ON COLUMN transferencia.descricao IS 'Descrição.';
COMMENT ON COLUMN transferencia.criado_em IS 'Data e hora técnica do registro.';

CREATE TABLE movimento_bancario (
    id                 bigint        GENERATED ALWAYS AS IDENTITY,
    conta_bancaria_id  smallint      NOT NULL,
    data_movimento     date          NOT NULL,
    tipo               varchar(7)    NOT NULL,
    natureza           varchar(20)   NOT NULL,
    valor              numeric(14,2) NOT NULL,
    historico          varchar(200)  NOT NULL,
    recebimento_id     bigint,
    pagamento_id       bigint,
    transferencia_id   bigint,
    criado_em          timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT pk_movimento_bancario PRIMARY KEY (id),
    CONSTRAINT fk_movimento_bancario_conta FOREIGN KEY (conta_bancaria_id) REFERENCES conta_bancaria (id),
    CONSTRAINT fk_movimento_bancario_recebimento FOREIGN KEY (recebimento_id) REFERENCES recebimento (id),
    CONSTRAINT fk_movimento_bancario_pagamento FOREIGN KEY (pagamento_id) REFERENCES pagamento (id),
    CONSTRAINT fk_movimento_bancario_transferencia FOREIGN KEY (transferencia_id) REFERENCES transferencia (id),
    CONSTRAINT ck_movimento_bancario_tipo CHECK (tipo IN ('ENTRADA', 'SAIDA')),
    CONSTRAINT ck_movimento_bancario_valor CHECK (valor > 0),
    CONSTRAINT ck_movimento_bancario_origem CHECK (num_nonnulls(recebimento_id, pagamento_id, transferencia_id) = 1),
    CONSTRAINT ck_movimento_bancario_natureza CHECK (
           (natureza = 'RECEBIMENTO'         AND tipo = 'ENTRADA' AND recebimento_id   IS NOT NULL)
        OR (natureza = 'ESTORNO_RECEBIMENTO' AND tipo = 'SAIDA'   AND recebimento_id   IS NOT NULL)
        OR (natureza = 'PAGAMENTO'           AND tipo = 'SAIDA'   AND pagamento_id     IS NOT NULL)
        OR (natureza = 'ESTORNO_PAGAMENTO'   AND tipo = 'ENTRADA' AND pagamento_id     IS NOT NULL)
        OR (natureza = 'TRANSFERENCIA'                            AND transferencia_id IS NOT NULL)),
    CONSTRAINT uq_movimento_bancario_recebimento UNIQUE (recebimento_id, natureza),
    CONSTRAINT uq_movimento_bancario_pagamento UNIQUE (pagamento_id, natureza),
    CONSTRAINT uq_movimento_bancario_transferencia UNIQUE (transferencia_id, tipo)
);
COMMENT ON TABLE movimento_bancario IS 'Extrato de todas as contas: fonte única do regime de caixa. Imutável: correções são feitas por estorno.';
COMMENT ON COLUMN movimento_bancario.id IS 'Identificador interno.';
COMMENT ON COLUMN movimento_bancario.conta_bancaria_id IS 'Conta movimentada.';
COMMENT ON COLUMN movimento_bancario.data_movimento IS 'Data do crédito ou débito.';
COMMENT ON COLUMN movimento_bancario.tipo IS 'ENTRADA ou SAIDA.';
COMMENT ON COLUMN movimento_bancario.natureza IS 'RECEBIMENTO, ESTORNO_RECEBIMENTO, PAGAMENTO, ESTORNO_PAGAMENTO ou TRANSFERENCIA.';
COMMENT ON COLUMN movimento_bancario.valor IS 'Valor sempre positivo; o sentido vem de tipo.';
COMMENT ON COLUMN movimento_bancario.historico IS 'Texto do extrato.';
COMMENT ON COLUMN movimento_bancario.recebimento_id IS 'Recebimento de origem.';
COMMENT ON COLUMN movimento_bancario.pagamento_id IS 'Pagamento de origem.';
COMMENT ON COLUMN movimento_bancario.transferencia_id IS 'Transferência de origem.';
COMMENT ON COLUMN movimento_bancario.criado_em IS 'Data e hora técnica do registro.';

-- -----------------------------------------------------------------------------
-- Índices
-- Chaves primárias e restrições UNIQUE já criam índices próprios.
-- Os índices abaixo atendem às consultas das views e dos relatórios.
-- -----------------------------------------------------------------------------

-- Regra de negócio: um veículo só pode ter UMA venda ativa (bloqueia venda duplicada).
CREATE UNIQUE INDEX uq_venda_veiculo_ativa ON venda (veiculo_id) WHERE situacao = 'ATIVA';

-- DRE e ranking de vendedores filtram vendas por período e por vendedor.
CREATE INDEX ix_venda_data_venda ON venda (data_venda);
CREATE INDEX ix_venda_vendedor_data ON venda (vendedor_id, data_venda);
CREATE INDEX ix_venda_cliente ON venda (cliente_id);

-- Custo total do veículo (estoque e CMV) soma custos por veículo.
CREATE INDEX ix_custo_veiculo_veiculo ON custo_veiculo (veiculo_id, data_custo);
CREATE INDEX ix_compra_veiculo_fornecedor ON compra_veiculo (fornecedor_id);

-- Posição de contas a receber/pagar: títulos ativos por vencimento (vencidos x a vencer).
CREATE INDEX ix_titulo_receber_vencimento_ativo ON titulo_receber (data_vencimento) WHERE situacao = 'ATIVO';
CREATE INDEX ix_titulo_receber_cliente ON titulo_receber (cliente_id, data_vencimento);
CREATE INDEX ix_titulo_receber_venda ON titulo_receber (venda_id);
CREATE INDEX ix_titulo_pagar_vencimento_ativo ON titulo_pagar (data_vencimento) WHERE situacao = 'ATIVO';
-- DRE de despesas: títulos por mês de competência e categoria.
CREATE INDEX ix_titulo_pagar_competencia ON titulo_pagar (data_competencia, categoria_id);
CREATE INDEX ix_titulo_pagar_venda ON titulo_pagar (venda_id) WHERE venda_id IS NOT NULL;
CREATE INDEX ix_titulo_pagar_compra ON titulo_pagar (compra_veiculo_id) WHERE compra_veiculo_id IS NOT NULL;
CREATE INDEX ix_titulo_pagar_custo ON titulo_pagar (custo_veiculo_id) WHERE custo_veiculo_id IS NOT NULL;
CREATE INDEX ix_titulo_pagar_fornecedor ON titulo_pagar (fornecedor_id);

-- Saldo em aberto = valor - soma das baixas efetivas do título.
CREATE INDEX ix_recebimento_titulo ON recebimento (titulo_receber_id) INCLUDE (valor_principal, situacao);
CREATE INDEX ix_pagamento_titulo ON pagamento (titulo_pagar_id) INCLUDE (valor_principal, situacao);
-- Resultado financeiro (juros e descontos) por data de baixa.
CREATE INDEX ix_recebimento_data ON recebimento (data_recebimento);
CREATE INDEX ix_pagamento_data ON pagamento (data_pagamento);

-- Extrato, saldos e fluxo de caixa: movimentos por conta e data.
CREATE INDEX ix_movimento_bancario_conta_data ON movimento_bancario (conta_bancaria_id, data_movimento);
CREATE INDEX ix_movimento_bancario_data ON movimento_bancario (data_movimento);
