-- =============================================================================
-- Fast Car - Sistema Financeiro em SQL
-- Arquivo : sql/05_reports.sql
-- Objetivo: relatórios gerenciais prontos para execução no psql.
-- Depende : 01 a 04 (somente leitura: não altera dados)
--
-- Período padrão: 2026-01-01 a 2026-06-30. Para outro período:
--   psql -d fastcar -v inicio=2026-04-01 -v fim=2026-06-30 -f sql/05_reports.sql
-- Data-base das posições (vencidos/a vencer): -v data_base=2026-05-31
-- =============================================================================

\set ON_ERROR_STOP on
SET search_path TO fastcar, public;

\if :{?inicio}
\else
    \set inicio 2026-01-01
\endif
\if :{?fim}
\else
    \set fim 2026-06-30
\endif
\if :{?data_base}
\else
    \set data_base 2026-06-30
\endif

\pset null '-'
\echo
\echo '=================================================================='
\echo ' FAST CAR - RELATÓRIOS GERENCIAIS'
\echo ' Período:' :inicio 'a' :fim '| Data-base das posições:' :data_base
\echo '=================================================================='

-- -----------------------------------------------------------------------------
\echo
\echo '1. RESUMO FINANCEIRO DO PERÍODO (regime de caixa), por conta e TOTAL'
\echo '   saldo_final = saldo_inicial + entradas - saídas + transferências recebidas - enviadas'
-- -----------------------------------------------------------------------------
SELECT * FROM fn_resumo_financeiro(:'inicio', :'fim');

-- -----------------------------------------------------------------------------
\echo
\echo '2. RESUMO FINANCEIRO MENSAL CONSOLIDADO (caixa)'
\echo '   geracao_caixa = entradas - saídas; transferências internas somam zero'
-- -----------------------------------------------------------------------------
SELECT * FROM vw_resumo_financeiro_mensal
 WHERE mes BETWEEN date_trunc('month', :'inicio'::date) AND :'fim';

-- -----------------------------------------------------------------------------
\echo
\echo '3. FLUXO DE CAIXA MENSAL POR GRUPO (valores negativos = saídas)'
-- -----------------------------------------------------------------------------
SELECT * FROM vw_fluxo_caixa_mensal
 WHERE mes BETWEEN date_trunc('month', :'inicio'::date) AND :'fim';

-- -----------------------------------------------------------------------------
\echo
\echo '4. FLUXO DE CAIXA DIÁRIO (dias com movimento, últimos 15 do período)'
-- -----------------------------------------------------------------------------
SELECT * FROM (
    SELECT * FROM fn_fluxo_caixa_diario(:'inicio', :'fim') ORDER BY data_movimento DESC LIMIT 15
) d ORDER BY data_movimento;

-- -----------------------------------------------------------------------------
\echo
\echo '5. DRE GERENCIAL DO PERÍODO (regime de competência)'
\echo '   Gerencial e simplificada: não substitui a contabilidade oficial.'
-- -----------------------------------------------------------------------------
SELECT * FROM fn_dre(:'inicio', :'fim');

-- -----------------------------------------------------------------------------
\echo
\echo '6. DRE GERENCIAL MENSAL'
-- -----------------------------------------------------------------------------
SELECT mes, receita_bruta, cancelamentos, outras_receitas, receita_liquida, cmv, lucro_bruto,
       despesas_operacionais, resultado_financeiro, resultado_periodo, margem_bruta_pct, margem_liquida_pct
  FROM vw_dre_mensal
 WHERE mes BETWEEN date_trunc('month', :'inicio'::date) AND :'fim';

-- -----------------------------------------------------------------------------
\echo
\echo '7. COMPARAÇÃO ENTRE MESES: resultado (competência) x geração de caixa'
-- -----------------------------------------------------------------------------
SELECT * FROM vw_dre_comparativo_mensal
 WHERE mes BETWEEN date_trunc('month', :'inicio'::date) AND :'fim';

-- -----------------------------------------------------------------------------
\echo
\echo '8. CONTAS EM ABERTO NA DATA-BASE: vencidas x a vencer'
-- -----------------------------------------------------------------------------
SELECT 'RECEBER' AS tipo, situacao, count(*) AS titulos,
       sum(valor_titulo) AS valor_original, sum(valor_recebido) AS valor_baixado, sum(saldo_aberto) AS saldo_aberto
  FROM fn_posicao_contas_receber(:'data_base') WHERE saldo_aberto > 0 GROUP BY situacao
UNION ALL
SELECT 'PAGAR', situacao, count(*), sum(valor_titulo), sum(valor_pago), sum(saldo_aberto)
  FROM fn_posicao_contas_pagar(:'data_base') WHERE saldo_aberto > 0 GROUP BY situacao
 ORDER BY 1 DESC, 2;

\echo
\echo '8a. Contas a receber em aberto (detalhe)'
SELECT documento, numero_parcela AS parc, cliente, data_vencimento, valor_titulo, valor_recebido,
       saldo_aberto, dias_atraso, situacao, faixa_atraso
  FROM fn_posicao_contas_receber(:'data_base')
 WHERE saldo_aberto > 0;

\echo
\echo '8b. Contas a pagar em aberto (detalhe)'
SELECT documento, numero_parcela AS parc, favorecido, categoria_nome, data_vencimento, valor_titulo,
       valor_pago, saldo_aberto, dias_atraso, situacao
  FROM fn_posicao_contas_pagar(:'data_base')
 WHERE saldo_aberto > 0;

-- -----------------------------------------------------------------------------
\echo
\echo '9. VALORES EM ABERTO APÓS PAGAMENTOS PARCIAIS'
-- -----------------------------------------------------------------------------
SELECT 'RECEBER' AS tipo, documento, numero_parcela AS parc, cliente AS contraparte,
       valor_titulo, valor_recebido AS valor_baixado, saldo_aberto, situacao
  FROM fn_posicao_contas_receber(:'data_base') WHERE recebido_parcial
UNION ALL
SELECT 'PAGAR', documento, numero_parcela, favorecido, valor_titulo, valor_pago, saldo_aberto, situacao
  FROM fn_posicao_contas_pagar(:'data_base') WHERE pago_parcial;

-- -----------------------------------------------------------------------------
\echo
\echo '10. INADIMPLÊNCIA POR CLIENTE E FAIXA DE ATRASO'
-- -----------------------------------------------------------------------------
SELECT cliente, faixa_atraso, count(*) AS titulos_vencidos, sum(saldo_aberto) AS saldo_vencido,
       max(dias_atraso) AS maior_atraso_dias
  FROM fn_posicao_contas_receber(:'data_base')
 WHERE situacao = 'VENCIDO'
 GROUP BY cliente, faixa_atraso
 ORDER BY saldo_vencido DESC;

\echo
\echo '10a. Inadimplência por faixa (data de referência configurada)'
SELECT * FROM vw_inadimplencia_faixa;

-- -----------------------------------------------------------------------------
\echo
\echo '11. DESPESAS OPERACIONAIS POR CATEGORIA E CENTRO DE CUSTO'
\echo '    (competência: reconhecidas no período, líquidas de cancelamentos)'
-- -----------------------------------------------------------------------------
SELECT categoria_codigo, categoria_nome, centro_custo_codigo, sum(valor_despesa) AS despesa_competencia
  FROM vw_despesas_categoria_centro
 WHERE mes BETWEEN date_trunc('month', :'inicio'::date) AND :'fim'
 GROUP BY categoria_codigo, categoria_nome, centro_custo_codigo
 ORDER BY categoria_codigo, centro_custo_codigo;

\echo
\echo '11a. Saídas de caixa por categoria e centro de custo (pagas no período)'
SELECT categoria_codigo, categoria_nome, centro_custo_codigo, sum(valor_pago) AS pago_no_periodo
  FROM vw_pagamentos_categoria_centro
 WHERE mes BETWEEN date_trunc('month', :'inicio'::date) AND :'fim'
 GROUP BY categoria_codigo, categoria_nome, centro_custo_codigo
 ORDER BY categoria_codigo, centro_custo_codigo;

-- -----------------------------------------------------------------------------
\echo
\echo '12. MARGEM POR VEÍCULO VENDIDO (vendas ativas no período)'
-- -----------------------------------------------------------------------------
SELECT numero_venda, data_venda, veiculo, dias_em_estoque, valor_venda, custo_aquisicao, custos_adicionais,
       custo_total, lucro_bruto, margem_bruta_pct, comissao, margem_contribuicao, margem_contribuicao_pct
  FROM vw_margem_veiculo_vendido
 WHERE data_venda BETWEEN :'inicio' AND :'fim';

-- -----------------------------------------------------------------------------
\echo
\echo '13. VENDAS E COMISSÕES POR VENDEDOR (período)'
-- -----------------------------------------------------------------------------
SELECT vendedor,
       sum(vendas_ativas)     AS vendas_ativas,
       sum(vendas_canceladas) AS vendas_canceladas,
       sum(faturamento)       AS faturamento,
       sum(lucro_bruto)       AS lucro_bruto,
       sum(comissao_devida)   AS comissao_devida,
       sum(comissao_paga)     AS comissao_paga,
       sum(comissao_a_pagar)  AS comissao_a_pagar
  FROM vw_vendas_comissoes_vendedor
 WHERE mes BETWEEN date_trunc('month', :'inicio'::date) AND :'fim'
 GROUP BY vendedor
 ORDER BY faturamento DESC;

-- -----------------------------------------------------------------------------
\echo
\echo '14. ESTOQUE DE VEÍCULOS NA DATA-BASE (valor de custo)'
-- -----------------------------------------------------------------------------
SELECT * FROM fn_estoque_veiculos(:'data_base');

\echo
\echo '14a. Evolução mensal do estoque'
SELECT * FROM vw_estoque_mensal;

-- -----------------------------------------------------------------------------
\echo
\echo '15. SALDO DAS CONTAS NA DATA-BASE'
-- -----------------------------------------------------------------------------
SELECT * FROM fn_saldo_contas(:'data_base');
