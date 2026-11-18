-- =============================================================================
-- Fast Car - Sistema Financeiro em SQL
-- Arquivo : sql/04_views.sql
-- Objetivo: views e funções de relatório (caixa, competência, posições).
-- Depende : 01_schema.sql e 02_functions.sql (os dados podem ser carregados antes ou depois)
--
-- Duas fontes, nunca misturadas:
--   * REGIME DE CAIXA      -> somente movimento_bancario (dinheiro que entrou/saiu).
--   * REGIME DE COMPETÊNCIA -> vw_lancamento_competencia (venda, CMV, despesas por
--                              data de competência, juros e descontos).
-- Títulos a receber/pagar são posições (direitos e obrigações), não receita nem despesa.
--
-- Funções com parâmetros de data (fn_*) permitem consultar qualquer período;
-- as views (vw_*) aplicam essas funções aos meses de janeiro de 2026 até a
-- data de referência (tabela configuracao).
-- =============================================================================

\set ON_ERROR_STOP on
SET search_path TO fastcar, public;

-- -----------------------------------------------------------------------------
-- Meses do período de análise: do mês seguinte ao saldo inicial até a data de referência.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_mes_analise AS
SELECT m::date                                      AS mes,
       (m + interval '1 month - 1 day')::date       AS fim_mes
  FROM generate_series(
           date_trunc('month', (SELECT min(data_saldo_inicial) FROM conta_bancaria) + 1),
           date_trunc('month', fn_data_referencia()),
           interval '1 month') AS m;
COMMENT ON VIEW vw_mes_analise IS 'Meses analisados: do primeiro mês após o saldo inicial até o mês da data de referência.';

-- =============================================================================
-- REGIME DE CAIXA
-- =============================================================================

-- Extrato classificado: cada movimento bancário com sinal, categoria e grupo de fluxo.
CREATE OR REPLACE VIEW vw_movimento_caixa AS
SELECT m.id                                                   AS movimento_id,
       m.conta_bancaria_id,
       cb.codigo                                              AS conta_codigo,
       m.data_movimento,
       date_trunc('month', m.data_movimento)::date            AS mes,
       m.tipo,
       m.natureza,
       m.valor,
       CASE m.tipo WHEN 'ENTRADA' THEN m.valor ELSE -m.valor END AS valor_assinado,
       CASE
           WHEN m.natureza = 'TRANSFERENCIA'                       THEN 'TRANSFERENCIA_INTERNA'
           WHEN m.recebimento_id IS NOT NULL AND tr.venda_id IS NOT NULL THEN 'RECEBIMENTO_VENDA_VEICULO'
           WHEN m.recebimento_id IS NOT NULL                       THEN 'RECEBIMENTO_OUTRAS_RECEITAS'
           WHEN tp.compra_veiculo_id IS NOT NULL                   THEN 'PAGAMENTO_AQUISICAO_VEICULO'
           WHEN tp.custo_veiculo_id IS NOT NULL                    THEN 'PAGAMENTO_CUSTO_VEICULO'
           WHEN tp.venda_id IS NOT NULL                            THEN 'PAGAMENTO_COMISSAO'
           ELSE                                                         'PAGAMENTO_DESPESA_OPERACIONAL'
       END                                                    AS grupo_fluxo,
       COALESCE(catr.codigo, catp.codigo)                     AS categoria_codigo,
       COALESCE(catr.nome, catp.nome, 'Transferência entre contas próprias') AS categoria_nome,
       COALESCE(ccr.codigo, ccp.codigo)                       AS centro_custo_codigo,
       COALESCE(tr.documento, tp.documento)                   AS documento,
       m.historico,
       m.recebimento_id,
       m.pagamento_id,
       m.transferencia_id
  FROM movimento_bancario m
  JOIN conta_bancaria cb            ON cb.id = m.conta_bancaria_id
  LEFT JOIN recebimento r           ON r.id = m.recebimento_id
  LEFT JOIN titulo_receber tr       ON tr.id = r.titulo_receber_id
  LEFT JOIN categoria_financeira catr ON catr.id = tr.categoria_id
  LEFT JOIN centro_custo ccr        ON ccr.id = tr.centro_custo_id
  LEFT JOIN pagamento p             ON p.id = m.pagamento_id
  LEFT JOIN titulo_pagar tp         ON tp.id = p.titulo_pagar_id
  LEFT JOIN categoria_financeira catp ON catp.id = tp.categoria_id
  LEFT JOIN centro_custo ccp        ON ccp.id = tp.centro_custo_id;
COMMENT ON VIEW vw_movimento_caixa IS 'Extrato de todas as contas com sinal (+ entrada, - saída), categoria, centro de custo e grupo de fluxo. Estornos aparecem no sentido contrário, na data do estorno.';

-- Saldo de cada conta ao final de uma data.
CREATE OR REPLACE FUNCTION fn_saldo_contas(p_data date)
RETURNS TABLE (conta_codigo varchar, conta_descricao varchar, saldo numeric(14,2))
LANGUAGE sql STABLE
AS $$
    SELECT cb.codigo, cb.descricao,
           cb.saldo_inicial + COALESCE(sum(CASE m.tipo WHEN 'ENTRADA' THEN m.valor ELSE -m.valor END), 0)
      FROM fastcar.conta_bancaria cb
      LEFT JOIN fastcar.movimento_bancario m
             ON m.conta_bancaria_id = cb.id AND m.data_movimento <= p_data
     GROUP BY cb.id, cb.codigo, cb.descricao, cb.saldo_inicial
     ORDER BY cb.id;
$$;
COMMENT ON FUNCTION fn_saldo_contas(date) IS 'Saldo de cada conta ao final do dia informado (saldo inicial + movimentos até a data).';

-- Resumo financeiro de um período por conta e total consolidado.
-- Entradas e saídas excluem transferências internas, que aparecem em colunas próprias.
-- saldo_final = saldo_inicial + entradas - saidas + transferencias_recebidas - transferencias_enviadas
CREATE OR REPLACE FUNCTION fn_resumo_financeiro(p_inicio date, p_fim date)
RETURNS TABLE (
    conta_codigo             varchar,
    saldo_inicial            numeric(14,2),
    entradas                 numeric(14,2),
    saidas                   numeric(14,2),
    transferencias_recebidas numeric(14,2),
    transferencias_enviadas  numeric(14,2),
    saldo_final              numeric(14,2)
)
LANGUAGE plpgsql STABLE SET search_path = fastcar, public
AS $$
BEGIN
    IF p_fim < p_inicio THEN
        RAISE EXCEPTION 'Período inválido: % a %', p_inicio, p_fim;
    END IF;
    RETURN QUERY
    WITH por_conta AS (
        SELECT cb.id,
               cb.codigo,
               cb.saldo_inicial + COALESCE(sum(CASE WHEN m.data_movimento < p_inicio
                                                    THEN CASE m.tipo WHEN 'ENTRADA' THEN m.valor ELSE -m.valor END END), 0) AS saldo_ini,
               COALESCE(sum(m.valor) FILTER (WHERE m.data_movimento BETWEEN p_inicio AND p_fim
                                               AND m.natureza <> 'TRANSFERENCIA' AND m.tipo = 'ENTRADA'), 0) AS ent,
               COALESCE(sum(m.valor) FILTER (WHERE m.data_movimento BETWEEN p_inicio AND p_fim
                                               AND m.natureza <> 'TRANSFERENCIA' AND m.tipo = 'SAIDA'), 0)   AS sai,
               COALESCE(sum(m.valor) FILTER (WHERE m.data_movimento BETWEEN p_inicio AND p_fim
                                               AND m.natureza = 'TRANSFERENCIA' AND m.tipo = 'ENTRADA'), 0)  AS tr_in,
               COALESCE(sum(m.valor) FILTER (WHERE m.data_movimento BETWEEN p_inicio AND p_fim
                                               AND m.natureza = 'TRANSFERENCIA' AND m.tipo = 'SAIDA'), 0)    AS tr_out
          FROM conta_bancaria cb
          LEFT JOIN movimento_bancario m ON m.conta_bancaria_id = cb.id AND m.data_movimento <= p_fim
         GROUP BY cb.id, cb.codigo, cb.saldo_inicial
    )
    SELECT COALESCE(codigo, 'TOTAL')::varchar,
           sum(saldo_ini)::numeric(14,2),
           sum(ent)::numeric(14,2),
           sum(sai)::numeric(14,2),
           sum(tr_in)::numeric(14,2),
           sum(tr_out)::numeric(14,2),
           sum(saldo_ini + ent - sai + tr_in - tr_out)::numeric(14,2)
      FROM por_conta
     GROUP BY GROUPING SETS ((id, codigo), ())
     ORDER BY GROUPING(id, codigo), min(id);
END $$;
COMMENT ON FUNCTION fn_resumo_financeiro(date, date) IS 'Resumo de caixa do período por conta e TOTAL: saldo inicial, entradas, saídas, transferências e saldo final.';

CREATE OR REPLACE VIEW vw_resumo_financeiro_mensal_conta AS
SELECT ma.mes, r.*
  FROM vw_mes_analise ma
 CROSS JOIN LATERAL fn_resumo_financeiro(ma.mes, ma.fim_mes) r
 ORDER BY ma.mes, r.conta_codigo = 'TOTAL', r.conta_codigo;
COMMENT ON VIEW vw_resumo_financeiro_mensal_conta IS 'Resumo de caixa mês a mês por conta, com linha TOTAL consolidada.';

CREATE OR REPLACE VIEW vw_resumo_financeiro_mensal AS
SELECT mes, saldo_inicial, entradas, saidas,
       entradas - saidas AS geracao_caixa,
       transferencias_recebidas - transferencias_enviadas AS transferencias_liquidas,
       saldo_final
  FROM vw_resumo_financeiro_mensal_conta
 WHERE conta_codigo = 'TOTAL'
 ORDER BY mes;
COMMENT ON VIEW vw_resumo_financeiro_mensal IS 'Resumo de caixa consolidado por mês. Transferências internas somam zero no consolidado.';

-- Fluxo de caixa diário consolidado (sem transferências internas) com saldo acumulado.
CREATE OR REPLACE FUNCTION fn_fluxo_caixa_diario(p_inicio date, p_fim date)
RETURNS TABLE (
    data_movimento  date,
    entradas        numeric(14,2),
    saidas          numeric(14,2),
    saldo_dia       numeric(14,2),
    saldo_final_dia numeric(14,2)
)
LANGUAGE sql STABLE
AS $$
    WITH abertura AS (
        SELECT sum(saldo) AS saldo FROM fastcar.fn_saldo_contas(p_inicio - 1)
    ),
    dia AS (
        SELECT m.data_movimento,
               COALESCE(sum(m.valor) FILTER (WHERE m.tipo = 'ENTRADA' AND m.natureza <> 'TRANSFERENCIA'), 0) AS ent,
               COALESCE(sum(m.valor) FILTER (WHERE m.tipo = 'SAIDA'   AND m.natureza <> 'TRANSFERENCIA'), 0) AS sai
          FROM fastcar.movimento_bancario m
         WHERE m.data_movimento BETWEEN p_inicio AND p_fim
         GROUP BY m.data_movimento
    )
    SELECT d.data_movimento,
           d.ent::numeric(14,2),
           d.sai::numeric(14,2),
           (d.ent - d.sai)::numeric(14,2),
           (a.saldo + sum(d.ent - d.sai) OVER (ORDER BY d.data_movimento))::numeric(14,2)
      FROM dia d CROSS JOIN abertura a
     ORDER BY d.data_movimento;
$$;
COMMENT ON FUNCTION fn_fluxo_caixa_diario(date, date) IS 'Fluxo de caixa diário consolidado (dias com movimento), com saldo acumulado de todas as contas.';

CREATE OR REPLACE VIEW vw_fluxo_caixa_diario AS
SELECT *
  FROM fn_fluxo_caixa_diario((SELECT min(mes) FROM vw_mes_analise), fn_data_referencia());
COMMENT ON VIEW vw_fluxo_caixa_diario IS 'Fluxo de caixa diário consolidado de janeiro até a data de referência.';

-- Fluxo de caixa mensal por grupo (formato longo) e consolidado.
CREATE OR REPLACE VIEW vw_fluxo_caixa_mensal_grupo AS
SELECT mes,
       grupo_fluxo,
       sum(valor) FILTER (WHERE tipo = 'ENTRADA') AS entradas,
       sum(valor) FILTER (WHERE tipo = 'SAIDA')   AS saidas,
       sum(valor_assinado)                        AS liquido
  FROM vw_movimento_caixa
 GROUP BY mes, grupo_fluxo
 ORDER BY mes, grupo_fluxo;
COMMENT ON VIEW vw_fluxo_caixa_mensal_grupo IS 'Fluxo de caixa mensal por grupo (recebimento de vendas, aquisição de veículos, despesas etc.). Valores incluem estornos.';

CREATE OR REPLACE VIEW vw_fluxo_caixa_mensal AS
SELECT ma.mes,
       COALESCE(sum(c.valor_assinado) FILTER (WHERE c.grupo_fluxo = 'RECEBIMENTO_VENDA_VEICULO'), 0)     AS recebimentos_vendas,
       COALESCE(sum(c.valor_assinado) FILTER (WHERE c.grupo_fluxo = 'RECEBIMENTO_OUTRAS_RECEITAS'), 0)   AS recebimentos_outros,
       COALESCE(sum(c.valor_assinado) FILTER (WHERE c.grupo_fluxo = 'PAGAMENTO_AQUISICAO_VEICULO'), 0)   AS pagamentos_aquisicao_veiculos,
       COALESCE(sum(c.valor_assinado) FILTER (WHERE c.grupo_fluxo = 'PAGAMENTO_CUSTO_VEICULO'), 0)       AS pagamentos_custos_veiculos,
       COALESCE(sum(c.valor_assinado) FILTER (WHERE c.grupo_fluxo = 'PAGAMENTO_COMISSAO'), 0)            AS pagamentos_comissoes,
       COALESCE(sum(c.valor_assinado) FILTER (WHERE c.grupo_fluxo = 'PAGAMENTO_DESPESA_OPERACIONAL'), 0) AS pagamentos_despesas,
       COALESCE(sum(c.valor_assinado) FILTER (WHERE c.grupo_fluxo <> 'TRANSFERENCIA_INTERNA'), 0)        AS fluxo_liquido,
       COALESCE(sum(c.valor_assinado) FILTER (WHERE c.grupo_fluxo = 'TRANSFERENCIA_INTERNA'), 0)         AS transferencias_liquidas
  FROM vw_mes_analise ma
  LEFT JOIN vw_movimento_caixa c ON c.mes = ma.mes
 GROUP BY ma.mes
 ORDER BY ma.mes;
COMMENT ON VIEW vw_fluxo_caixa_mensal IS 'Fluxo de caixa mensal consolidado por grupo (valores com sinal: negativos são saídas). Transferências líquidas somam zero.';

-- =============================================================================
-- REGIME DE COMPETÊNCIA
-- =============================================================================

-- Razão gerencial de resultado: um lançamento por fato econômico reconhecido.
-- Valor positivo aumenta o resultado; negativo reduz.
CREATE OR REPLACE VIEW vw_lancamento_competencia AS
-- (1) Receita bruta: toda venda, na data da venda (mesmo que depois seja cancelada).
SELECT v.data_venda AS data_competencia, 'RECEITA_BRUTA'::varchar(30) AS linha_dre,
       '1.01'::varchar(10) AS categoria_codigo, 'Venda de veículos'::varchar(80) AS categoria_nome,
       'COM'::varchar(10) AS centro_custo_codigo, v.valor_venda AS valor,
       'VENDA'::varchar(20) AS origem, v.id::bigint AS origem_id, ('Venda ' || v.numero_venda)::varchar(200) AS historico
  FROM venda v
UNION ALL
-- (2) Cancelamento de venda: reversão da receita no mês do cancelamento.
SELECT v.data_cancelamento, 'CANCELAMENTO_VENDA', '1.01', 'Venda de veículos', 'COM', -v.valor_venda,
       'CANCELAMENTO_VENDA', v.id, 'Cancelamento da venda ' || v.numero_venda
  FROM venda v WHERE v.situacao = 'CANCELADA'
UNION ALL
-- (3) CMV: custo do veículo (aquisição + custos adicionais) na data da venda.
SELECT v.data_venda, 'CMV', NULL, 'Custo dos veículos vendidos', 'COM', -v.custo_veiculo_vendido,
       'VENDA', v.id, 'CMV da venda ' || v.numero_venda
  FROM venda v
UNION ALL
-- (4) Reversão do CMV no cancelamento: o veículo volta ao estoque.
SELECT v.data_cancelamento, 'CMV', NULL, 'Custo dos veículos vendidos', 'COM', v.custo_veiculo_vendido,
       'CANCELAMENTO_VENDA', v.id, 'Reversão do CMV da venda ' || v.numero_venda
  FROM venda v WHERE v.situacao = 'CANCELADA'
UNION ALL
-- (5) Outras receitas operacionais (títulos a receber sem venda), por competência.
SELECT t.data_competencia, c.grupo_dre, c.codigo, c.nome, cc.codigo, t.valor,
       'TITULO_RECEBER', t.id, t.descricao
  FROM titulo_receber t
  JOIN categoria_financeira c ON c.id = t.categoria_id
  JOIN centro_custo cc ON cc.id = t.centro_custo_id
 WHERE t.venda_id IS NULL AND c.grupo_dre = 'OUTRAS_RECEITAS'
UNION ALL
SELECT t.data_cancelamento, c.grupo_dre, c.codigo, c.nome, cc.codigo, -t.valor,
       'CANCELAMENTO_TITULO', t.id, 'Cancelamento: ' || t.descricao
  FROM titulo_receber t
  JOIN categoria_financeira c ON c.id = t.categoria_id
  JOIN centro_custo cc ON cc.id = t.centro_custo_id
 WHERE t.venda_id IS NULL AND c.grupo_dre = 'OUTRAS_RECEITAS' AND t.situacao = 'CANCELADO'
UNION ALL
-- (6) Despesas (incluindo comissões), por competência. Categorias de ESTOQUE ficam de fora.
SELECT t.data_competencia, c.grupo_dre, c.codigo, c.nome, cc.codigo, -t.valor,
       'TITULO_PAGAR', t.id, t.descricao
  FROM titulo_pagar t
  JOIN categoria_financeira c ON c.id = t.categoria_id
  JOIN centro_custo cc ON cc.id = t.centro_custo_id
 WHERE c.natureza = 'DESPESA'
UNION ALL
SELECT t.data_cancelamento, c.grupo_dre, c.codigo, c.nome, cc.codigo, t.valor,
       'CANCELAMENTO_TITULO', t.id, 'Cancelamento: ' || t.descricao
  FROM titulo_pagar t
  JOIN categoria_financeira c ON c.id = t.categoria_id
  JOIN centro_custo cc ON cc.id = t.centro_custo_id
 WHERE c.natureza = 'DESPESA' AND t.situacao = 'CANCELADO'
UNION ALL
-- (7) Resultado financeiro de recebimentos: juros/multa (+) e descontos concedidos (-),
--     reconhecidos na data da baixa e revertidos na data do estorno.
SELECT r.data_recebimento, 'RECEITA_FINANCEIRA', NULL, 'Juros e multas recebidos', NULL, r.valor_juros_multa,
       'RECEBIMENTO', r.id, 'Juros/multa recebidos'
  FROM recebimento r WHERE r.valor_juros_multa > 0
UNION ALL
SELECT r.data_estorno, 'RECEITA_FINANCEIRA', NULL, 'Juros e multas recebidos', NULL, -r.valor_juros_multa,
       'ESTORNO_RECEBIMENTO', r.id, 'Estorno de juros/multa recebidos'
  FROM recebimento r WHERE r.valor_juros_multa > 0 AND r.situacao = 'ESTORNADO'
UNION ALL
SELECT r.data_recebimento, 'DESPESA_FINANCEIRA', NULL, 'Descontos concedidos', NULL, -r.valor_desconto,
       'RECEBIMENTO', r.id, 'Desconto concedido'
  FROM recebimento r WHERE r.valor_desconto > 0
UNION ALL
SELECT r.data_estorno, 'DESPESA_FINANCEIRA', NULL, 'Descontos concedidos', NULL, r.valor_desconto,
       'ESTORNO_RECEBIMENTO', r.id, 'Estorno de desconto concedido'
  FROM recebimento r WHERE r.valor_desconto > 0 AND r.situacao = 'ESTORNADO'
UNION ALL
-- (8) Resultado financeiro de pagamentos: juros/multa pagos (-) e descontos obtidos (+).
SELECT p.data_pagamento, 'DESPESA_FINANCEIRA', NULL, 'Juros e multas pagos', NULL, -p.valor_juros_multa,
       'PAGAMENTO', p.id, 'Juros/multa pagos'
  FROM pagamento p WHERE p.valor_juros_multa > 0
UNION ALL
SELECT p.data_estorno, 'DESPESA_FINANCEIRA', NULL, 'Juros e multas pagos', NULL, p.valor_juros_multa,
       'ESTORNO_PAGAMENTO', p.id, 'Estorno de juros/multa pagos'
  FROM pagamento p WHERE p.valor_juros_multa > 0 AND p.situacao = 'ESTORNADO'
UNION ALL
SELECT p.data_pagamento, 'RECEITA_FINANCEIRA', NULL, 'Descontos obtidos', NULL, p.valor_desconto,
       'PAGAMENTO', p.id, 'Desconto obtido'
  FROM pagamento p WHERE p.valor_desconto > 0
UNION ALL
SELECT p.data_estorno, 'RECEITA_FINANCEIRA', NULL, 'Descontos obtidos', NULL, -p.valor_desconto,
       'ESTORNO_PAGAMENTO', p.id, 'Estorno de desconto obtido'
  FROM pagamento p WHERE p.valor_desconto > 0 AND p.situacao = 'ESTORNADO';
COMMENT ON VIEW vw_lancamento_competencia IS 'Razão gerencial do regime de competência. Fonte única da DRE. Não contém compras de veículos, custos capitalizados, parcelas, recebimentos de principal nem transferências.';

-- DRE gerencial de qualquer período, linha a linha.
CREATE OR REPLACE FUNCTION fn_dre(p_inicio date, p_fim date)
RETURNS TABLE (ordem smallint, linha varchar, valor numeric(14,2))
LANGUAGE sql STABLE
AS $$
    WITH l AS (
        SELECT linha_dre, sum(valor) AS v
          FROM fastcar.vw_lancamento_competencia
         WHERE data_competencia BETWEEN p_inicio AND p_fim
         GROUP BY linha_dre
    ), x AS (
        SELECT COALESCE(max(v) FILTER (WHERE linha_dre = 'RECEITA_BRUTA'), 0)          AS receita_bruta,
               COALESCE(max(v) FILTER (WHERE linha_dre = 'CANCELAMENTO_VENDA'), 0)     AS cancelamentos,
               COALESCE(max(v) FILTER (WHERE linha_dre = 'OUTRAS_RECEITAS'), 0)        AS outras_receitas,
               COALESCE(max(v) FILTER (WHERE linha_dre = 'CMV'), 0)                    AS cmv,
               COALESCE(max(v) FILTER (WHERE linha_dre = 'DESPESA_VENDAS'), 0)         AS desp_vendas,
               COALESCE(max(v) FILTER (WHERE linha_dre = 'DESPESA_PESSOAL'), 0)        AS desp_pessoal,
               COALESCE(max(v) FILTER (WHERE linha_dre = 'DESPESA_ADMINISTRATIVA'), 0) AS desp_adm,
               COALESCE(max(v) FILTER (WHERE linha_dre = 'RECEITA_FINANCEIRA'), 0)     AS rec_fin,
               COALESCE(max(v) FILTER (WHERE linha_dre = 'DESPESA_FINANCEIRA'), 0)     AS desp_fin
          FROM l
    )
    SELECT o::smallint, d::varchar, val::numeric(14,2)
      FROM x, LATERAL (VALUES
        ( 1, '(+) Receita bruta de vendas de veículos',            receita_bruta),
        ( 2, '(-) Cancelamentos de vendas',                        cancelamentos),
        ( 3, '(+) Outras receitas operacionais',                   outras_receitas),
        ( 4, '(=) Receita operacional líquida',                    receita_bruta + cancelamentos + outras_receitas),
        ( 5, '(-) Custo dos veículos vendidos (CMV)',              cmv),
        ( 6, '(=) Lucro bruto',                                    receita_bruta + cancelamentos + outras_receitas + cmv),
        ( 7, '(-) Despesas com vendas (comissões, marketing, garantia)', desp_vendas),
        ( 8, '(-) Despesas com pessoal',                           desp_pessoal),
        ( 9, '(-) Despesas administrativas',                       desp_adm),
        (10, '(=) Total de despesas operacionais',                 desp_vendas + desp_pessoal + desp_adm),
        (11, '(=) Resultado operacional',                          receita_bruta + cancelamentos + outras_receitas + cmv
                                                                   + desp_vendas + desp_pessoal + desp_adm),
        (12, '(+) Receitas financeiras',                           rec_fin),
        (13, '(-) Despesas financeiras',                           desp_fin),
        (14, '(=) Resultado do período (antes de tributos sobre o lucro)',
                                                                   receita_bruta + cancelamentos + outras_receitas + cmv
                                                                   + desp_vendas + desp_pessoal + desp_adm + rec_fin + desp_fin)
      ) AS t(o, d, val)
     ORDER BY o;
$$;
COMMENT ON FUNCTION fn_dre(date, date) IS 'DRE gerencial simplificada (regime de competência) para qualquer período. Valores negativos reduzem o resultado.';

CREATE OR REPLACE VIEW vw_dre_mensal AS
WITH l AS (
    SELECT date_trunc('month', data_competencia)::date AS mes, linha_dre, sum(valor) AS v
      FROM vw_lancamento_competencia
     GROUP BY 1, 2
), p AS (
    SELECT ma.mes,
           COALESCE(sum(l.v) FILTER (WHERE l.linha_dre = 'RECEITA_BRUTA'), 0)          AS receita_bruta,
           COALESCE(sum(l.v) FILTER (WHERE l.linha_dre = 'CANCELAMENTO_VENDA'), 0)     AS cancelamentos,
           COALESCE(sum(l.v) FILTER (WHERE l.linha_dre = 'OUTRAS_RECEITAS'), 0)        AS outras_receitas,
           COALESCE(sum(l.v) FILTER (WHERE l.linha_dre = 'CMV'), 0)                    AS cmv,
           COALESCE(sum(l.v) FILTER (WHERE l.linha_dre = 'DESPESA_VENDAS'), 0)         AS despesas_vendas,
           COALESCE(sum(l.v) FILTER (WHERE l.linha_dre = 'DESPESA_PESSOAL'), 0)        AS despesas_pessoal,
           COALESCE(sum(l.v) FILTER (WHERE l.linha_dre = 'DESPESA_ADMINISTRATIVA'), 0) AS despesas_administrativas,
           COALESCE(sum(l.v) FILTER (WHERE l.linha_dre IN ('RECEITA_FINANCEIRA', 'DESPESA_FINANCEIRA')), 0) AS resultado_financeiro
      FROM vw_mes_analise ma
      LEFT JOIN l ON l.mes = ma.mes
     GROUP BY ma.mes
)
SELECT mes,
       receita_bruta,
       cancelamentos,
       outras_receitas,
       receita_bruta + cancelamentos + outras_receitas                                   AS receita_liquida,
       cmv,
       receita_bruta + cancelamentos + outras_receitas + cmv                             AS lucro_bruto,
       despesas_vendas,
       despesas_pessoal,
       despesas_administrativas,
       despesas_vendas + despesas_pessoal + despesas_administrativas                     AS despesas_operacionais,
       receita_bruta + cancelamentos + outras_receitas + cmv
         + despesas_vendas + despesas_pessoal + despesas_administrativas                 AS resultado_operacional,
       resultado_financeiro,
       receita_bruta + cancelamentos + outras_receitas + cmv
         + despesas_vendas + despesas_pessoal + despesas_administrativas
         + resultado_financeiro                                                          AS resultado_periodo,
       -- Margens só fazem sentido com receita líquida positiva (ex.: mês com cancelamento maior que vendas).
       CASE WHEN receita_bruta + cancelamentos + outras_receitas > 0 THEN
           round(100 * (receita_bruta + cancelamentos + outras_receitas + cmv)
                 / (receita_bruta + cancelamentos + outras_receitas), 2) END                AS margem_bruta_pct,
       CASE WHEN receita_bruta + cancelamentos + outras_receitas > 0 THEN
           round(100 * (receita_bruta + cancelamentos + outras_receitas + cmv
                        + despesas_vendas + despesas_pessoal + despesas_administrativas + resultado_financeiro)
                 / (receita_bruta + cancelamentos + outras_receitas), 2) END                AS margem_liquida_pct
  FROM p
 ORDER BY mes;
COMMENT ON VIEW vw_dre_mensal IS 'DRE gerencial mensal (competência). Custos e despesas com sinal negativo.';

-- Comparação mês a mês: competência x caixa e variação em relação ao mês anterior.
CREATE OR REPLACE VIEW vw_dre_comparativo_mensal AS
SELECT d.mes,
       d.receita_liquida,
       d.receita_liquida - lag(d.receita_liquida) OVER w                         AS variacao_receita_liquida,
       round(100 * (d.receita_liquida - lag(d.receita_liquida) OVER w)
             / NULLIF(abs(lag(d.receita_liquida) OVER w), 0), 2)                AS variacao_receita_pct,
       d.lucro_bruto,
       d.lucro_bruto - lag(d.lucro_bruto) OVER w                                 AS variacao_lucro_bruto,
       d.resultado_periodo,
       d.resultado_periodo - lag(d.resultado_periodo) OVER w                     AS variacao_resultado,
       sum(d.resultado_periodo) OVER (ORDER BY d.mes)                            AS resultado_acumulado,
       r.geracao_caixa                                                           AS geracao_caixa,
       d.resultado_periodo - r.geracao_caixa                                     AS diferenca_competencia_caixa
  FROM vw_dre_mensal d
  JOIN vw_resumo_financeiro_mensal r ON r.mes = d.mes
WINDOW w AS (ORDER BY d.mes)
 ORDER BY d.mes;
COMMENT ON VIEW vw_dre_comparativo_mensal IS 'Evolução mensal do resultado (competência) e comparação com a geração de caixa do mês.';

-- =============================================================================
-- POSIÇÕES: CONTAS A RECEBER E A PAGAR
-- =============================================================================

-- Faixa de atraso padronizada.
CREATE OR REPLACE FUNCTION fn_faixa_atraso(p_dias integer)
RETURNS varchar
LANGUAGE sql IMMUTABLE
AS $$
    SELECT CASE
               WHEN p_dias IS NULL OR p_dias <= 0 THEN 'A vencer'
               WHEN p_dias <= 30 THEN '01-30 dias'
               WHEN p_dias <= 60 THEN '31-60 dias'
               WHEN p_dias <= 90 THEN '61-90 dias'
               ELSE 'Acima de 90 dias'
           END;
$$;

-- Posição de contas a receber em uma data-base: considera apenas títulos emitidos
-- até a data e baixas efetivas até a data (um estorno posterior não altera o passado).
CREATE OR REPLACE FUNCTION fn_posicao_contas_receber(p_data_base date)
RETURNS TABLE (
    titulo_id         bigint,
    documento         varchar,
    numero_parcela    smallint,
    total_parcelas    smallint,
    cliente           varchar,
    cliente_documento varchar,
    descricao         varchar,
    data_vencimento   date,
    valor_titulo      numeric(14,2),
    valor_recebido    numeric(14,2),
    saldo_aberto      numeric(14,2),
    dias_atraso       integer,
    situacao          varchar,
    recebido_parcial  boolean,
    faixa_atraso      varchar
)
LANGUAGE sql STABLE
AS $$
    WITH t AS (
        SELECT tr.*, c.nome AS cliente_nome, c.documento AS cli_doc,
               COALESCE((SELECT sum(r.valor_principal)
                           FROM fastcar.recebimento r
                          WHERE r.titulo_receber_id = tr.id
                            AND r.data_recebimento <= p_data_base
                            AND (r.situacao = 'EFETIVO' OR r.data_estorno > p_data_base)), 0) AS recebido
          FROM fastcar.titulo_receber tr
          JOIN fastcar.cliente c ON c.id = tr.cliente_id
         WHERE tr.data_emissao <= p_data_base
           AND (tr.situacao = 'ATIVO' OR tr.data_cancelamento > p_data_base)
    )
    SELECT id, t.documento, t.numero_parcela, t.total_parcelas, cliente_nome, cli_doc, t.descricao,
           t.data_vencimento, t.valor, recebido::numeric(14,2), (t.valor - recebido)::numeric(14,2),
           CASE WHEN t.valor - recebido > 0 THEN GREATEST(p_data_base - t.data_vencimento, 0) ELSE 0 END,
           (CASE WHEN t.valor - recebido = 0 THEN 'QUITADO'
                 WHEN t.data_vencimento < p_data_base THEN 'VENCIDO'
                 ELSE 'A_VENCER' END)::varchar,
           recebido > 0 AND t.valor - recebido > 0,
           (CASE WHEN t.valor - recebido = 0 THEN NULL
                 ELSE fastcar.fn_faixa_atraso(p_data_base - t.data_vencimento) END)::varchar
      FROM t
     ORDER BY t.data_vencimento, t.documento, t.numero_parcela;
$$;
COMMENT ON FUNCTION fn_posicao_contas_receber(date) IS 'Posição de cada título a receber em uma data-base: valor, recebido, saldo, dias de atraso, situação e faixa.';

CREATE OR REPLACE FUNCTION fn_posicao_contas_pagar(p_data_base date)
RETURNS TABLE (
    titulo_id         bigint,
    documento         varchar,
    numero_parcela    smallint,
    total_parcelas    smallint,
    favorecido        varchar,
    categoria_codigo  varchar,
    categoria_nome    varchar,
    centro_custo      varchar,
    descricao         varchar,
    data_vencimento   date,
    valor_titulo      numeric(14,2),
    valor_pago        numeric(14,2),
    saldo_aberto      numeric(14,2),
    dias_atraso       integer,
    situacao          varchar,
    pago_parcial      boolean,
    faixa_atraso      varchar
)
LANGUAGE sql STABLE
AS $$
    WITH t AS (
        SELECT tp.*,
               COALESCE(f.nome, v.nome, 'Folha de pagamento (consolidada)') AS fav,
               cat.codigo AS cat_cod, cat.nome AS cat_nome, cc.codigo AS cc_cod,
               COALESCE((SELECT sum(p.valor_principal)
                           FROM fastcar.pagamento p
                          WHERE p.titulo_pagar_id = tp.id
                            AND p.data_pagamento <= p_data_base
                            AND (p.situacao = 'EFETIVO' OR p.data_estorno > p_data_base)), 0) AS pago
          FROM fastcar.titulo_pagar tp
          JOIN fastcar.categoria_financeira cat ON cat.id = tp.categoria_id
          JOIN fastcar.centro_custo cc ON cc.id = tp.centro_custo_id
          LEFT JOIN fastcar.fornecedor f ON f.id = tp.fornecedor_id
          LEFT JOIN fastcar.vendedor v ON v.id = tp.vendedor_id
         WHERE tp.data_emissao <= p_data_base
           AND (tp.situacao = 'ATIVO' OR tp.data_cancelamento > p_data_base)
    )
    SELECT id, t.documento, t.numero_parcela, t.total_parcelas, fav, cat_cod, cat_nome, cc_cod, t.descricao,
           t.data_vencimento, t.valor, pago::numeric(14,2), (t.valor - pago)::numeric(14,2),
           CASE WHEN t.valor - pago > 0 THEN GREATEST(p_data_base - t.data_vencimento, 0) ELSE 0 END,
           (CASE WHEN t.valor - pago = 0 THEN 'QUITADO'
                 WHEN t.data_vencimento < p_data_base THEN 'VENCIDO'
                 ELSE 'A_VENCER' END)::varchar,
           pago > 0 AND t.valor - pago > 0,
           (CASE WHEN t.valor - pago = 0 THEN NULL
                 ELSE fastcar.fn_faixa_atraso(p_data_base - t.data_vencimento) END)::varchar
      FROM t
     ORDER BY t.data_vencimento, t.documento, t.numero_parcela;
$$;
COMMENT ON FUNCTION fn_posicao_contas_pagar(date) IS 'Posição de cada título a pagar em uma data-base: valor, pago, saldo, dias de atraso, situação e faixa.';

CREATE OR REPLACE VIEW vw_contas_receber_aberto AS
SELECT * FROM fn_posicao_contas_receber(fn_data_referencia()) WHERE saldo_aberto > 0;
COMMENT ON VIEW vw_contas_receber_aberto IS 'Títulos a receber com saldo em aberto na data de referência (VENCIDO ou A_VENCER), já descontados os recebimentos parciais.';

CREATE OR REPLACE VIEW vw_contas_pagar_aberto AS
SELECT * FROM fn_posicao_contas_pagar(fn_data_referencia()) WHERE saldo_aberto > 0;
COMMENT ON VIEW vw_contas_pagar_aberto IS 'Títulos a pagar com saldo em aberto na data de referência (VENCIDO ou A_VENCER), já descontados os pagamentos parciais.';

CREATE OR REPLACE VIEW vw_resumo_contas_aberto AS
SELECT 'RECEBER'::varchar AS tipo, situacao, count(*) AS quantidade_titulos,
       sum(valor_titulo) AS valor_original, sum(valor_recebido) AS valor_baixado, sum(saldo_aberto) AS saldo_aberto
  FROM vw_contas_receber_aberto GROUP BY situacao
UNION ALL
SELECT 'PAGAR', situacao, count(*), sum(valor_titulo), sum(valor_pago), sum(saldo_aberto)
  FROM vw_contas_pagar_aberto GROUP BY situacao
 ORDER BY 1 DESC, 2;
COMMENT ON VIEW vw_resumo_contas_aberto IS 'Totais em aberto a receber e a pagar, separados em VENCIDO e A_VENCER.';

CREATE OR REPLACE VIEW vw_inadimplencia_cliente AS
SELECT cliente, cliente_documento, faixa_atraso,
       count(*)            AS titulos_vencidos,
       sum(saldo_aberto)   AS saldo_vencido,
       max(dias_atraso)    AS maior_atraso_dias
  FROM vw_contas_receber_aberto
 WHERE situacao = 'VENCIDO'
 GROUP BY cliente, cliente_documento, faixa_atraso
 ORDER BY saldo_vencido DESC, cliente;
COMMENT ON VIEW vw_inadimplencia_cliente IS 'Saldo vencido por cliente e faixa de atraso na data de referência.';

CREATE OR REPLACE VIEW vw_inadimplencia_faixa AS
SELECT f.faixa_atraso,
       count(r.titulo_id)               AS titulos_vencidos,
       count(DISTINCT r.cliente_documento) AS clientes,
       COALESCE(sum(r.saldo_aberto), 0) AS saldo_vencido,
       round(100 * COALESCE(sum(r.saldo_aberto), 0)
             / NULLIF((SELECT sum(saldo_aberto) FROM vw_contas_receber_aberto), 0), 2) AS pct_carteira_aberta
  FROM (VALUES (1, '01-30 dias'), (2, '31-60 dias'), (3, '61-90 dias'), (4, 'Acima de 90 dias')) AS f(ordem, faixa_atraso)
  LEFT JOIN vw_contas_receber_aberto r ON r.faixa_atraso = f.faixa_atraso AND r.situacao = 'VENCIDO'
 GROUP BY f.ordem, f.faixa_atraso
 ORDER BY f.ordem;
COMMENT ON VIEW vw_inadimplencia_faixa IS 'Inadimplência por faixa de atraso e participação na carteira a receber em aberto.';

-- =============================================================================
-- DESPESAS POR CATEGORIA E CENTRO DE CUSTO
-- =============================================================================
CREATE OR REPLACE VIEW vw_despesas_categoria_centro AS
SELECT date_trunc('month', data_competencia)::date AS mes,
       categoria_codigo, categoria_nome, centro_custo_codigo, linha_dre,
       -sum(valor) AS valor_despesa
  FROM vw_lancamento_competencia
 WHERE linha_dre IN ('DESPESA_VENDAS', 'DESPESA_PESSOAL', 'DESPESA_ADMINISTRATIVA')
 GROUP BY 1, 2, 3, 4, 5
 ORDER BY 1, 2, 4;
COMMENT ON VIEW vw_despesas_categoria_centro IS 'Despesas operacionais por mês de competência, categoria e centro de custo (valores positivos, líquidos de cancelamentos).';

CREATE OR REPLACE VIEW vw_pagamentos_categoria_centro AS
SELECT mes, grupo_fluxo, categoria_codigo, categoria_nome, centro_custo_codigo,
       -sum(valor_assinado) AS valor_pago
  FROM vw_movimento_caixa
 WHERE pagamento_id IS NOT NULL
 GROUP BY mes, grupo_fluxo, categoria_codigo, categoria_nome, centro_custo_codigo
 ORDER BY mes, categoria_codigo, centro_custo_codigo;
COMMENT ON VIEW vw_pagamentos_categoria_centro IS 'Saídas de caixa por mês de pagamento, categoria e centro de custo (líquidas de estornos, com juros).';

-- =============================================================================
-- VENDAS, MARGENS E COMISSÕES
-- =============================================================================
CREATE OR REPLACE VIEW vw_margem_veiculo_vendido AS
SELECT v.numero_venda,
       v.data_venda,
       ve.chassi,
       ve.marca || ' ' || ve.modelo || ' ' || ve.ano_fabricacao || '/' || ve.ano_modelo AS veiculo,
       vd.nome                                               AS vendedor,
       c.data_compra,
       v.data_venda - c.data_compra                          AS dias_em_estoque,
       v.valor_venda,
       c.valor_compra                                        AS custo_aquisicao,
       v.custo_veiculo_vendido - c.valor_compra              AS custos_adicionais,
       v.custo_veiculo_vendido                               AS custo_total,
       v.valor_venda - v.custo_veiculo_vendido               AS lucro_bruto,
       round(100 * (v.valor_venda - v.custo_veiculo_vendido) / v.valor_venda, 2) AS margem_bruta_pct,
       v.valor_comissao                                      AS comissao,
       v.valor_venda - v.custo_veiculo_vendido - v.valor_comissao AS margem_contribuicao,
       round(100 * (v.valor_venda - v.custo_veiculo_vendido - v.valor_comissao) / v.valor_venda, 2) AS margem_contribuicao_pct
  FROM venda v
  JOIN veiculo ve        ON ve.id = v.veiculo_id
  JOIN compra_veiculo c  ON c.veiculo_id = v.veiculo_id
  JOIN vendedor vd       ON vd.id = v.vendedor_id
 WHERE v.situacao = 'ATIVA'
 ORDER BY v.data_venda, v.numero_venda;
COMMENT ON VIEW vw_margem_veiculo_vendido IS 'Margem por veículo vendido (vendas ativas): lucro bruto = venda - custo total; margem de contribuição desconta a comissão.';

CREATE OR REPLACE VIEW vw_vendas_comissoes_vendedor AS
WITH com AS (
    SELECT t.venda_id,
           sum(t.valor) FILTER (WHERE t.situacao = 'ATIVO') AS comissao_devida,
           COALESCE(sum(p.valor_principal) FILTER (WHERE p.situacao = 'EFETIVO'), 0) AS comissao_paga
      FROM titulo_pagar t
      LEFT JOIN pagamento p ON p.titulo_pagar_id = t.id
     WHERE t.venda_id IS NOT NULL
     GROUP BY t.venda_id
)
SELECT date_trunc('month', v.data_venda)::date                         AS mes,
       vd.nome                                                         AS vendedor,
       count(*) FILTER (WHERE v.situacao = 'ATIVA')                    AS vendas_ativas,
       count(*) FILTER (WHERE v.situacao = 'CANCELADA')                AS vendas_canceladas,
       COALESCE(sum(v.valor_venda) FILTER (WHERE v.situacao = 'ATIVA'), 0) AS faturamento,
       COALESCE(sum(v.valor_venda - v.custo_veiculo_vendido) FILTER (WHERE v.situacao = 'ATIVA'), 0) AS lucro_bruto,
       COALESCE(sum(com.comissao_devida), 0)                           AS comissao_devida,
       COALESCE(sum(com.comissao_paga), 0)                             AS comissao_paga,
       COALESCE(sum(com.comissao_devida), 0) - COALESCE(sum(com.comissao_paga), 0) AS comissao_a_pagar
  FROM venda v
  JOIN vendedor vd ON vd.id = v.vendedor_id
  LEFT JOIN com ON com.venda_id = v.id
 GROUP BY 1, 2
 ORDER BY 1, 2;
COMMENT ON VIEW vw_vendas_comissoes_vendedor IS 'Vendas, faturamento, lucro bruto e comissões por vendedor e mês da venda. Vendas canceladas são contadas à parte e não geram comissão devida.';

-- =============================================================================
-- ESTOQUE
-- =============================================================================

-- Valor do estoque em qualquer data: veículos comprados até a data e sem venda vigente na data.
CREATE OR REPLACE FUNCTION fn_estoque_veiculos(p_data date)
RETURNS TABLE (
    chassi             char(17),
    veiculo            text,
    data_compra        date,
    dias_em_estoque    integer,
    custo_aquisicao    numeric(14,2),
    custos_adicionais  numeric(14,2),
    custo_total        numeric(14,2),
    preco_anunciado    numeric(14,2)
)
LANGUAGE sql STABLE
AS $$
    SELECT ve.chassi,
           ve.marca || ' ' || ve.modelo || ' ' || ve.ano_fabricacao || '/' || ve.ano_modelo,
           c.data_compra,
           p_data - c.data_compra,
           c.valor_compra,
           (fastcar.fn_custo_veiculo(ve.id, p_data) - c.valor_compra)::numeric(14,2),
           fastcar.fn_custo_veiculo(ve.id, p_data),
           ve.preco_anunciado
      FROM fastcar.veiculo ve
      JOIN fastcar.compra_veiculo c ON c.veiculo_id = ve.id
     WHERE c.data_compra <= p_data
       AND NOT EXISTS (SELECT 1
                         FROM fastcar.venda v
                        WHERE v.veiculo_id = ve.id
                          AND v.data_venda <= p_data
                          AND (v.situacao = 'ATIVA' OR v.data_cancelamento > p_data))
     ORDER BY c.data_compra;
$$;
COMMENT ON FUNCTION fn_estoque_veiculos(date) IS 'Veículos em estoque em uma data e seu custo (aquisição + custos adicionais até a data).';

CREATE OR REPLACE VIEW vw_estoque_veiculos AS
SELECT e.*, ve.situacao,
       e.preco_anunciado - e.custo_total AS margem_potencial
  FROM fn_estoque_veiculos(fn_data_referencia()) e
  JOIN veiculo ve ON ve.chassi = e.chassi
 ORDER BY e.data_compra;
COMMENT ON VIEW vw_estoque_veiculos IS 'Estoque na data de referência: custo de cada veículo, dias parado e margem potencial pelo preço anunciado.';

CREATE OR REPLACE VIEW vw_estoque_mensal AS
SELECT ma.fim_mes AS data_posicao,
       count(e.chassi)                AS veiculos,
       COALESCE(sum(e.custo_total), 0) AS valor_estoque
  FROM vw_mes_analise ma
  LEFT JOIN LATERAL fn_estoque_veiculos(LEAST(ma.fim_mes, fn_data_referencia())) e ON true
 GROUP BY ma.fim_mes
 ORDER BY ma.fim_mes;
COMMENT ON VIEW vw_estoque_mensal IS 'Quantidade e valor de custo do estoque no último dia de cada mês.';

COMMENT ON FUNCTION fn_faixa_atraso(integer) IS 'Classifica dias de atraso em faixas: A vencer, 01-30, 31-60, 61-90 e acima de 90 dias.';
