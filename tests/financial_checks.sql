-- =============================================================================
-- Fast Car - Sistema Financeiro em SQL
-- Arquivo : tests/financial_checks.sql
-- Objetivo: testes automatizados de integridade e consistência financeira.
-- Depende : sql/01 a sql/04 executados e sql/03_seed.sql carregado.
--
-- Execução:
--   psql -d fastcar -v ON_ERROR_STOP=1 -f tests/financial_checks.sql
--
-- Funcionamento:
--   * Tudo roda em UMA transação que termina em ROLLBACK: os testes que
--     simulam operações (pagamentos, cancelamentos, transferências) não
--     alteram o banco.
--   * Cada teste grava APROVADO/REPROVADO em uma tabela temporária, exibida ao final.
--   * Se algum teste reprovar, o script termina com erro (código de saída 3 no psql).
--   * Testes de bloqueio executam o comando proibido dentro de um sub-bloco e
--     verificam que ele falhou com o SQLSTATE esperado.
--   * Valores esperados fixos referem-se ao seed (data de referência 2026-06-30).
-- =============================================================================

\set ON_ERROR_STOP on
SET search_path TO fastcar, public;
SET client_min_messages TO warning;

BEGIN;

-- Oculta a saída de cada chamada individual; o resultado consolidado é exibido ao final.
\o /dev/null

CREATE TEMP TABLE resultado_teste (
    ordem     serial PRIMARY KEY,
    grupo     text    NOT NULL,
    teste     text    NOT NULL,
    aprovado  boolean NOT NULL,
    detalhe   text
) ON COMMIT DROP;

-- Registra o resultado de um teste.
CREATE FUNCTION pg_temp.verificar(p_grupo text, p_teste text, p_ok boolean, p_detalhe text DEFAULT NULL)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO resultado_teste (grupo, teste, aprovado, detalhe)
    VALUES (p_grupo, p_teste, COALESCE(p_ok, false), p_detalhe);
$$;

-- Executa um comando que DEVE falhar. Aprova se falhar com o SQLSTATE esperado
-- (e, opcionalmente, com mensagem contendo p_trecho). O sub-bloco desfaz o comando.
CREATE FUNCTION pg_temp.esperar_erro(p_grupo text, p_teste text, p_sql text,
                                     p_sqlstate text, p_trecho text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        PERFORM pg_temp.verificar(p_grupo, p_teste, false, 'Comando foi aceito, mas deveria ser bloqueado');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.verificar(p_grupo, p_teste,
            SQLSTATE = p_sqlstate AND (p_trecho IS NULL OR SQLERRM ILIKE '%' || p_trecho || '%'),
            SQLSTATE || ': ' || SQLERRM);
    END;
END $$;

-- =============================================================================
-- A. INTEGRIDADE DOS RELACIONAMENTOS
-- =============================================================================
SELECT pg_temp.verificar('A. Integridade', 'Toda compra tem títulos a pagar que somam o valor da compra',
    NOT EXISTS (
        SELECT 1 FROM compra_veiculo c
         WHERE c.valor_compra <> (SELECT COALESCE(sum(t.valor), 0) FROM titulo_pagar t
                                   WHERE t.compra_veiculo_id = c.id AND t.situacao = 'ATIVO')),
    (SELECT count(*) || ' compras verificadas' FROM compra_veiculo));

SELECT pg_temp.verificar('A. Integridade', 'Todo custo de veículo tem exatamente um título a pagar de mesmo valor',
    NOT EXISTS (
        SELECT 1 FROM custo_veiculo cv
         WHERE (SELECT count(*) FROM titulo_pagar t WHERE t.custo_veiculo_id = cv.id) <> 1
            OR cv.valor <> (SELECT sum(t.valor) FROM titulo_pagar t WHERE t.custo_veiculo_id = cv.id)),
    (SELECT count(*) || ' custos verificados' FROM custo_veiculo));

SELECT pg_temp.verificar('A. Integridade', 'Toda venda ativa tem títulos a receber ativos que somam o valor da venda',
    NOT EXISTS (
        SELECT 1 FROM venda v
         WHERE v.situacao = 'ATIVA'
           AND v.valor_venda <> (SELECT COALESCE(sum(t.valor), 0) FROM titulo_receber t
                                  WHERE t.venda_id = v.id AND t.situacao = 'ATIVO')),
    (SELECT count(*) || ' vendas ativas' FROM venda WHERE situacao = 'ATIVA'));

SELECT pg_temp.verificar('A. Integridade', 'Toda venda com comissão tem um título de comissão de mesmo valor',
    NOT EXISTS (
        SELECT 1 FROM venda v
         WHERE v.valor_comissao > 0
           AND (SELECT count(*) FROM titulo_pagar t WHERE t.venda_id = v.id AND t.valor = v.valor_comissao) <> 1));

SELECT pg_temp.verificar('A. Integridade', 'CMV registrado na venda = aquisição + custos até a data da venda',
    NOT EXISTS (SELECT 1 FROM venda v
                 WHERE v.custo_veiculo_vendido <> fn_custo_veiculo(v.veiculo_id, v.data_venda)));

SELECT pg_temp.verificar('A. Integridade', 'Veículo VENDIDO se e somente se possui venda ativa',
    NOT EXISTS (
        SELECT 1 FROM veiculo ve
         WHERE (ve.situacao = 'VENDIDO') <> EXISTS (SELECT 1 FROM venda v
                                                     WHERE v.veiculo_id = ve.id AND v.situacao = 'ATIVA')));

SELECT pg_temp.verificar('A. Integridade', 'Cada recebimento tem 1 movimento de entrada de mesmo valor (e 1 de estorno se estornado)',
    NOT EXISTS (
        SELECT 1 FROM recebimento r
         WHERE (SELECT count(*) FROM movimento_bancario m
                 WHERE m.recebimento_id = r.id AND m.natureza = 'RECEBIMENTO' AND m.valor = r.valor_total
                   AND m.conta_bancaria_id = r.conta_bancaria_id AND m.data_movimento = r.data_recebimento) <> 1
            OR (SELECT count(*) FROM movimento_bancario m
                 WHERE m.recebimento_id = r.id AND m.natureza = 'ESTORNO_RECEBIMENTO' AND m.valor = r.valor_total)
               <> CASE r.situacao WHEN 'ESTORNADO' THEN 1 ELSE 0 END),
    (SELECT count(*) || ' recebimentos' FROM recebimento));

SELECT pg_temp.verificar('A. Integridade', 'Cada pagamento tem 1 movimento de saída de mesmo valor (e 1 de estorno se estornado)',
    NOT EXISTS (
        SELECT 1 FROM pagamento p
         WHERE (SELECT count(*) FROM movimento_bancario m
                 WHERE m.pagamento_id = p.id AND m.natureza = 'PAGAMENTO' AND m.valor = p.valor_total
                   AND m.conta_bancaria_id = p.conta_bancaria_id AND m.data_movimento = p.data_pagamento) <> 1
            OR (SELECT count(*) FROM movimento_bancario m
                 WHERE m.pagamento_id = p.id AND m.natureza = 'ESTORNO_PAGAMENTO' AND m.valor = p.valor_total)
               <> CASE p.situacao WHEN 'ESTORNADO' THEN 1 ELSE 0 END),
    (SELECT count(*) || ' pagamentos' FROM pagamento));

SELECT pg_temp.verificar('A. Integridade', 'Todo movimento bancário tem origem (recebimento, pagamento ou transferência)',
    NOT EXISTS (SELECT 1 FROM movimento_bancario
                 WHERE num_nonnulls(recebimento_id, pagamento_id, transferencia_id) <> 1));

SELECT pg_temp.esperar_erro('A. Integridade', 'FK: venda com cliente inexistente é rejeitada',
    $$INSERT INTO venda (numero_venda, veiculo_id, cliente_id, vendedor_id, data_venda, valor_venda, valor_entrada,
                         quantidade_parcelas, custo_veiculo_vendido, percentual_comissao, valor_comissao)
      VALUES ('T-FK', (SELECT id FROM veiculo WHERE chassi = 'FCAR2600000000010'), 999999, 1,
              DATE '2026-06-30', 50000, 50000, 0, 1, 0, 0)$$, '23503');

SELECT pg_temp.esperar_erro('A. Integridade', 'FK: recebimento de título inexistente é rejeitado',
    $$INSERT INTO recebimento (titulo_receber_id, conta_bancaria_id, data_recebimento, valor_principal, forma_pagamento)
      VALUES (999999, 1, DATE '2026-06-30', 10, 'PIX')$$, 'P0001', 'não existe');

SELECT pg_temp.esperar_erro('A. Integridade', 'Exclusão de movimento bancário é bloqueada (histórico preservado)',
    $$DELETE FROM movimento_bancario WHERE id = (SELECT min(id) FROM movimento_bancario)$$, 'P0001', 'imutáveis');

SELECT pg_temp.esperar_erro('A. Integridade', 'Alteração de valor de movimento bancário é bloqueada',
    $$UPDATE movimento_bancario SET valor = valor + 1 WHERE id = (SELECT min(id) FROM movimento_bancario)$$, 'P0001', 'imutáveis');

SELECT pg_temp.esperar_erro('A. Integridade', 'Exclusão de venda é bloqueada',
    $$DELETE FROM venda WHERE numero_venda = 'V2026-001'$$, 'P0001', 'Exclusão não permitida');

-- =============================================================================
-- B. BLOQUEIO DE VALORES INVÁLIDOS
-- =============================================================================
SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Título a pagar com valor negativo',
    $$SELECT fn_lancar_conta_pagar('T-NEG', 'Teste', '3.04', 'ADM', NULL, DATE '2026-06-30', DATE '2026-06-30', -100)$$,
    'P0001', 'positivo');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'INSERT direto de título com valor zero (CHECK)',
    $$INSERT INTO titulo_pagar (documento, numero_parcela, total_parcelas, categoria_id, centro_custo_id, descricao,
                                data_emissao, data_competencia, data_vencimento, valor)
      VALUES ('T-ZERO', 1, 1, fn_id_categoria('3.04'), fn_id_centro_custo('ADM'), 'Teste',
              DATE '2026-06-30', DATE '2026-06-30', DATE '2026-06-30', 0)$$, '23514');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Chassi com letra proibida (O) é rejeitado',
    $$INSERT INTO veiculo (chassi, marca, modelo, ano_fabricacao, ano_modelo, quilometragem)
      VALUES ('FCAR26OOOOOOOOOO1', 'Teste', 'Teste', 2020, 2020, 0)$$, '23514');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Ano-modelo dois anos após a fabricação é rejeitado',
    $$INSERT INTO veiculo (chassi, marca, modelo, ano_fabricacao, ano_modelo, quilometragem)
      VALUES ('FCAR2699999999991', 'Teste', 'Teste', 2020, 2022, 0)$$, '23514');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'CPF com tamanho errado é rejeitado',
    $$INSERT INTO cliente (tipo_pessoa, nome, documento, data_cadastro) VALUES ('F', 'Teste', '123', DATE '2026-06-30')$$, '23514');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Documento de cliente duplicado é rejeitado',
    $$INSERT INTO cliente (tipo_pessoa, nome, documento, data_cadastro) VALUES ('F', 'Teste', '90000000001', DATE '2026-06-30')$$, '23505');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Comissão acima de 10% é rejeitada',
    $$INSERT INTO vendedor (nome, cpf, percentual_comissao, data_admissao) VALUES ('Teste', '79999999999', 50, DATE '2026-01-01')$$, '23514');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Entrada maior que o valor da venda é rejeitada',
    $$SELECT fn_registrar_venda('T-ENT', 'FCAR2600000000010', '90000000010', '70000000001', DATE '2026-06-30', 50000, 60000, 0)$$,
    '23514');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Desconto maior ou igual ao valor recebido é rejeitado',
    $$SELECT fn_registrar_recebimento('V2026-002', 5, DATE '2026-06-30', 'BCO_B', 100, p_desconto => 100)$$, '23514');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Título a pagar com categoria de receita é rejeitado',
    $$SELECT fn_lancar_conta_pagar('T-CAT', 'Teste', '1.02', 'ADM', NULL, DATE '2026-06-30', DATE '2026-06-30', 100)$$,
    'P0001', 'DESPESA ou ESTOQUE');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Despesa lançada em categoria de estoque é rejeitada (compra não vira despesa)',
    $$SELECT fn_lancar_conta_pagar('T-EST', 'Teste', '2.01', 'ADM', NULL, DATE '2026-06-30', DATE '2026-06-30', 100)$$,
    'P0001', 'ESTOQUE');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Conta a receber avulsa na categoria de venda de veículos é rejeitada',
    $$SELECT fn_lancar_conta_receber('T-REC', 'Teste', '1.01', 'COM', '90000000001', DATE '2026-06-30', DATE '2026-06-30', 100)$$,
    'P0001', '1.01');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Transferência para a mesma conta é rejeitada',
    $$SELECT fn_registrar_transferencia('BCO_A', 'BCO_A', DATE '2026-06-30', 100, 'Teste')$$, '23514');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Movimento anterior ao saldo inicial é rejeitado',
    $$SELECT fn_registrar_transferencia('BCO_A', 'BCO_B', DATE '2025-12-31', 100, 'Teste')$$, 'P0001', 'saldo inicial');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Custo em veículo já vendido é rejeitado',
    $$SELECT fn_registrar_custo_veiculo('T-CV', 'FCAR2600000000001', '80000000000303', 'MANUTENCAO', 'Teste',
                                        DATE '2026-06-30', 100, DATE '2026-06-30')$$, 'P0001', 'já vendido');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Pagamento em título cancelado é rejeitado',
    $$SELECT fn_registrar_pagamento('MKT-2026-06-RADIO', 1, DATE '2026-06-30', 'BCO_A', 100)$$, 'P0001', 'cancelado');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Alteração do valor de uma venda é bloqueada',
    $$UPDATE venda SET valor_venda = 1 WHERE numero_venda = 'V2026-001'$$, 'P0001', 'não pode ser alterada');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Cancelar título de compra de veículo é bloqueado',
    $$SELECT fn_cancelar_titulo_pagar('C2026-013', 2, DATE '2026-06-30', 'Teste')$$, 'P0001', 'não podem ser cancelados');

SELECT pg_temp.esperar_erro('B. Valores inválidos', 'Cancelar parcela de venda ativa isoladamente é bloqueado',
    $$SELECT fn_cancelar_titulo_receber('V2026-002', 5, DATE '2026-06-30', 'Teste')$$, 'P0001', 'fn_cancelar_venda');

-- =============================================================================
-- C. PREVENÇÃO DE VENDA DUPLICADA
-- =============================================================================
SELECT pg_temp.esperar_erro('C. Venda duplicada', 'Vender de novo um veículo já vendido é rejeitado',
    $$SELECT fn_registrar_venda('T-DUP', 'FCAR2600000000001', '90000000002', '70000000001', DATE '2026-06-30', 70000, 70000, 0)$$,
    'P0001', 'não está disponível');

SELECT pg_temp.esperar_erro('C. Venda duplicada', 'Número de venda repetido é rejeitado',
    $$SELECT fn_registrar_venda('V2026-001', 'FCAR2600000000010', '90000000002', '70000000001', DATE '2026-06-30', 50000, 50000, 0)$$,
    '23505');

SELECT pg_temp.esperar_erro('C. Venda duplicada', 'Vender veículo ainda em preparação é rejeitado',
    $$SELECT fn_registrar_venda('T-PREP', 'FCAR2600000000013', '90000000002', '70000000001', DATE '2026-06-30', 130000, 130000, 0)$$,
    'P0001', 'não está disponível');

SELECT pg_temp.verificar('C. Venda duplicada', 'Índice único parcial impede duas vendas ATIVAS do mesmo veículo',
    EXISTS (SELECT 1 FROM pg_indexes
             WHERE schemaname = 'fastcar' AND indexname = 'uq_venda_veiculo_ativa'
               AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%situacao%ATIVA%'));

SELECT pg_temp.verificar('C. Venda duplicada', 'Nenhum veículo tem mais de uma venda ativa',
    NOT EXISTS (SELECT 1 FROM venda WHERE situacao = 'ATIVA' GROUP BY veiculo_id HAVING count(*) > 1));

SELECT pg_temp.verificar('C. Venda duplicada', 'Veículo com venda cancelada pôde ser revendido (Renegade: 1 cancelada + 1 ativa)',
    (SELECT count(*) FILTER (WHERE v.situacao = 'CANCELADA') = 1 AND count(*) FILTER (WHERE v.situacao = 'ATIVA') = 1
       FROM venda v JOIN veiculo ve ON ve.id = v.veiculo_id WHERE ve.chassi = 'FCAR2600000000006'));

-- =============================================================================
-- D. PAGAMENTOS PARCIAIS E SALDOS
-- =============================================================================
SELECT pg_temp.verificar('D. Parciais e saldos', 'Nenhum título tem baixas efetivas acima do seu valor',
    NOT EXISTS (SELECT 1 FROM titulo_receber t WHERE fn_saldo_titulo_receber(t.id) < 0)
    AND NOT EXISTS (SELECT 1 FROM titulo_pagar t WHERE fn_saldo_titulo_pagar(t.id) < 0));

SELECT pg_temp.verificar('D. Parciais e saldos', 'Posição a receber: saldo = valor - recebido, para todos os títulos',
    NOT EXISTS (SELECT 1 FROM fn_posicao_contas_receber(fn_data_referencia())
                 WHERE saldo_aberto <> valor_titulo - valor_recebido
                    OR saldo_aberto <> fn_saldo_titulo_receber(titulo_id)));

SELECT pg_temp.verificar('D. Parciais e saldos', 'Posição a pagar: saldo = valor - pago, para todos os títulos',
    NOT EXISTS (SELECT 1 FROM fn_posicao_contas_pagar(fn_data_referencia())
                 WHERE saldo_aberto <> valor_titulo - valor_pago
                    OR saldo_aberto <> fn_saldo_titulo_pagar(titulo_id)));

SELECT pg_temp.verificar('D. Parciais e saldos', 'Compass parcela 2: 12.000 + 8.000 quitam 20.000 (juros fora do principal)',
    (SELECT saldo_aberto = 0 AND valor_recebido = 20000 FROM fn_posicao_contas_receber(fn_data_referencia())
      WHERE documento = 'V2026-004' AND numero_parcela = 2)
    AND (SELECT sum(r.valor_total) = 20160 FROM recebimento r JOIN titulo_receber t ON t.id = r.titulo_receber_id
          WHERE t.documento = 'V2026-004' AND t.numero_parcela = 2));

SELECT pg_temp.verificar('D. Parciais e saldos', 'Argo parcela 2: recebido 4.000, saldo vencido 6.000',
    (SELECT valor_recebido = 4000 AND saldo_aberto = 6000 AND situacao = 'VENCIDO' AND recebido_parcial
       FROM fn_posicao_contas_receber(fn_data_referencia())
      WHERE documento = 'V2026-007' AND numero_parcela = 2));

SELECT pg_temp.verificar('D. Parciais e saldos', 'Desconto quita o principal: HB20 parcela 3 saldo 0 com 4.900 em caixa',
    (SELECT saldo_aberto = 0 FROM fn_posicao_contas_receber(fn_data_referencia())
      WHERE documento = 'V2026-002' AND numero_parcela = 3)
    AND (SELECT r.valor_total = 4900 FROM recebimento r JOIN titulo_receber t ON t.id = r.titulo_receber_id
          WHERE t.documento = 'V2026-002' AND t.numero_parcela = 3));

SELECT pg_temp.verificar('D. Parciais e saldos', 'Totais em aberto na data de referência (receber 236.000; pagar 101.736,50)',
    (SELECT sum(saldo_aberto) FROM vw_contas_receber_aberto) = 236000.00
    AND (SELECT sum(saldo_aberto) FROM vw_contas_pagar_aberto) = 101736.50,
    (SELECT 'receber=' || sum(saldo_aberto) FROM vw_contas_receber_aberto) || ' / ' ||
    (SELECT 'pagar=' || sum(saldo_aberto) FROM vw_contas_pagar_aberto));

SELECT pg_temp.verificar('D. Parciais e saldos', 'Posição histórica: em 31/05 a parcela 2 do Compass tinha saldo 8.000 vencido',
    (SELECT saldo_aberto = 8000 AND situacao = 'VENCIDO' AND recebido_parcial
       FROM fn_posicao_contas_receber(DATE '2026-05-31') WHERE documento = 'V2026-004' AND numero_parcela = 2));

-- Simulação: título de 1.000 pago em duas partes e tentativa de pagar além do saldo.
DO $$
BEGIN
    PERFORM fn_lancar_conta_pagar('T-PARC', 'Teste de parciais', '3.06', 'ADM', '80000000000808',
                                  DATE '2026-06-30', DATE '2026-06-30', 1000.00);
    PERFORM fn_registrar_pagamento('T-PARC', 1, DATE '2026-06-30', 'BCO_A', 400.00);
    PERFORM pg_temp.verificar('D. Parciais e saldos', 'Simulação: após pagar 400 de 1.000 o saldo é 600',
        (SELECT fn_saldo_titulo_pagar(id) = 600 FROM titulo_pagar WHERE documento = 'T-PARC'));
    PERFORM fn_registrar_pagamento('T-PARC', 1, DATE '2026-06-30', 'BCO_A', 600.00);
    PERFORM pg_temp.verificar('D. Parciais e saldos', 'Simulação: após pagar mais 600 o saldo é 0 (quitado)',
        (SELECT fn_saldo_titulo_pagar(id) = 0 FROM titulo_pagar WHERE documento = 'T-PARC'));
END $$;

SELECT pg_temp.esperar_erro('D. Parciais e saldos', 'Simulação: pagar 0,01 em título quitado é bloqueado',
    $$SELECT fn_registrar_pagamento('T-PARC', 1, DATE '2026-06-30', 'BCO_A', 0.01)$$, 'P0001', 'excede o saldo');

SELECT pg_temp.esperar_erro('D. Parciais e saldos', 'Recebimento acima do saldo da parcela é bloqueado',
    $$SELECT fn_registrar_recebimento('V2026-007', 2, DATE '2026-06-30', 'BCO_B', 6000.01)$$, 'P0001', 'excede o saldo');

-- =============================================================================
-- E. AUSÊNCIA DE DUPLA CONTAGEM
-- =============================================================================
SELECT pg_temp.verificar('E. Dupla contagem', 'Receita bruta da DRE = soma das vendas (não das parcelas ou recebimentos)',
    (SELECT valor FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem = 1)
      = (SELECT sum(valor_venda) FROM venda)
    AND (SELECT valor FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem = 1) = 1197200.00,
    (SELECT 'receita bruta=' || valor FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem = 1));

SELECT pg_temp.verificar('E. Dupla contagem', 'Receita de vendas líquida de cancelamentos = soma das vendas ativas',
    (SELECT sum(valor) FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem IN (1, 2))
      = (SELECT sum(valor_venda) FROM venda WHERE situacao = 'ATIVA'));

SELECT pg_temp.verificar('E. Dupla contagem', 'CMV líquido do semestre = soma do custo das vendas ativas (919.050)',
    (SELECT -valor FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem = 5)
      = (SELECT sum(custo_veiculo_vendido) FROM venda WHERE situacao = 'ATIVA')
    AND (SELECT -valor FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem = 5) = 919050.00);

SELECT pg_temp.verificar('E. Dupla contagem', 'Compras e custos de veículos (estoque) não aparecem na DRE',
    NOT EXISTS (SELECT 1 FROM vw_lancamento_competencia l
                  JOIN categoria_financeira c ON c.codigo = l.categoria_codigo
                 WHERE c.natureza = 'ESTOQUE'));

SELECT pg_temp.verificar('E. Dupla contagem', 'Parcelas de vendas não geram receita (só a venda gera)',
    NOT EXISTS (SELECT 1 FROM vw_lancamento_competencia l
                  JOIN titulo_receber t ON t.id = l.origem_id
                 WHERE l.linha_dre = 'OUTRAS_RECEITAS' AND t.venda_id IS NOT NULL)
    AND (SELECT count(*) FROM vw_lancamento_competencia WHERE linha_dre = 'RECEITA_BRUTA') = (SELECT count(*) FROM venda));

SELECT pg_temp.verificar('E. Dupla contagem', 'Soma das DREs mensais = DRE do semestre (aditividade)',
    (SELECT sum(resultado_periodo) FROM vw_dre_mensal)
      = (SELECT valor FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem = 14)
    AND (SELECT sum(lucro_bruto) FROM vw_dre_mensal)
      = (SELECT valor FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem = 6),
    (SELECT 'resultado semestre=' || valor FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem = 14));

SELECT pg_temp.verificar('E. Dupla contagem', 'Extrato classificado não duplica movimentos (joins 1:1)',
    (SELECT count(*) FROM vw_movimento_caixa) = (SELECT count(*) FROM movimento_bancario)
    AND (SELECT sum(valor_assinado) FROM vw_movimento_caixa)
      = (SELECT sum(CASE tipo WHEN 'ENTRADA' THEN valor ELSE -valor END) FROM movimento_bancario));

SELECT pg_temp.verificar('E. Dupla contagem', 'Despesas por categoria/centro (competência) = despesas operacionais da DRE',
    (SELECT sum(valor_despesa) FROM vw_despesas_categoria_centro)
      = -(SELECT valor FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem = 10));

SELECT pg_temp.verificar('E. Dupla contagem', 'Fluxo mensal por grupo soma o mesmo que o resumo de caixa',
    (SELECT sum(fluxo_liquido) FROM vw_fluxo_caixa_mensal) = (SELECT sum(geracao_caixa) FROM vw_resumo_financeiro_mensal));

-- Simulação: receber uma parcela muda o caixa, mas não muda a receita da DRE.
DO $$
DECLARE
    v_receita_antes numeric; v_receita_depois numeric;
    v_caixa_antes   numeric; v_caixa_depois   numeric;
BEGIN
    SELECT valor INTO v_receita_antes FROM fn_dre(DATE '2026-06-01', DATE '2026-06-30') WHERE ordem = 4;
    SELECT saldo_final INTO v_caixa_antes FROM fn_resumo_financeiro(DATE '2026-06-01', DATE '2026-06-30') WHERE conta_codigo = 'TOTAL';
    PERFORM fn_registrar_recebimento('V2026-004', 3, DATE '2026-06-30', 'BCO_B', 20000.00);
    SELECT valor INTO v_receita_depois FROM fn_dre(DATE '2026-06-01', DATE '2026-06-30') WHERE ordem = 4;
    SELECT saldo_final INTO v_caixa_depois FROM fn_resumo_financeiro(DATE '2026-06-01', DATE '2026-06-30') WHERE conta_codigo = 'TOTAL';
    PERFORM pg_temp.verificar('E. Dupla contagem', 'Simulação: recebimento de parcela aumenta o caixa e não altera a receita',
        v_receita_depois = v_receita_antes AND v_caixa_depois - v_caixa_antes = 20000,
        'receita ' || v_receita_antes || ' -> ' || v_receita_depois || '; caixa +' || (v_caixa_depois - v_caixa_antes));
END $$;

-- =============================================================================
-- F. TRANSFERÊNCIAS E ESTORNOS
-- =============================================================================
SELECT pg_temp.verificar('F. Transferências e estornos', 'Cada transferência gera 1 saída e 1 entrada de mesmo valor e soma zero',
    NOT EXISTS (
        SELECT 1 FROM transferencia t
         WHERE (SELECT count(*) FROM movimento_bancario m WHERE m.transferencia_id = t.id) <> 2
            OR (SELECT sum(CASE m.tipo WHEN 'ENTRADA' THEN m.valor ELSE -m.valor END)
                  FROM movimento_bancario m WHERE m.transferencia_id = t.id) <> 0
            OR NOT EXISTS (SELECT 1 FROM movimento_bancario m WHERE m.transferencia_id = t.id
                             AND m.tipo = 'SAIDA' AND m.conta_bancaria_id = t.conta_origem_id AND m.valor = t.valor)),
    (SELECT count(*) || ' transferências' FROM transferencia));

SELECT pg_temp.verificar('F. Transferências e estornos', 'Transferências não entram em entradas/saídas nem na DRE',
    (SELECT sum(entradas) - sum(saidas) FROM vw_resumo_financeiro_mensal)
      = (SELECT sum(valor_assinado) FROM vw_movimento_caixa WHERE grupo_fluxo <> 'TRANSFERENCIA_INTERNA')
    AND NOT EXISTS (SELECT 1 FROM vw_lancamento_competencia WHERE origem ILIKE '%TRANSF%'));

DO $$
DECLARE
    v_dre_antes numeric; v_dre_depois numeric;
    v_total_antes numeric; v_total_depois numeric;
    v_a_antes numeric; v_a_depois numeric;
BEGIN
    SELECT valor INTO v_dre_antes FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem = 14;
    SELECT sum(saldo) INTO v_total_antes FROM fn_saldo_contas(DATE '2026-06-30');
    SELECT saldo INTO v_a_antes FROM fn_saldo_contas(DATE '2026-06-30') WHERE conta_codigo = 'BCO_A';
    PERFORM fn_registrar_transferencia('BCO_A', 'BCO_B', DATE '2026-06-30', 25000.00, 'Teste');
    SELECT valor INTO v_dre_depois FROM fn_dre(DATE '2026-01-01', DATE '2026-06-30') WHERE ordem = 14;
    SELECT sum(saldo) INTO v_total_depois FROM fn_saldo_contas(DATE '2026-06-30');
    SELECT saldo INTO v_a_depois FROM fn_saldo_contas(DATE '2026-06-30') WHERE conta_codigo = 'BCO_A';
    PERFORM pg_temp.verificar('F. Transferências e estornos',
        'Simulação: transferência muda saldos por conta, mas não o total nem o resultado',
        v_a_antes - v_a_depois = 25000 AND v_total_antes = v_total_depois AND v_dre_antes = v_dre_depois);
END $$;

SELECT pg_temp.verificar('F. Transferências e estornos', 'Cheque devolvido: recebimento estornado não reduz o saldo da parcela',
    (SELECT saldo_aberto = 6000 AND valor_recebido = 0 FROM fn_posicao_contas_receber(fn_data_referencia())
      WHERE documento = 'V2026-005' AND numero_parcela = 2)
    AND (SELECT sum(m.valor_assinado) = 0 FROM vw_movimento_caixa m
           JOIN recebimento r ON r.id = m.recebimento_id
           JOIN titulo_receber t ON t.id = r.titulo_receber_id
          WHERE t.documento = 'V2026-005' AND t.numero_parcela = 2));

SELECT pg_temp.verificar('F. Transferências e estornos', 'Pagamento estornado e refeito: marketing de abril pago uma única vez (líquido)',
    (SELECT fn_saldo_titulo_pagar(id) = 0 FROM titulo_pagar WHERE documento = 'MKT-2026-04')
    AND (SELECT sum(-m.valor_assinado) = 2400 FROM vw_movimento_caixa m
           JOIN pagamento p ON p.id = m.pagamento_id
           JOIN titulo_pagar t ON t.id = p.titulo_pagar_id WHERE t.documento = 'MKT-2026-04')
    AND (SELECT count(*) = 3 FROM movimento_bancario m
           JOIN pagamento p ON p.id = m.pagamento_id
           JOIN titulo_pagar t ON t.id = p.titulo_pagar_id WHERE t.documento = 'MKT-2026-04'));

SELECT pg_temp.verificar('F. Transferências e estornos', 'Venda cancelada: receita/CMV em março, reversão em abril, efeito líquido zero',
    (SELECT sum(valor) FILTER (WHERE date_trunc('month', data_competencia) = DATE '2026-03-01') = 99000 - 84000 - 1782
        AND sum(valor) FILTER (WHERE date_trunc('month', data_competencia) = DATE '2026-04-01') = -(99000 - 84000 - 1782)
        AND sum(valor) = 0
       FROM vw_lancamento_competencia l
      WHERE (l.origem IN ('VENDA', 'CANCELAMENTO_VENDA') AND l.origem_id = (SELECT id FROM venda WHERE numero_venda = 'V2026-006'))
         OR (l.origem IN ('TITULO_PAGAR', 'CANCELAMENTO_TITULO') AND l.origem_id = (SELECT id FROM titulo_pagar WHERE documento = 'COM-V2026-006'))));

SELECT pg_temp.verificar('F. Transferências e estornos', 'Venda cancelada: entrada devolvida ao cliente (caixa líquido zero) e títulos cancelados',
    (SELECT sum(m.valor_assinado) = 0 AND count(*) = 2 FROM vw_movimento_caixa m
       JOIN recebimento r ON r.id = m.recebimento_id
       JOIN titulo_receber t ON t.id = r.titulo_receber_id
       JOIN venda v ON v.id = t.venda_id WHERE v.numero_venda = 'V2026-006')
    AND NOT EXISTS (SELECT 1 FROM titulo_receber t JOIN venda v ON v.id = t.venda_id
                     WHERE v.numero_venda = 'V2026-006' AND t.situacao = 'ATIVO')
    AND (SELECT situacao = 'CANCELADO' FROM titulo_pagar WHERE documento = 'COM-V2026-006'));

SELECT pg_temp.verificar('F. Transferências e estornos', 'Despesa cancelada no mesmo mês tem efeito zero na DRE (rádio de junho)',
    (SELECT sum(valor) = 0 AND count(*) = 2 FROM vw_lancamento_competencia
      WHERE origem_id = (SELECT id FROM titulo_pagar WHERE documento = 'MKT-2026-06-RADIO')
        AND origem IN ('TITULO_PAGAR', 'CANCELAMENTO_TITULO')));

SELECT pg_temp.esperar_erro('F. Transferências e estornos', 'Estornar duas vezes o mesmo recebimento é bloqueado',
    $$SELECT fn_estornar_recebimento((SELECT r.id FROM recebimento r JOIN titulo_receber t ON t.id = r.titulo_receber_id
                                       WHERE t.documento = 'V2026-005' AND t.numero_parcela = 2), DATE '2026-06-30', 'Teste')$$,
    'P0001', 'já foi estornado');

SELECT pg_temp.esperar_erro('F. Transferências e estornos', 'Cancelar venda com comissão já paga é bloqueado',
    $$SELECT fn_cancelar_venda('V2026-001', DATE '2026-06-30', 'Teste')$$, 'P0001', 'comissão');

SELECT pg_temp.esperar_erro('F. Transferências e estornos', 'Cancelar título com pagamento efetivo é bloqueado',
    $$SELECT fn_cancelar_titulo_pagar('ALUG-2026-06', 1, DATE '2026-06-30', 'Teste')$$, 'P0001', 'estorne');

-- Simulação de cancelamento completo de uma venda parcelada com entrada recebida.
DO $$
DECLARE
    v_caixa_antes  numeric; v_caixa_depois  numeric;
    v_receber_antes numeric; v_receber_depois numeric;
    v_res_jun_antes numeric; v_res_jun_depois numeric;
BEGIN
    SELECT sum(saldo) INTO v_caixa_antes FROM fn_saldo_contas(DATE '2026-06-30');
    SELECT sum(saldo_aberto) INTO v_receber_antes FROM fn_posicao_contas_receber(DATE '2026-06-30');
    SELECT valor INTO v_res_jun_antes FROM fn_dre(DATE '2026-06-01', DATE '2026-06-30') WHERE ordem = 6;
    PERFORM fn_cancelar_venda('V2026-010', DATE '2026-06-30', 'Simulação de distrato');
    SELECT sum(saldo) INTO v_caixa_depois FROM fn_saldo_contas(DATE '2026-06-30');
    SELECT sum(saldo_aberto) INTO v_receber_depois FROM fn_posicao_contas_receber(DATE '2026-06-30');
    SELECT valor INTO v_res_jun_depois FROM fn_dre(DATE '2026-06-01', DATE '2026-06-30') WHERE ordem = 6;
    PERFORM pg_temp.verificar('F. Transferências e estornos',
        'Simulação: cancelar T-Cross devolve 49.900, zera 80.000 a receber, estorna 22.200 de lucro bruto e libera o veículo',
        v_caixa_antes - v_caixa_depois = 49900
        AND v_receber_antes - v_receber_depois = 80000
        AND v_res_jun_antes - v_res_jun_depois = 22200
        AND (SELECT situacao = 'DISPONIVEL' FROM veiculo WHERE chassi = 'FCAR2600000000009')
        AND (SELECT situacao = 'CANCELADO' FROM titulo_pagar WHERE documento = 'COM-V2026-010'),
        'caixa -' || (v_caixa_antes - v_caixa_depois) || '; a receber -' || (v_receber_antes - v_receber_depois)
        || '; lucro bruto jun -' || (v_res_jun_antes - v_res_jun_depois));
END $$;

-- =============================================================================
-- G. RECONCILIAÇÃO DE SALDOS
-- (a partir daqui os dados incluem as simulações acima; os testes são de identidade)
-- =============================================================================
SELECT pg_temp.verificar('G. Reconciliação', 'Por conta e mês: inicial + entradas - saídas + transf. recebidas - enviadas = final',
    NOT EXISTS (SELECT 1 FROM vw_resumo_financeiro_mensal_conta
                 WHERE saldo_inicial + entradas - saidas + transferencias_recebidas - transferencias_enviadas <> saldo_final));

SELECT pg_temp.verificar('G. Reconciliação', 'Saldo final de um mês = saldo inicial do mês seguinte (por conta)',
    NOT EXISTS (SELECT 1 FROM (
                    SELECT conta_codigo, saldo_final,
                           lead(saldo_inicial) OVER (PARTITION BY conta_codigo ORDER BY mes) AS prox_inicial
                      FROM vw_resumo_financeiro_mensal_conta) x
                 WHERE prox_inicial IS NOT NULL AND prox_inicial <> saldo_final));

SELECT pg_temp.verificar('G. Reconciliação', 'Saldo final consolidado = saldos iniciais + soma de todos os movimentos',
    (SELECT saldo_final FROM fn_resumo_financeiro(DATE '2026-01-01', DATE '2026-06-30') WHERE conta_codigo = 'TOTAL')
      = (SELECT sum(saldo_inicial) FROM conta_bancaria)
        + (SELECT sum(CASE tipo WHEN 'ENTRADA' THEN valor ELSE -valor END) FROM movimento_bancario
            WHERE data_movimento <= DATE '2026-06-30'));

SELECT pg_temp.verificar('G. Reconciliação', 'Resumo do período = saldos de fn_saldo_contas na data final',
    NOT EXISTS (SELECT 1 FROM fn_resumo_financeiro(DATE '2026-01-01', DATE '2026-06-30') r
                  JOIN fn_saldo_contas(DATE '2026-06-30') s ON s.conta_codigo = r.conta_codigo
                 WHERE r.saldo_final <> s.saldo));

SELECT pg_temp.verificar('G. Reconciliação', 'Último saldo do fluxo diário = saldo final consolidado',
    (SELECT saldo_final_dia FROM vw_fluxo_caixa_diario ORDER BY data_movimento DESC LIMIT 1)
      = (SELECT saldo_final FROM fn_resumo_financeiro(DATE '2026-01-01', DATE '2026-06-30') WHERE conta_codigo = 'TOTAL'));

SELECT pg_temp.verificar('G. Reconciliação', 'Transferências se anulam no consolidado de cada mês',
    NOT EXISTS (SELECT 1 FROM vw_resumo_financeiro_mensal_conta
                 WHERE conta_codigo = 'TOTAL' AND transferencias_recebidas <> transferencias_enviadas));

SELECT pg_temp.verificar('G. Reconciliação', 'Resumo de um trimestre = soma dos três meses',
    (SELECT entradas - saidas FROM fn_resumo_financeiro(DATE '2026-04-01', DATE '2026-06-30') WHERE conta_codigo = 'TOTAL')
      = (SELECT sum(geracao_caixa) FROM vw_resumo_financeiro_mensal WHERE mes BETWEEN DATE '2026-04-01' AND DATE '2026-06-01'));

-- =============================================================================
-- H. COERÊNCIA ENTRE CAIXA E COMPETÊNCIA
-- =============================================================================
SELECT pg_temp.verificar('H. Caixa x competência', 'Vendas ativas = principal recebido + saldo a receber das vendas',
    (SELECT sum(valor_venda) FROM venda WHERE situacao = 'ATIVA')
      = (SELECT COALESCE(sum(r.valor_principal), 0) FROM recebimento r
           JOIN titulo_receber t ON t.id = r.titulo_receber_id
           JOIN venda v ON v.id = t.venda_id
          WHERE r.situacao = 'EFETIVO' AND v.situacao = 'ATIVA')
        + (SELECT COALESCE(sum(fn_saldo_titulo_receber(t.id)), 0) FROM titulo_receber t
           JOIN venda v ON v.id = t.venda_id WHERE v.situacao = 'ATIVA' AND t.situacao = 'ATIVO'));

SELECT pg_temp.verificar('H. Caixa x competência', 'Despesas da DRE = principal pago + saldo a pagar dos títulos de despesa',
    -(SELECT sum(valor) FROM vw_lancamento_competencia
       WHERE linha_dre IN ('DESPESA_VENDAS', 'DESPESA_PESSOAL', 'DESPESA_ADMINISTRATIVA'))
      = (SELECT COALESCE(sum(p.valor_principal), 0) FROM pagamento p
           JOIN titulo_pagar t ON t.id = p.titulo_pagar_id
           JOIN categoria_financeira c ON c.id = t.categoria_id
          WHERE p.situacao = 'EFETIVO' AND c.natureza = 'DESPESA')
        + (SELECT COALESCE(sum(fn_saldo_titulo_pagar(t.id)), 0) FROM titulo_pagar t
           JOIN categoria_financeira c ON c.id = t.categoria_id
          WHERE c.natureza = 'DESPESA' AND t.situacao = 'ATIVO'));

SELECT pg_temp.verificar('H. Caixa x competência', 'Estoque: compras + custos = estoque final + CMV líquido',
    (SELECT sum(valor_compra) FROM compra_veiculo) + (SELECT sum(valor) FROM custo_veiculo)
      = (SELECT COALESCE(sum(custo_total), 0) FROM fn_estoque_veiculos(DATE '2026-06-30'))
        - (SELECT COALESCE(sum(valor), 0) FROM vw_lancamento_competencia WHERE linha_dre = 'CMV'));

SELECT pg_temp.verificar('H. Caixa x competência', 'Resultado financeiro da DRE = juros/descontos das baixas efetivas',
    (SELECT COALESCE(sum(valor), 0) FROM vw_lancamento_competencia
      WHERE linha_dre IN ('RECEITA_FINANCEIRA', 'DESPESA_FINANCEIRA'))
      = (SELECT COALESCE(sum(valor_juros_multa - valor_desconto), 0) FROM recebimento WHERE situacao = 'EFETIVO')
        - (SELECT COALESCE(sum(valor_juros_multa - valor_desconto), 0) FROM pagamento WHERE situacao = 'EFETIVO'));

-- Ponte (método indireto): resultado = variação do caixa + a receber - a pagar + estoque
-- (no início do período não havia saldos de receber, pagar ou estoque).
SELECT pg_temp.verificar('H. Caixa x competência', 'Ponte caixa-competência: resultado = Δcaixa + a receber - a pagar + estoque',
    (SELECT sum(valor) FROM vw_lancamento_competencia WHERE data_competencia <= DATE '2026-06-30')
      = ((SELECT sum(saldo) FROM fn_saldo_contas(DATE '2026-06-30')) - (SELECT sum(saldo_inicial) FROM conta_bancaria))
        + (SELECT sum(saldo_aberto) FROM fn_posicao_contas_receber(DATE '2026-06-30'))
        - (SELECT sum(saldo_aberto) FROM fn_posicao_contas_pagar(DATE '2026-06-30'))
        + (SELECT COALESCE(sum(custo_total), 0) FROM fn_estoque_veiculos(DATE '2026-06-30')));

-- =============================================================================
-- RESULTADO
-- =============================================================================
\o
\echo
\echo '================ RESULTADO DOS TESTES ================'
SELECT ordem AS "#", grupo, teste,
       CASE WHEN aprovado THEN 'APROVADO' ELSE 'REPROVADO' END AS resultado
  FROM resultado_teste
 ORDER BY ordem;

SELECT count(*)                              AS total,
       count(*) FILTER (WHERE aprovado)      AS aprovados,
       count(*) FILTER (WHERE NOT aprovado)  AS reprovados
  FROM resultado_teste;

\echo 'Detalhes dos testes reprovados (vazio = nenhum):'
SELECT ordem AS "#", teste, detalhe FROM resultado_teste WHERE NOT aprovado ORDER BY ordem;

-- Falha a execução (psql sai com código 3) se houver teste reprovado.
DO $$
DECLARE v_falhas integer;
BEGIN
    SELECT count(*) INTO v_falhas FROM resultado_teste WHERE NOT aprovado;
    IF v_falhas > 0 THEN
        RAISE EXCEPTION '% teste(s) reprovado(s)', v_falhas;
    END IF;
END $$;

-- Desfaz as simulações: o banco volta exatamente ao estado do seed.
ROLLBACK;
\echo 'Todos os testes foram aprovados. Simulações desfeitas (ROLLBACK).'
