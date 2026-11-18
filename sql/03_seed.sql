-- =============================================================================
-- Fast Car - Sistema Financeiro em SQL
-- Arquivo : sql/03_seed.sql
-- Objetivo: carregar dados fictícios de janeiro a junho de 2026.
-- Depende : 01_schema.sql e 02_functions.sql (executar em schema recém-criado)
--
-- Todos os nomes, documentos, chassis, placas e valores são SINTÉTICOS.
-- CPFs/CNPJs não são válidos e e-mails usam o domínio reservado example.com.
--
-- Data de referência: 2026-06-30. Todas as operações são datadas até ela, e
-- os relatórios de vencidos/a vencer usam essa data (tabela configuracao).
--
-- Os lançamentos usam as funções de negócio (nunca INSERT direto em títulos,
-- baixas ou movimentos), para que todas as regras sejam aplicadas.
-- O script inteiro roda em uma transação: ou carrega tudo, ou nada.
-- =============================================================================

\set ON_ERROR_STOP on
SET search_path TO fastcar, public;

BEGIN;

-- -----------------------------------------------------------------------------
-- Configuração e cadastros
-- -----------------------------------------------------------------------------
INSERT INTO configuracao (id, data_referencia, descricao)
VALUES (1, DATE '2026-06-30', 'Data-base fixa para exemplos e testes reproduzíveis');

INSERT INTO centro_custo (codigo, nome) VALUES
    ('ADM', 'Administrativo'),
    ('COM', 'Comercial'),
    ('OFI', 'Oficina e preparação');

INSERT INTO categoria_financeira (codigo, nome, natureza, grupo_dre) VALUES
    ('1.01', 'Venda de veículos',                        'RECEITA', NULL),
    ('1.02', 'Serviços de despachante',                  'RECEITA', 'OUTRAS_RECEITAS'),
    ('2.01', 'Aquisição de veículos para estoque',       'ESTOQUE', NULL),
    ('2.02', 'Custos de preparação de veículos',         'ESTOQUE', NULL),
    ('3.01', 'Comissões sobre vendas',                   'DESPESA', 'DESPESA_VENDAS'),
    ('3.02', 'Marketing e publicidade',                  'DESPESA', 'DESPESA_VENDAS'),
    ('3.03', 'Salários e encargos',                      'DESPESA', 'DESPESA_PESSOAL'),
    ('3.04', 'Aluguel',                                  'DESPESA', 'DESPESA_ADMINISTRATIVA'),
    ('3.05', 'Energia, água e telecomunicações',         'DESPESA', 'DESPESA_ADMINISTRATIVA'),
    ('3.06', 'Serviços de terceiros',                    'DESPESA', 'DESPESA_ADMINISTRATIVA'),
    ('3.07', 'Tarifas bancárias',                        'DESPESA', 'DESPESA_ADMINISTRATIVA'),
    ('3.08', 'Garantia e pós-venda',                     'DESPESA', 'DESPESA_VENDAS');

INSERT INTO conta_bancaria (codigo, descricao, tipo, banco, agencia, numero_conta, saldo_inicial, data_saldo_inicial) VALUES
    ('BCO_A', 'Banco Alfa - conta movimento', 'CORRENTE', 'Banco Alfa (fictício)', '0001', '10001-1', 650000.00, DATE '2025-12-31'),
    ('BCO_B', 'Banco Beta - conta cobrança',  'CORRENTE', 'Banco Beta (fictício)', '0002', '20002-2', 150000.00, DATE '2025-12-31'),
    ('CAIXA', 'Caixa da loja',                'CAIXA',    NULL,                    NULL,   NULL,       5000.00,  DATE '2025-12-31');

INSERT INTO cliente (tipo_pessoa, nome, documento, email, telefone, cidade, uf, data_cadastro) VALUES
    ('F', 'Rafael Moreira Lima',          '90000000001',    'rafael.lima@example.com',     '11900000001', 'São Paulo', 'SP', DATE '2026-01-20'),
    ('F', 'Patrícia Gomes Duarte',        '90000000002',    'patricia.duarte@example.com', '11900000002', 'Guarulhos', 'SP', DATE '2026-02-05'),
    ('F', 'Eduardo Nunes Barros',         '90000000003',    'eduardo.barros@example.com',  '11900000003', 'Osasco',    'SP', DATE '2026-02-20'),
    ('F', 'Mariana Alves Teixeira',       '90000000004',    'mariana.teixeira@example.com','11900000004', 'Santo André','SP', DATE '2026-03-10'),
    ('F', 'Gustavo Pereira Rocha',        '90000000005',    'gustavo.rocha@example.com',   '11900000005', 'São Paulo', 'SP', DATE '2026-03-01'),
    ('F', 'Luciana Freitas Campos',       '90000000006',    'luciana.campos@example.com',  '11900000006', 'Barueri',   'SP', DATE '2026-03-20'),
    ('F', 'Thiago Martins Cardoso',       '90000000007',    'thiago.cardoso@example.com',  '11900000007', 'São Paulo', 'SP', DATE '2026-05-05'),
    ('F', 'Fernanda Souza Ramos',         '90000000008',    'fernanda.ramos@example.com',  '11900000008', 'Diadema',   'SP', DATE '2026-04-10'),
    ('J', 'Agropecuária Campo Verde Ltda','90000000000109', 'financeiro@campoverde.example.com', '1930000009', 'Campinas', 'SP', DATE '2026-05-02'),
    ('F', 'Renato Carvalho Pinto',        '90000000010',    'renato.pinto@example.com',    '11900000010', 'São Paulo', 'SP', DATE '2026-06-01');

INSERT INTO fornecedor (tipo_pessoa, nome, documento, ramo, email, telefone, data_cadastro) VALUES
    ('J', 'Leilões Paulista Veículos Ltda',     '80000000000101', 'Leilão e revenda de veículos', 'contato@leiloespaulista.example.com', '1130000001', DATE '2026-01-02'),
    ('F', 'Marcos Andrade (particular)',        '80000000002',    'Venda particular de veículo',   'marcos.andrade@example.com',          '11910000002', DATE '2026-01-02'),
    ('J', 'Oficina Mecânica Torque Ltda',       '80000000000303', 'Oficina mecânica',             'oficina@torque.example.com',          '1130000003', DATE '2026-01-02'),
    ('J', 'Despachante Rápido Ltda',            '80000000000404', 'Despachante',                  'atendimento@despachante.example.com', '1130000004', DATE '2026-01-02'),
    ('J', 'Estética Automotiva Brilho Ltda',    '80000000000505', 'Estética e preparação',        'contato@brilho.example.com',          '1130000005', DATE '2026-01-02'),
    ('J', 'Imobiliária Central Ltda',           '80000000000606', 'Locação de imóveis',           'locacao@central.example.com',         '1130000006', DATE '2026-01-02'),
    ('J', 'Companhia de Energia e Telecom S.A.','80000000000707', 'Energia, água e telecom',      'empresas@energiatelecom.example.com', '1130000007', DATE '2026-01-02'),
    ('J', 'Contábil Exata Ltda',                '80000000000808', 'Contabilidade',                'escritorio@exata.example.com',        '1130000008', DATE '2026-01-02'),
    ('J', 'Agência Vitrine Digital Ltda',       '80000000000909', 'Marketing e publicidade',      'midia@vitrine.example.com',           '1130000009', DATE '2026-01-02'),
    ('J', 'Banco Alfa S.A. (fictício)',         '80000000001010', 'Serviços bancários',           NULL,                                  NULL,         DATE '2026-01-02'),
    ('J', 'Locadora Frota Usada Ltda',          '80000000001111', 'Locadora (venda de seminovos)', 'seminovos@frota.example.com',        '1130000011', DATE '2026-01-02'),
    ('F', 'Juliana Prado (particular)',         '80000000012',    'Venda particular de veículo',   'juliana.prado@example.com',           '11910000012', DATE '2026-01-02');

INSERT INTO vendedor (nome, cpf, email, percentual_comissao, data_admissao) VALUES
    ('Ana Ribeiro',  '70000000001', 'ana.ribeiro@fastcar.example.com',  2.00, DATE '2024-03-01'),
    ('Bruno Costa',  '70000000002', 'bruno.costa@fastcar.example.com',  1.50, DATE '2025-02-10'),
    ('Carla Mendes', '70000000003', 'carla.mendes@fastcar.example.com', 1.80, DATE '2025-08-15');

-- -----------------------------------------------------------------------------
-- Despesas fixas e recorrentes (competência de janeiro a junho)
--   Aluguel       : competência dia 1, vence dia 10 do mesmo mês.
--   Salários      : competência último dia do mês, vence dia 5 do mês seguinte.
--   Energia/telecom: competência último dia do mês, vence dia 15 do mês seguinte.
--   Contabilidade : competência último dia do mês, vence dia 10 do mês seguinte.
--   Marketing     : competência e vencimento no dia 25 do mês.
--   Tarifas       : debitadas no último dia do mês.
-- -----------------------------------------------------------------------------
SELECT fn_lancar_conta_pagar('ALUG-2026-' || to_char(m, 'MM'), 'Aluguel da loja ' || to_char(m, 'MM/YYYY'),
                             '3.04', 'ADM', '80000000000606', m::date, (m + interval '9 days')::date, 6800.00)
  FROM generate_series(DATE '2026-01-01', DATE '2026-06-01', interval '1 month') AS m;

SELECT fn_lancar_conta_pagar('FOLHA-2026-' || to_char(m, 'MM'), 'Folha de pagamento e encargos ' || to_char(m, 'MM/YYYY'),
                             '3.03', 'ADM', NULL, (m + interval '1 month - 1 day')::date,
                             (m + interval '1 month 4 days')::date,
                             CASE WHEN m < DATE '2026-03-01' THEN 10900.00 ELSE 11600.00 END)
  FROM generate_series(DATE '2026-01-01', DATE '2026-06-01', interval '1 month') AS m;

SELECT fn_lancar_conta_pagar('ENERG-2026-' || to_char(m, 'MM'), 'Energia, água e internet ' || to_char(m, 'MM/YYYY'),
                             '3.05', 'ADM', '80000000000707', (m + interval '1 month - 1 day')::date,
                             (m + interval '1 month 14 days')::date, v)
  FROM (VALUES (DATE '2026-01-01', 890.00), (DATE '2026-02-01', 920.00), (DATE '2026-03-01', 860.00),
               (DATE '2026-04-01', 840.00), (DATE '2026-05-01', 880.00), (DATE '2026-06-01', 950.00)) AS t(m, v);

SELECT fn_lancar_conta_pagar('CONT-2026-' || to_char(m, 'MM'), 'Honorários contábeis ' || to_char(m, 'MM/YYYY'),
                             '3.06', 'ADM', '80000000000808', (m + interval '1 month - 1 day')::date,
                             (m + interval '1 month 9 days')::date, 1500.00)
  FROM generate_series(DATE '2026-01-01', DATE '2026-06-01', interval '1 month') AS m;

SELECT fn_lancar_conta_pagar('MKT-2026-' || to_char(m, 'MM'), 'Anúncios em portais e redes sociais ' || to_char(m, 'MM/YYYY'),
                             '3.02', 'COM', '80000000000909', (m + interval '24 days')::date,
                             (m + interval '24 days')::date, v)
  FROM (VALUES (DATE '2026-01-01', 3200.00), (DATE '2026-02-01', 2600.00), (DATE '2026-03-01', 3600.00),
               (DATE '2026-04-01', 2400.00), (DATE '2026-05-01', 2900.00), (DATE '2026-06-01', 2700.00)) AS t(m, v);

SELECT fn_lancar_conta_pagar('TARIF-2026-' || to_char(m, 'MM'), 'Tarifas bancárias ' || to_char(m, 'MM/YYYY'),
                             '3.07', 'ADM', '80000000001010', (m + interval '1 month - 1 day')::date,
                             (m + interval '1 month - 1 day')::date, 89.00)
  FROM generate_series(DATE '2026-01-01', DATE '2026-06-01', interval '1 month') AS m;

-- Feirão de março: despesa parcelada em 3x (competência integral em março).
SELECT fn_lancar_conta_pagar('MKT-FEIRAO-2026', 'Feirão de seminovos de março', '3.02', 'COM', '80000000000909',
                             DATE '2026-03-14', DATE '2026-03-20', 4500.00, 3);

-- =============================================================================
-- JANEIRO
-- =============================================================================
SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-001', p_fornecedor_documento => '80000000002', p_data_compra => DATE '2026-01-05',
    p_valor_compra => 58000.00, p_parcelas => 1, p_primeiro_vencimento => DATE '2026-01-05',
    p_chassi => 'FCAR2600000000001', p_placa => 'FCA1A01', p_renavam => '90000000001',
    p_marca => 'Chevrolet', p_modelo => 'Onix', p_versao => 'LT 1.0', p_ano_fabricacao => 2021, p_ano_modelo => 2022,
    p_cor => 'Prata', p_quilometragem => 48000, p_preco_anunciado => 72900.00);
SELECT fn_registrar_pagamento('C2026-001', 1, DATE '2026-01-05', 'BCO_A', 58000.00, p_forma => 'TED');

SELECT fn_registrar_custo_veiculo('NF-CV-001', 'FCAR2600000000001', '80000000000404', 'DOCUMENTACAO', 'Transferência e vistoria', DATE '2026-01-07', 850.00, DATE '2026-01-15');
SELECT fn_registrar_custo_veiculo('NF-CV-002', 'FCAR2600000000001', '80000000000505', 'PREPARACAO', 'Polimento e higienização', DATE '2026-01-09', 1200.00, DATE '2026-01-20');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-002', p_fornecedor_documento => '80000000000101', p_data_compra => DATE '2026-01-08',
    p_valor_compra => 62000.00, p_parcelas => 2, p_primeiro_vencimento => DATE '2026-01-08',
    p_chassi => 'FCAR2600000000002', p_placa => 'FCA1A02', p_renavam => '90000000002',
    p_marca => 'Hyundai', p_modelo => 'HB20', p_versao => 'Comfort 1.0', p_ano_fabricacao => 2022, p_ano_modelo => 2022,
    p_cor => 'Branco', p_quilometragem => 35000, p_preco_anunciado => 76900.00);
SELECT fn_registrar_pagamento('C2026-002', 1, DATE '2026-01-08', 'BCO_A', 31000.00, p_forma => 'TED');

SELECT fn_registrar_pagamento('ALUG-2026-01', 1, DATE '2026-01-10', 'BCO_A', 6800.00, p_forma => 'BOLETO');
SELECT fn_disponibilizar_veiculo('FCAR2600000000001');

SELECT fn_registrar_custo_veiculo('NF-CV-003', 'FCAR2600000000002', '80000000000303', 'MANUTENCAO', 'Revisão, freios e suspensão', DATE '2026-01-14', 2300.00, DATE '2026-01-30');
SELECT fn_registrar_pagamento('NF-CV-001', 1, DATE '2026-01-15', 'BCO_A', 850.00, p_forma => 'PIX');
SELECT fn_registrar_custo_veiculo('NF-CV-004', 'FCAR2600000000002', '80000000000404', 'DOCUMENTACAO', 'Transferência e vistoria', DATE '2026-01-16', 900.00, DATE '2026-01-25');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-003', p_fornecedor_documento => '80000000001111', p_data_compra => DATE '2026-01-20',
    p_valor_compra => 98000.00, p_parcelas => 1, p_primeiro_vencimento => DATE '2026-01-20',
    p_chassi => 'FCAR2600000000003', p_placa => 'FCA1A03', p_renavam => '90000000003',
    p_marca => 'Toyota', p_modelo => 'Corolla', p_versao => 'XEi 2.0', p_ano_fabricacao => 2020, p_ano_modelo => 2021,
    p_cor => 'Preto', p_quilometragem => 62000, p_preco_anunciado => 124900.00);
SELECT fn_registrar_pagamento('C2026-003', 1, DATE '2026-01-20', 'BCO_A', 98000.00, p_forma => 'TED');
SELECT fn_registrar_pagamento('NF-CV-002', 1, DATE '2026-01-20', 'BCO_A', 1200.00, p_forma => 'PIX');
SELECT fn_disponibilizar_veiculo('FCAR2600000000002');

-- Venda à vista do Onix.
SELECT fn_registrar_venda('V2026-001', 'FCAR2600000000001', '90000000001', '70000000001', DATE '2026-01-24', 72900.00, 72900.00, 0);
SELECT fn_registrar_recebimento('V2026-001', 0, DATE '2026-01-24', 'BCO_A', 72900.00, p_forma => 'TED');

SELECT fn_registrar_pagamento('MKT-2026-01', 1, DATE '2026-01-25', 'BCO_A', 3200.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('NF-CV-004', 1, DATE '2026-01-25', 'BCO_A', 900.00, p_forma => 'PIX');
SELECT fn_registrar_custo_veiculo('NF-CV-005', 'FCAR2600000000003', '80000000000505', 'PREPARACAO', 'Polimento, pneus e higienização', DATE '2026-01-26', 3500.00, DATE '2026-02-05');
SELECT fn_registrar_custo_veiculo('NF-CV-006', 'FCAR2600000000003', '80000000000404', 'DOCUMENTACAO', 'Transferência e vistoria', DATE '2026-01-27', 1100.00, DATE '2026-02-05');
SELECT fn_registrar_pagamento('NF-CV-003', 1, DATE '2026-01-30', 'BCO_A', 2300.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('TARIF-2026-01', 1, DATE '2026-01-31', 'BCO_A', 89.00, p_forma => 'DEBITO');

-- =============================================================================
-- FEVEREIRO
-- =============================================================================
SELECT fn_disponibilizar_veiculo('FCAR2600000000003');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-004', p_fornecedor_documento => '80000000000101', p_data_compra => DATE '2026-02-03',
    p_valor_compra => 125000.00, p_parcelas => 2, p_primeiro_vencimento => DATE '2026-02-03',
    p_chassi => 'FCAR2600000000004', p_placa => 'FCA1A04', p_renavam => '90000000004',
    p_marca => 'Jeep', p_modelo => 'Compass', p_versao => 'Longitude 2.0', p_ano_fabricacao => 2021, p_ano_modelo => 2021,
    p_cor => 'Cinza', p_quilometragem => 41000, p_preco_anunciado => 149900.00);
SELECT fn_registrar_pagamento('C2026-004', 1, DATE '2026-02-03', 'BCO_A', 62500.00, p_forma => 'TED');

SELECT fn_registrar_pagamento('FOLHA-2026-01', 1, DATE '2026-02-05', 'BCO_A', 10900.00, p_forma => 'TED');
SELECT fn_registrar_pagamento('NF-CV-005', 1, DATE '2026-02-05', 'BCO_A', 3500.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('NF-CV-006', 1, DATE '2026-02-05', 'BCO_A', 1100.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('C2026-002', 2, DATE '2026-02-08', 'BCO_A', 31000.00, p_forma => 'TED');

-- Venda parcelada do HB20: entrada + 10 parcelas de 5.000.
SELECT fn_registrar_venda('V2026-002', 'FCAR2600000000002', '90000000002', '70000000002', DATE '2026-02-10',
                          79900.00, 29900.00, 10, DATE '2026-03-10');
SELECT fn_registrar_recebimento('V2026-002', 0, DATE '2026-02-10', 'BCO_A', 29900.00, p_forma => 'PIX');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-005', p_fornecedor_documento => '80000000012', p_data_compra => DATE '2026-02-10',
    p_valor_compra => 38000.00, p_parcelas => 1, p_primeiro_vencimento => DATE '2026-02-10',
    p_chassi => 'FCAR2600000000005', p_placa => 'FCA1A05', p_renavam => '90000000005',
    p_marca => 'Volkswagen', p_modelo => 'Gol', p_versao => '1.0 MPI', p_ano_fabricacao => 2019, p_ano_modelo => 2020,
    p_cor => 'Vermelho', p_quilometragem => 78000, p_preco_anunciado => 49900.00);
SELECT fn_registrar_pagamento('C2026-005', 1, DATE '2026-02-10', 'BCO_A', 38000.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('ALUG-2026-02', 1, DATE '2026-02-10', 'BCO_A', 6800.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('CONT-2026-01', 1, DATE '2026-02-10', 'BCO_A', 1500.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('COM-V2026-001', 1, DATE '2026-02-10', 'BCO_A', 1458.00, p_forma => 'PIX');

SELECT fn_registrar_custo_veiculo('NF-CV-007', 'FCAR2600000000004', '80000000000303', 'MANUTENCAO', 'Troca de correia, fluidos e alinhamento', DATE '2026-02-10', 4200.00, DATE '2026-02-25');
SELECT fn_registrar_custo_veiculo('NF-CV-008', 'FCAR2600000000004', '80000000000404', 'DOCUMENTACAO', 'Transferência e vistoria', DATE '2026-02-12', 1300.00, DATE '2026-02-20');
SELECT fn_registrar_custo_veiculo('NF-CV-009', 'FCAR2600000000005', '80000000000505', 'PREPARACAO', 'Funilaria leve e polimento', DATE '2026-02-14', 1500.00, DATE '2026-02-28');
SELECT fn_registrar_custo_veiculo('NF-CV-010', 'FCAR2600000000005', '80000000000404', 'DOCUMENTACAO', 'Transferência e vistoria', DATE '2026-02-15', 700.00, DATE '2026-02-28');
SELECT fn_registrar_pagamento('ENERG-2026-01', 1, DATE '2026-02-15', 'BCO_A', 890.00, p_forma => 'BOLETO');
SELECT fn_disponibilizar_veiculo('FCAR2600000000004');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-006', p_fornecedor_documento => '80000000001111', p_data_compra => DATE '2026-02-20',
    p_valor_compra => 82000.00, p_parcelas => 1, p_primeiro_vencimento => DATE '2026-02-20',
    p_chassi => 'FCAR2600000000006', p_placa => 'FCA1A06', p_renavam => '90000000006',
    p_marca => 'Jeep', p_modelo => 'Renegade', p_versao => 'Sport 1.8', p_ano_fabricacao => 2020, p_ano_modelo => 2020,
    p_cor => 'Azul', p_quilometragem => 55000, p_preco_anunciado => 97900.00);
SELECT fn_registrar_pagamento('C2026-006', 1, DATE '2026-02-20', 'BCO_A', 82000.00, p_forma => 'TED');
SELECT fn_registrar_pagamento('NF-CV-008', 1, DATE '2026-02-20', 'BCO_A', 1300.00, p_forma => 'PIX');
SELECT fn_disponibilizar_veiculo('FCAR2600000000005');

SELECT fn_registrar_custo_veiculo('NF-CV-011', 'FCAR2600000000006', '80000000000303', 'MANUTENCAO', 'Revisão completa e bateria', DATE '2026-02-24', 2000.00, DATE '2026-03-10');
SELECT fn_registrar_pagamento('MKT-2026-02', 1, DATE '2026-02-25', 'BCO_A', 2600.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('NF-CV-007', 1, DATE '2026-02-25', 'BCO_A', 4200.00, p_forma => 'PIX');

-- Venda "à vista" do Corolla paga em duas transferências (recebimento parcial).
SELECT fn_registrar_venda('V2026-003', 'FCAR2600000000003', '90000000003', '70000000001', DATE '2026-02-27', 124900.00, 124900.00, 0);
SELECT fn_registrar_recebimento('V2026-003', 0, DATE '2026-02-27', 'BCO_A', 100000.00, p_forma => 'TED', p_observacao => 'Primeira transferência do cliente');

SELECT fn_registrar_pagamento('NF-CV-009', 1, DATE '2026-02-28', 'BCO_A', 1500.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('NF-CV-010', 1, DATE '2026-02-28', 'BCO_A', 700.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('TARIF-2026-02', 1, DATE '2026-02-28', 'BCO_A', 89.00, p_forma => 'DEBITO');

-- =============================================================================
-- MARÇO
-- =============================================================================
SELECT fn_disponibilizar_veiculo('FCAR2600000000006');
SELECT fn_registrar_recebimento('V2026-003', 0, DATE '2026-03-02', 'BCO_A', 24900.00, p_forma => 'TED', p_observacao => 'Saldo da venda à vista');
SELECT fn_registrar_pagamento('C2026-004', 2, DATE '2026-03-03', 'BCO_A', 62500.00, p_forma => 'TED');

-- Venda parcelada do Gol: entrada em dinheiro no caixa da loja.
SELECT fn_registrar_venda('V2026-005', 'FCAR2600000000005', '90000000005', '70000000002', DATE '2026-03-05',
                          49900.00, 13900.00, 6, DATE '2026-04-05');
SELECT fn_registrar_recebimento('V2026-005', 0, DATE '2026-03-05', 'CAIXA', 13900.00, p_forma => 'DINHEIRO');
SELECT fn_registrar_pagamento('FOLHA-2026-02', 1, DATE '2026-03-05', 'BCO_A', 10900.00, p_forma => 'TED');

-- Transferência entre contas próprias: depósito do dinheiro do caixa no banco.
SELECT fn_registrar_transferencia('CAIXA', 'BCO_A', DATE '2026-03-06', 10000.00, 'Depósito de numerário do caixa');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-007', p_fornecedor_documento => '80000000000101', p_data_compra => DATE '2026-03-10',
    p_valor_compra => 60000.00, p_parcelas => 1, p_primeiro_vencimento => DATE '2026-03-10',
    p_chassi => 'FCAR2600000000007', p_placa => 'FCA1A07', p_renavam => '90000000007',
    p_marca => 'Fiat', p_modelo => 'Argo', p_versao => 'Drive 1.0', p_ano_fabricacao => 2022, p_ano_modelo => 2023,
    p_cor => 'Branco', p_quilometragem => 28000, p_preco_anunciado => 72900.00);
SELECT fn_registrar_pagamento('C2026-007', 1, DATE '2026-03-10', 'BCO_A', 60000.00, p_forma => 'TED');
SELECT fn_registrar_pagamento('ALUG-2026-03', 1, DATE '2026-03-10', 'BCO_A', 6800.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('CONT-2026-02', 1, DATE '2026-03-10', 'BCO_A', 1500.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('COM-V2026-002', 1, DATE '2026-03-10', 'BCO_A', 1198.50, p_forma => 'PIX');
SELECT fn_registrar_pagamento('COM-V2026-003', 1, DATE '2026-03-10', 'BCO_A', 2498.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('NF-CV-011', 1, DATE '2026-03-10', 'BCO_A', 2000.00, p_forma => 'PIX');
SELECT fn_registrar_recebimento('V2026-002', 1, DATE '2026-03-10', 'BCO_B', 5000.00, p_forma => 'BOLETO');

-- Venda parcelada do Compass + serviço de despachante cobrado à parte.
SELECT fn_registrar_venda('V2026-004', 'FCAR2600000000004', '90000000004', '70000000003', DATE '2026-03-14',
                          154900.00, 54900.00, 5, DATE '2026-04-14');
SELECT fn_registrar_recebimento('V2026-004', 0, DATE '2026-03-14', 'BCO_A', 54900.00, p_forma => 'TED');
SELECT fn_lancar_conta_receber('SERV-2026-001', 'Serviço de despachante - transferência do Compass', '1.02', 'COM',
                               '90000000004', DATE '2026-03-14', DATE '2026-03-14', 650.00);
SELECT fn_registrar_recebimento('SERV-2026-001', 1, DATE '2026-03-14', 'CAIXA', 650.00, p_forma => 'DINHEIRO');

SELECT fn_registrar_custo_veiculo('NF-CV-012', 'FCAR2600000000007', '80000000000505', 'PREPARACAO', 'Polimento e higienização', DATE '2026-03-14', 1800.00, DATE '2026-03-30');
SELECT fn_registrar_pagamento('ENERG-2026-02', 1, DATE '2026-03-16', 'BCO_A', 920.00, p_forma => 'BOLETO');
SELECT fn_disponibilizar_veiculo('FCAR2600000000007');
SELECT fn_registrar_pagamento('MKT-FEIRAO-2026', 1, DATE '2026-03-20', 'BCO_A', 1500.00, p_forma => 'BOLETO');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-008', p_fornecedor_documento => '80000000001111', p_data_compra => DATE '2026-03-25',
    p_valor_compra => 165000.00, p_parcelas => 3, p_primeiro_vencimento => DATE '2026-03-25',
    p_chassi => 'FCAR2600000000008', p_placa => 'FCA1A08', p_renavam => '90000000008',
    p_marca => 'Toyota', p_modelo => 'Hilux', p_versao => 'SRV 2.8 4x4', p_ano_fabricacao => 2019, p_ano_modelo => 2019,
    p_cor => 'Prata', p_quilometragem => 95000, p_preco_anunciado => 199900.00);
SELECT fn_registrar_pagamento('C2026-008', 1, DATE '2026-03-25', 'BCO_A', 55000.00, p_forma => 'TED');
SELECT fn_registrar_pagamento('MKT-2026-03', 1, DATE '2026-03-25', 'BCO_A', 3600.00, p_forma => 'BOLETO');

-- Venda parcelada do Renegade (será cancelada em abril).
SELECT fn_registrar_venda('V2026-006', 'FCAR2600000000006', '90000000006', '70000000003', DATE '2026-03-27',
                          99000.00, 39000.00, 3, DATE '2026-04-27');
SELECT fn_registrar_recebimento('V2026-006', 0, DATE '2026-03-27', 'BCO_A', 39000.00, p_forma => 'TED');

SELECT fn_registrar_pagamento('NF-CV-012', 1, DATE '2026-03-30', 'BCO_A', 1800.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('TARIF-2026-03', 1, DATE '2026-03-31', 'BCO_A', 89.00, p_forma => 'DEBITO');

-- =============================================================================
-- ABRIL
-- =============================================================================
SELECT fn_registrar_custo_veiculo('NF-CV-013', 'FCAR2600000000008', '80000000000303', 'MANUTENCAO', 'Revisão de motor, embreagem e pneus', DATE '2026-04-01', 5500.00, DATE '2026-04-20');
SELECT fn_registrar_custo_veiculo('NF-CV-014', 'FCAR2600000000008', '80000000000404', 'DOCUMENTACAO', 'Transferência e vistoria', DATE '2026-04-02', 1400.00, DATE '2026-04-15');
SELECT fn_registrar_pagamento('FOLHA-2026-03', 1, DATE '2026-04-06', 'BCO_A', 11600.00, p_forma => 'TED');
SELECT fn_registrar_recebimento('V2026-005', 1, DATE '2026-04-06', 'BCO_B', 6000.00, p_forma => 'BOLETO', p_observacao => 'Vencimento em 05/04 (domingo), pago no dia útil seguinte');

-- Cancelamento da venda do Renegade: entrada devolvida, parcelas e comissão canceladas,
-- veículo volta ao estoque. Receita e CMV são revertidos em abril.
SELECT fn_cancelar_venda('V2026-006', DATE '2026-04-06', 'Distrato: cliente desistiu da compra após recusa de crédito pessoal');

SELECT fn_disponibilizar_veiculo('FCAR2600000000008');
SELECT fn_registrar_pagamento('ALUG-2026-04', 1, DATE '2026-04-10', 'BCO_A', 6800.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('CONT-2026-03', 1, DATE '2026-04-10', 'BCO_A', 1500.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('COM-V2026-004', 1, DATE '2026-04-10', 'BCO_A', 2788.20, p_forma => 'PIX');
SELECT fn_registrar_pagamento('COM-V2026-005', 1, DATE '2026-04-10', 'BCO_A', 748.50, p_forma => 'PIX');
SELECT fn_registrar_recebimento('V2026-002', 2, DATE '2026-04-10', 'BCO_B', 5000.00, p_forma => 'BOLETO');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-009', p_fornecedor_documento => '80000000000101', p_data_compra => DATE '2026-04-12',
    p_valor_compra => 105000.00, p_parcelas => 1, p_primeiro_vencimento => DATE '2026-04-12',
    p_chassi => 'FCAR2600000000009', p_placa => 'FCA1A09', p_renavam => '90000000009',
    p_marca => 'Volkswagen', p_modelo => 'T-Cross', p_versao => 'Comfortline 1.0 TSI', p_ano_fabricacao => 2022, p_ano_modelo => 2022,
    p_cor => 'Cinza', p_quilometragem => 30000, p_preco_anunciado => 129900.00);
SELECT fn_registrar_pagamento('C2026-009', 1, DATE '2026-04-12', 'BCO_A', 105000.00, p_forma => 'TED');
SELECT fn_registrar_recebimento('V2026-004', 1, DATE '2026-04-14', 'BCO_B', 20000.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('NF-CV-014', 1, DATE '2026-04-15', 'BCO_A', 1400.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('ENERG-2026-03', 1, DATE '2026-04-15', 'BCO_A', 860.00, p_forma => 'BOLETO');
SELECT fn_registrar_custo_veiculo('NF-CV-015', 'FCAR2600000000009', '80000000000505', 'PREPARACAO', 'Polimento e vitrificação', DATE '2026-04-16', 2700.00, DATE '2026-04-30');

-- Venda parcelada do Argo.
SELECT fn_registrar_venda('V2026-007', 'FCAR2600000000007', '90000000008', '70000000002', DATE '2026-04-18',
                          74500.00, 24500.00, 5, DATE '2026-05-18');
SELECT fn_registrar_recebimento('V2026-007', 0, DATE '2026-04-18', 'BCO_A', 24500.00, p_forma => 'PIX');

SELECT fn_registrar_pagamento('NF-CV-013', 1, DATE '2026-04-20', 'BCO_A', 5500.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('MKT-FEIRAO-2026', 2, DATE '2026-04-20', 'BCO_A', 1500.00, p_forma => 'BOLETO');
SELECT fn_disponibilizar_veiculo('FCAR2600000000009');

-- Pagamento de marketing feito com boleto errado, devolvido pela agência e pago de novo.
SELECT fn_registrar_pagamento('MKT-2026-04', 1, DATE '2026-04-25', 'BCO_A', 2400.00, p_forma => 'BOLETO', p_observacao => 'Boleto com código de barras incorreto');
SELECT fn_estornar_pagamento(
    (SELECT p.id FROM pagamento p JOIN titulo_pagar t ON t.id = p.titulo_pagar_id
      WHERE t.documento = 'MKT-2026-04' AND p.situacao = 'EFETIVO'),
    DATE '2026-04-27', 'Valor devolvido pela agência: boleto emitido com dados incorretos');
SELECT fn_registrar_pagamento('MKT-2026-04', 1, DATE '2026-04-28', 'BCO_A', 2400.00, p_forma => 'PIX', p_observacao => 'Pagamento refeito');

SELECT fn_registrar_pagamento('C2026-008', 2, DATE '2026-04-25', 'BCO_A', 55000.00, p_forma => 'TED');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-010', p_fornecedor_documento => '80000000002', p_data_compra => DATE '2026-04-28',
    p_valor_compra => 45000.00, p_parcelas => 1, p_primeiro_vencimento => DATE '2026-04-28',
    p_chassi => 'FCAR2600000000010', p_placa => 'FCA1A10', p_renavam => '90000000010',
    p_marca => 'Renault', p_modelo => 'Kwid', p_versao => 'Zen 1.0', p_ano_fabricacao => 2023, p_ano_modelo => 2023,
    p_cor => 'Laranja', p_quilometragem => 15000, p_preco_anunciado => 54900.00);
SELECT fn_registrar_pagamento('C2026-010', 1, DATE '2026-04-28', 'BCO_A', 45000.00, p_forma => 'PIX');

-- Transferência entre contas próprias: concentração de recursos na conta movimento.
SELECT fn_registrar_transferencia('BCO_B', 'BCO_A', DATE '2026-04-30', 60000.00, 'Concentração de saldo na conta movimento');
SELECT fn_registrar_pagamento('NF-CV-015', 1, DATE '2026-04-30', 'BCO_A', 2700.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('TARIF-2026-04', 1, DATE '2026-04-30', 'BCO_A', 89.00, p_forma => 'DEBITO');

-- =============================================================================
-- MAIO
-- =============================================================================
SELECT fn_registrar_custo_veiculo('NF-CV-016', 'FCAR2600000000010', '80000000000505', 'PREPARACAO', 'Higienização e pequenos reparos', DATE '2026-05-03', 900.00, DATE '2026-05-15');

-- Parcela 2 do Gol paga com cheque, que volta sem fundos (estorno do recebimento).
SELECT fn_registrar_recebimento('V2026-005', 2, DATE '2026-05-05', 'BCO_B', 6000.00, p_forma => 'CHEQUE');
SELECT fn_registrar_pagamento('FOLHA-2026-04', 1, DATE '2026-05-05', 'BCO_A', 11600.00, p_forma => 'TED');

-- Parcela 3 do HB20 antecipada com desconto de 100,00.
SELECT fn_registrar_recebimento('V2026-002', 3, DATE '2026-05-05', 'BCO_B', 5000.00, p_desconto => 100.00, p_forma => 'PIX', p_observacao => 'Antecipação com desconto');
SELECT fn_disponibilizar_veiculo('FCAR2600000000010');

-- Venda à vista da Hilux para pessoa jurídica, paga em duas transferências.
SELECT fn_registrar_venda('V2026-008', 'FCAR2600000000008', '90000000000109', '70000000003', DATE '2026-05-08', 199900.00, 199900.00, 0);
SELECT fn_registrar_recebimento('V2026-008', 0, DATE '2026-05-08', 'BCO_A', 150000.00, p_forma => 'TED');
SELECT fn_lancar_conta_receber('SERV-2026-002', 'Serviço de despachante - transferência da Hilux', '1.02', 'COM',
                               '90000000000109', DATE '2026-05-08', DATE '2026-05-15', 800.00);

SELECT fn_estornar_recebimento(
    (SELECT r.id FROM recebimento r JOIN titulo_receber t ON t.id = r.titulo_receber_id
      WHERE t.documento = 'V2026-005' AND t.numero_parcela = 2 AND r.situacao = 'EFETIVO'),
    DATE '2026-05-08', 'Cheque devolvido por insuficiência de fundos');

SELECT fn_registrar_pagamento('ALUG-2026-05', 1, DATE '2026-05-11', 'BCO_A', 6800.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('CONT-2026-04', 1, DATE '2026-05-11', 'BCO_A', 1500.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('COM-V2026-007', 1, DATE '2026-05-11', 'BCO_A', 1117.50, p_forma => 'PIX');
SELECT fn_registrar_recebimento('V2026-008', 0, DATE '2026-05-11', 'BCO_B', 49900.00, p_forma => 'TED', p_observacao => 'Saldo da venda à vista');

-- Revenda do Renegade (devolvido ao estoque pelo cancelamento de abril).
SELECT fn_registrar_venda('V2026-009', 'FCAR2600000000006', '90000000007', '70000000001', DATE '2026-05-12', 97500.00, 97500.00, 0);
SELECT fn_registrar_recebimento('V2026-009', 0, DATE '2026-05-12', 'BCO_A', 97500.00, p_forma => 'TED');

-- Despesa de garantia de um veículo já vendido: vai para a DRE (não para o custo do veículo).
SELECT fn_lancar_conta_pagar('GAR-2026-001', 'Garantia: reparo no ar-condicionado do Onix vendido em janeiro',
                             '3.08', 'OFI', '80000000000303', DATE '2026-05-12', DATE '2026-05-20', 650.00);

SELECT fn_registrar_recebimento('V2026-004', 2, DATE '2026-05-14', 'BCO_B', 12000.00, p_forma => 'BOLETO', p_observacao => 'Pagamento parcial');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-011', p_fornecedor_documento => '80000000001111', p_data_compra => DATE '2026-05-15',
    p_valor_compra => 92000.00, p_parcelas => 2, p_primeiro_vencimento => DATE '2026-05-15',
    p_chassi => 'FCAR2600000000011', p_placa => 'FCA1A11', p_renavam => '90000000011',
    p_marca => 'Honda', p_modelo => 'Civic', p_versao => 'EXL 2.0', p_ano_fabricacao => 2019, p_ano_modelo => 2019,
    p_cor => 'Preto', p_quilometragem => 70000, p_preco_anunciado => 112900.00);
SELECT fn_registrar_pagamento('C2026-011', 1, DATE '2026-05-15', 'BCO_A', 46000.00, p_forma => 'TED');
SELECT fn_registrar_pagamento('NF-CV-016', 1, DATE '2026-05-15', 'BCO_A', 900.00, p_forma => 'PIX');
SELECT fn_registrar_recebimento('SERV-2026-002', 1, DATE '2026-05-15', 'BCO_B', 800.00, p_forma => 'PIX');
SELECT fn_registrar_recebimento('V2026-007', 1, DATE '2026-05-18', 'BCO_B', 10000.00, p_forma => 'BOLETO');
SELECT fn_registrar_custo_veiculo('NF-CV-017', 'FCAR2600000000011', '80000000000303', 'MANUTENCAO', 'Revisão, pastilhas e discos', DATE '2026-05-19', 3100.00, DATE '2026-06-05');

-- Energia de abril paga com 5 dias de atraso (multa e juros de 18,50).
SELECT fn_registrar_pagamento('ENERG-2026-04', 1, DATE '2026-05-20', 'BCO_A', 840.00, p_juros_multa => 18.50, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('GAR-2026-001', 1, DATE '2026-05-20', 'BCO_A', 650.00, p_forma => 'PIX');
SELECT fn_registrar_pagamento('MKT-FEIRAO-2026', 3, DATE '2026-05-20', 'BCO_A', 1500.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('C2026-008', 3, DATE '2026-05-25', 'BCO_A', 55000.00, p_forma => 'TED');
SELECT fn_registrar_pagamento('MKT-2026-05', 1, DATE '2026-05-25', 'BCO_A', 2900.00, p_forma => 'BOLETO');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-012', p_fornecedor_documento => '80000000000101', p_data_compra => DATE '2026-05-29',
    p_valor_compra => 88000.00, p_parcelas => 1, p_primeiro_vencimento => DATE '2026-05-29',
    p_chassi => 'FCAR2600000000012', p_placa => 'FCA1A12', p_renavam => '90000000012',
    p_marca => 'Hyundai', p_modelo => 'Creta', p_versao => 'Action 1.6', p_ano_fabricacao => 2021, p_ano_modelo => 2022,
    p_cor => 'Branco', p_quilometragem => 39000, p_preco_anunciado => 104900.00);
SELECT fn_registrar_pagamento('C2026-012', 1, DATE '2026-05-29', 'BCO_A', 88000.00, p_forma => 'TED');
SELECT fn_disponibilizar_veiculo('FCAR2600000000011');
SELECT fn_registrar_pagamento('TARIF-2026-05', 1, DATE '2026-05-31', 'BCO_A', 89.00, p_forma => 'DEBITO');

-- =============================================================================
-- JUNHO
-- =============================================================================
SELECT fn_registrar_custo_veiculo('NF-CV-018', 'FCAR2600000000012', '80000000000505', 'PREPARACAO', 'Polimento e higienização', DATE '2026-06-03', 1600.00, DATE '2026-06-15');
SELECT fn_registrar_pagamento('FOLHA-2026-05', 1, DATE '2026-06-05', 'BCO_A', 11600.00, p_forma => 'TED');
SELECT fn_registrar_pagamento('NF-CV-017', 1, DATE '2026-06-05', 'BCO_A', 3100.00, p_forma => 'PIX');

-- Compass: restante da parcela 2 pago com atraso e juros (parcela 3 ficará em aberto).
SELECT fn_registrar_recebimento('V2026-004', 2, DATE '2026-06-05', 'BCO_B', 8000.00, p_juros_multa => 160.00, p_forma => 'BOLETO', p_observacao => 'Quitação da parcela 2 com juros de atraso');
SELECT fn_disponibilizar_veiculo('FCAR2600000000012');

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-013', p_fornecedor_documento => '80000000001111', p_data_compra => DATE '2026-06-10',
    p_valor_compra => 120000.00, p_parcelas => 3, p_primeiro_vencimento => DATE '2026-06-10',
    p_chassi => 'FCAR2600000000013', p_placa => 'FCA1A13', p_renavam => '90000000013',
    p_marca => 'Ford', p_modelo => 'Ranger', p_versao => 'XLS 2.2 4x4', p_ano_fabricacao => 2018, p_ano_modelo => 2018,
    p_cor => 'Vermelho', p_quilometragem => 110000, p_preco_anunciado => 139900.00);
SELECT fn_registrar_pagamento('C2026-013', 1, DATE '2026-06-10', 'BCO_A', 40000.00, p_forma => 'TED');

-- Venda parcelada do T-Cross (parcelas a vencer a partir de julho).
SELECT fn_registrar_venda('V2026-010', 'FCAR2600000000009', '90000000010', '70000000001', DATE '2026-06-10',
                          129900.00, 49900.00, 4, DATE '2026-07-10');
SELECT fn_registrar_recebimento('V2026-010', 0, DATE '2026-06-10', 'BCO_A', 49900.00, p_forma => 'TED');

SELECT fn_registrar_pagamento('ALUG-2026-06', 1, DATE '2026-06-10', 'BCO_A', 6800.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('CONT-2026-05', 1, DATE '2026-06-10', 'BCO_A', 1500.00, p_forma => 'BOLETO');
SELECT fn_registrar_pagamento('COM-V2026-008', 1, DATE '2026-06-10', 'BCO_A', 3598.20, p_forma => 'PIX');
SELECT fn_registrar_pagamento('COM-V2026-009', 1, DATE '2026-06-10', 'BCO_A', 1950.00, p_forma => 'PIX');

-- Campanha de rádio contratada e cancelada antes do pagamento.
SELECT fn_lancar_conta_pagar('MKT-2026-06-RADIO', 'Campanha em rádio local', '3.02', 'COM', '80000000000909',
                             DATE '2026-06-01', DATE '2026-06-30', 1800.00, 1, DATE '2026-06-01');
SELECT fn_cancelar_titulo_pagar('MKT-2026-06-RADIO', 1, DATE '2026-06-12', 'Contrato cancelado pela agência antes da veiculação');

SELECT fn_registrar_recebimento('V2026-002', 4, DATE '2026-06-12', 'BCO_B', 5000.00, p_juros_multa => 50.00, p_forma => 'BOLETO', p_observacao => 'Pago com 2 dias de atraso');
SELECT fn_registrar_custo_veiculo('NF-CV-019', 'FCAR2600000000013', '80000000000303', 'MANUTENCAO', 'Revisão de motor e suspensão', DATE '2026-06-15', 2500.00, DATE '2026-07-15');
SELECT fn_registrar_pagamento('C2026-011', 2, DATE '2026-06-15', 'BCO_A', 46000.00, p_forma => 'TED');
SELECT fn_registrar_pagamento('NF-CV-018', 1, DATE '2026-06-15', 'BCO_A', 1600.00, p_forma => 'PIX');
-- Energia de maio (vencimento 15/06) NÃO foi paga: fica vencida na data de referência.

SELECT fn_registrar_compra_veiculo(
    p_numero_compra => 'C2026-014', p_fornecedor_documento => '80000000002', p_data_compra => DATE '2026-06-20',
    p_valor_compra => 41000.00, p_parcelas => 1, p_primeiro_vencimento => DATE '2026-06-20',
    p_chassi => 'FCAR2600000000014', p_placa => 'FCA1A14', p_renavam => '90000000014',
    p_marca => 'Renault', p_modelo => 'Sandero', p_versao => 'Expression 1.0', p_ano_fabricacao => 2020, p_ano_modelo => 2020,
    p_cor => 'Prata', p_quilometragem => 60000, p_preco_anunciado => 52900.00);
SELECT fn_registrar_pagamento('C2026-014', 1, DATE '2026-06-20', 'BCO_A', 41000.00, p_forma => 'PIX');

-- Venda à vista do Civic para cliente recorrente.
SELECT fn_registrar_venda('V2026-011', 'FCAR2600000000011', '90000000001', '70000000002', DATE '2026-06-22', 113900.00, 113900.00, 0);
SELECT fn_registrar_recebimento('V2026-011', 0, DATE '2026-06-22', 'BCO_A', 113900.00, p_forma => 'TED');

-- Argo: pagamento parcial da parcela 2 (vencida em 18/06).
SELECT fn_registrar_recebimento('V2026-007', 2, DATE '2026-06-25', 'BCO_B', 4000.00, p_forma => 'PIX', p_observacao => 'Pagamento parcial');
SELECT fn_registrar_pagamento('MKT-2026-06', 1, DATE '2026-06-25', 'BCO_A', 2700.00, p_forma => 'BOLETO');

-- Transferência entre contas próprias: reforço do caixa da loja.
SELECT fn_registrar_transferencia('BCO_A', 'CAIXA', DATE '2026-06-29', 1500.00, 'Reforço de troco do caixa');
SELECT fn_registrar_pagamento('TARIF-2026-06', 1, DATE '2026-06-30', 'BCO_A', 89.00, p_forma => 'DEBITO');

COMMIT;
