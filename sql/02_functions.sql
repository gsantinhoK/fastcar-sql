-- =============================================================================
-- Fast Car - Sistema Financeiro em SQL
-- Arquivo : sql/02_functions.sql
-- Objetivo: gatilhos de integridade e funções de negócio.
-- Depende : 01_schema.sql
--
-- Convenções:
--   fn_tg_*  funções de gatilho        tg_*   gatilhos
--   fn_id_*  busca de chave por código fn_*   operações de negócio
--
-- Todas as funções de negócio rodam em uma única transação: se qualquer etapa
-- falhar (ex.: valor acima do saldo), nada do que foi feito pela função persiste.
-- Para agrupar várias operações em um único bloco atômico, use BEGIN/COMMIT.
-- =============================================================================

\set ON_ERROR_STOP on
SET search_path TO fastcar, public;

-- -----------------------------------------------------------------------------
-- Utilitários
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_data_referencia()
RETURNS date
LANGUAGE sql STABLE
AS $$
    SELECT COALESCE((SELECT c.data_referencia FROM fastcar.configuracao c WHERE c.id = 1), current_date);
$$;
COMMENT ON FUNCTION fn_data_referencia() IS 'Data de referência dos relatórios (tabela configuracao). Usa a data atual se não configurada.';

CREATE OR REPLACE FUNCTION fn_id_conta(p_codigo text)
RETURNS smallint LANGUAGE plpgsql STABLE SET search_path = fastcar, public AS $$
DECLARE v_id smallint;
BEGIN
    SELECT id INTO v_id FROM conta_bancaria WHERE codigo = p_codigo AND ativo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Conta bancária "%" inexistente ou inativa', p_codigo;
    END IF;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION fn_id_categoria(p_codigo text)
RETURNS integer LANGUAGE plpgsql STABLE SET search_path = fastcar, public AS $$
DECLARE v_id integer;
BEGIN
    SELECT id INTO v_id FROM categoria_financeira WHERE codigo = p_codigo AND ativo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Categoria financeira "%" inexistente ou inativa', p_codigo;
    END IF;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION fn_id_centro_custo(p_codigo text)
RETURNS smallint LANGUAGE plpgsql STABLE SET search_path = fastcar, public AS $$
DECLARE v_id smallint;
BEGIN
    SELECT id INTO v_id FROM centro_custo WHERE codigo = p_codigo AND ativo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Centro de custo "%" inexistente ou inativo', p_codigo;
    END IF;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION fn_id_cliente(p_documento text)
RETURNS integer LANGUAGE plpgsql STABLE SET search_path = fastcar, public AS $$
DECLARE v_id integer;
BEGIN
    SELECT id INTO v_id FROM cliente WHERE documento = p_documento;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cliente com documento "%" não encontrado', p_documento;
    END IF;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION fn_id_fornecedor(p_documento text)
RETURNS integer LANGUAGE plpgsql STABLE SET search_path = fastcar, public AS $$
DECLARE v_id integer;
BEGIN
    IF p_documento IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT id INTO v_id FROM fornecedor WHERE documento = p_documento;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Fornecedor com documento "%" não encontrado', p_documento;
    END IF;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION fn_id_veiculo(p_chassi text)
RETURNS integer LANGUAGE plpgsql STABLE SET search_path = fastcar, public AS $$
DECLARE v_id integer;
BEGIN
    SELECT id INTO v_id FROM veiculo WHERE chassi = p_chassi;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Veículo com chassi "%" não encontrado', p_chassi;
    END IF;
    RETURN v_id;
END $$;

-- Custo total do veículo até uma data: aquisição + custos adicionais lançados até a data.
CREATE OR REPLACE FUNCTION fn_custo_veiculo(p_veiculo_id integer, p_data date)
RETURNS numeric(14,2)
LANGUAGE sql STABLE
AS $$
    SELECT c.valor_compra
         + COALESCE((SELECT sum(cv.valor)
                       FROM fastcar.custo_veiculo cv
                      WHERE cv.veiculo_id = p_veiculo_id
                        AND cv.data_custo <= p_data), 0)
      FROM fastcar.compra_veiculo c
     WHERE c.veiculo_id = p_veiculo_id
       AND c.data_compra <= p_data;
$$;
COMMENT ON FUNCTION fn_custo_veiculo(integer, date) IS 'Custo do veículo (aquisição + custos adicionais) acumulado até a data informada.';

-- Saldo em aberto de um título: valor original menos o principal das baixas efetivas.
CREATE OR REPLACE FUNCTION fn_saldo_titulo_receber(p_titulo_id bigint)
RETURNS numeric(14,2)
LANGUAGE sql STABLE
AS $$
    SELECT t.valor - COALESCE((SELECT sum(r.valor_principal)
                                 FROM fastcar.recebimento r
                                WHERE r.titulo_receber_id = t.id
                                  AND r.situacao = 'EFETIVO'), 0)
      FROM fastcar.titulo_receber t
     WHERE t.id = p_titulo_id;
$$;

CREATE OR REPLACE FUNCTION fn_saldo_titulo_pagar(p_titulo_id bigint)
RETURNS numeric(14,2)
LANGUAGE sql STABLE
AS $$
    SELECT t.valor - COALESCE((SELECT sum(p.valor_principal)
                                 FROM fastcar.pagamento p
                                WHERE p.titulo_pagar_id = t.id
                                  AND p.situacao = 'EFETIVO'), 0)
      FROM fastcar.titulo_pagar t
     WHERE t.id = p_titulo_id;
$$;

-- -----------------------------------------------------------------------------
-- Gatilhos genéricos de imutabilidade (preservação do histórico)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_bloqueia_exclusao()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Exclusão não permitida em %: o histórico financeiro é preservado; use cancelamento ou estorno', TG_TABLE_NAME;
END $$;

CREATE OR REPLACE FUNCTION fn_tg_bloqueia_alteracao()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Registros de % são imutáveis (%): faça um lançamento de estorno ou ajuste', TG_TABLE_NAME, TG_OP;
END $$;

CREATE TRIGGER tg_movimento_bancario_imutavel BEFORE UPDATE OR DELETE ON movimento_bancario
    FOR EACH ROW EXECUTE FUNCTION fn_tg_bloqueia_alteracao();
CREATE TRIGGER tg_transferencia_imutavel BEFORE UPDATE OR DELETE ON transferencia
    FOR EACH ROW EXECUTE FUNCTION fn_tg_bloqueia_alteracao();
CREATE TRIGGER tg_compra_veiculo_imutavel BEFORE UPDATE OR DELETE ON compra_veiculo
    FOR EACH ROW EXECUTE FUNCTION fn_tg_bloqueia_alteracao();
CREATE TRIGGER tg_custo_veiculo_imutavel BEFORE UPDATE OR DELETE ON custo_veiculo
    FOR EACH ROW EXECUTE FUNCTION fn_tg_bloqueia_alteracao();
CREATE TRIGGER tg_venda_sem_exclusao BEFORE DELETE ON venda
    FOR EACH ROW EXECUTE FUNCTION fn_tg_bloqueia_exclusao();
CREATE TRIGGER tg_titulo_receber_sem_exclusao BEFORE DELETE ON titulo_receber
    FOR EACH ROW EXECUTE FUNCTION fn_tg_bloqueia_exclusao();
CREATE TRIGGER tg_titulo_pagar_sem_exclusao BEFORE DELETE ON titulo_pagar
    FOR EACH ROW EXECUTE FUNCTION fn_tg_bloqueia_exclusao();
CREATE TRIGGER tg_recebimento_sem_exclusao BEFORE DELETE ON recebimento
    FOR EACH ROW EXECUTE FUNCTION fn_tg_bloqueia_exclusao();
CREATE TRIGGER tg_pagamento_sem_exclusao BEFORE DELETE ON pagamento
    FOR EACH ROW EXECUTE FUNCTION fn_tg_bloqueia_exclusao();

-- -----------------------------------------------------------------------------
-- Movimento bancário: só após o saldo inicial e em conta ativa
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_movimento_bancario_valida()
RETURNS trigger LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE v_conta conta_bancaria%ROWTYPE;
BEGIN
    SELECT * INTO v_conta FROM conta_bancaria WHERE id = NEW.conta_bancaria_id;
    IF NOT FOUND OR NOT v_conta.ativo THEN
        RAISE EXCEPTION 'Conta bancária % inexistente ou inativa', NEW.conta_bancaria_id;
    END IF;
    IF NEW.data_movimento <= v_conta.data_saldo_inicial THEN
        RAISE EXCEPTION 'Movimento em % não permitido: a conta % tem saldo inicial em %',
            NEW.data_movimento, v_conta.codigo, v_conta.data_saldo_inicial;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_movimento_bancario_valida BEFORE INSERT ON movimento_bancario
    FOR EACH ROW EXECUTE FUNCTION fn_tg_movimento_bancario_valida();

-- -----------------------------------------------------------------------------
-- Veículo: máquina de estados
--   EM_PREPARACAO -> DISPONIVEL -> VENDIDO (via venda) -> DISPONIVEL (via cancelamento)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_veiculo_situacao()
RETURNS trigger LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE v_tem_venda_ativa boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.situacao = 'VENDIDO' THEN
            RAISE EXCEPTION 'Veículo não pode ser cadastrado como VENDIDO; registre a venda com fn_registrar_venda';
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.situacao IS DISTINCT FROM OLD.situacao THEN
        SELECT EXISTS (SELECT 1 FROM venda WHERE veiculo_id = NEW.id AND situacao = 'ATIVA')
          INTO v_tem_venda_ativa;
        IF NEW.situacao = 'VENDIDO' AND NOT v_tem_venda_ativa THEN
            RAISE EXCEPTION 'Veículo % só fica VENDIDO quando existe venda ativa', NEW.chassi;
        END IF;
        IF OLD.situacao = 'VENDIDO' AND v_tem_venda_ativa THEN
            RAISE EXCEPTION 'Veículo % tem venda ativa; cancele a venda para devolvê-lo ao estoque', NEW.chassi;
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_veiculo_situacao BEFORE INSERT OR UPDATE ON veiculo
    FOR EACH ROW EXECUTE FUNCTION fn_tg_veiculo_situacao();

-- -----------------------------------------------------------------------------
-- Custo de veículo: só para veículo em estoque e após a compra
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_custo_veiculo_valida()
RETURNS trigger LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_situacao    varchar;
    v_data_compra date;
BEGIN
    SELECT v.situacao, c.data_compra INTO v_situacao, v_data_compra
      FROM veiculo v
      LEFT JOIN compra_veiculo c ON c.veiculo_id = v.id
     WHERE v.id = NEW.veiculo_id
       FOR UPDATE OF v;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Veículo % não existe', NEW.veiculo_id;
    END IF;
    IF v_data_compra IS NULL THEN
        RAISE EXCEPTION 'Veículo % não tem compra registrada', NEW.veiculo_id;
    END IF;
    IF v_situacao = 'VENDIDO' THEN
        RAISE EXCEPTION 'Veículo % já vendido: custos pós-venda devem ser lançados como despesa (categoria 3.08)', NEW.veiculo_id;
    END IF;
    IF NEW.data_custo < v_data_compra THEN
        RAISE EXCEPTION 'Custo em % é anterior à compra do veículo (%)', NEW.data_custo, v_data_compra;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_custo_veiculo_valida BEFORE INSERT ON custo_veiculo
    FOR EACH ROW EXECUTE FUNCTION fn_tg_custo_veiculo_valida();

-- -----------------------------------------------------------------------------
-- Venda: validação, fotografia do CMV e atualização do estoque
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_venda_antes()
RETURNS trigger LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_situacao    varchar;
    v_data_compra date;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- O bloqueio da linha do veículo serializa vendas concorrentes do mesmo veículo.
        SELECT v.situacao, c.data_compra INTO v_situacao, v_data_compra
          FROM veiculo v
          LEFT JOIN compra_veiculo c ON c.veiculo_id = v.id
         WHERE v.id = NEW.veiculo_id
           FOR UPDATE OF v;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Veículo % não existe', NEW.veiculo_id;
        END IF;
        IF v_situacao <> 'DISPONIVEL' THEN
            RAISE EXCEPTION 'Veículo % não está disponível para venda (situação: %)', NEW.veiculo_id, v_situacao;
        END IF;
        IF NEW.data_venda < v_data_compra THEN
            RAISE EXCEPTION 'Data da venda (%) anterior à compra do veículo (%)', NEW.data_venda, v_data_compra;
        END IF;
        IF EXISTS (SELECT 1 FROM custo_veiculo WHERE veiculo_id = NEW.veiculo_id AND data_custo > NEW.data_venda) THEN
            RAISE EXCEPTION 'Há custos do veículo % lançados após a data da venda %', NEW.veiculo_id, NEW.data_venda;
        END IF;
        IF NEW.situacao <> 'ATIVA' THEN
            RAISE EXCEPTION 'Venda deve ser registrada como ATIVA';
        END IF;
        -- CMV: fotografia do custo do veículo na data da venda (não depende do valor informado).
        NEW.custo_veiculo_vendido := fn_custo_veiculo(NEW.veiculo_id, NEW.data_venda);
        RETURN NEW;
    END IF;

    -- UPDATE: apenas cancelamento é permitido.
    IF (to_jsonb(NEW) - ARRAY['situacao', 'data_cancelamento', 'motivo_cancelamento'])
       IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['situacao', 'data_cancelamento', 'motivo_cancelamento']) THEN
        RAISE EXCEPTION 'Venda % não pode ser alterada; cancele e registre uma nova venda', OLD.numero_venda;
    END IF;
    IF OLD.situacao = 'CANCELADA' THEN
        RAISE EXCEPTION 'Venda % já está cancelada', OLD.numero_venda;
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION fn_tg_venda_depois()
RETURNS trigger LANGUAGE plpgsql SET search_path = fastcar, public AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE veiculo SET situacao = 'VENDIDO' WHERE id = NEW.veiculo_id;
    ELSIF NEW.situacao = 'CANCELADA' AND OLD.situacao = 'ATIVA' THEN
        UPDATE veiculo SET situacao = 'DISPONIVEL' WHERE id = NEW.veiculo_id;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER tg_venda_antes BEFORE INSERT OR UPDATE ON venda
    FOR EACH ROW EXECUTE FUNCTION fn_tg_venda_antes();
CREATE TRIGGER tg_venda_depois AFTER INSERT OR UPDATE ON venda
    FOR EACH ROW EXECUTE FUNCTION fn_tg_venda_depois();

-- -----------------------------------------------------------------------------
-- Títulos: categoria coerente, imutabilidade e regras de cancelamento
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_titulo_receber_valida()
RETURNS trigger LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_natureza varchar;
    v_codigo   varchar;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF (to_jsonb(NEW) - ARRAY['situacao', 'data_cancelamento', 'motivo_cancelamento'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['situacao', 'data_cancelamento', 'motivo_cancelamento']) THEN
            RAISE EXCEPTION 'Título a receber % não pode ser alterado; cancele e lance novamente', OLD.id;
        END IF;
        IF OLD.situacao = 'CANCELADO' THEN
            RAISE EXCEPTION 'Título a receber % já está cancelado', OLD.id;
        END IF;
        IF NEW.situacao = 'CANCELADO' THEN
            IF OLD.venda_id IS NOT NULL
               AND (SELECT situacao FROM venda WHERE id = OLD.venda_id) <> 'CANCELADA' THEN
                RAISE EXCEPTION 'Título % pertence a uma venda ativa; use fn_cancelar_venda', OLD.id;
            END IF;
            IF EXISTS (SELECT 1 FROM recebimento WHERE titulo_receber_id = OLD.id AND situacao = 'EFETIVO') THEN
                RAISE EXCEPTION 'Título a receber % tem recebimentos efetivos; estorne-os antes de cancelar', OLD.id;
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    SELECT natureza, codigo INTO v_natureza, v_codigo
      FROM categoria_financeira WHERE id = NEW.categoria_id AND ativo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Categoria % inexistente ou inativa', NEW.categoria_id;
    END IF;
    IF v_natureza <> 'RECEITA' THEN
        RAISE EXCEPTION 'Título a receber exige categoria de RECEITA (categoria % é %)', v_codigo, v_natureza;
    END IF;
    IF (NEW.venda_id IS NOT NULL) <> (v_codigo = '1.01') THEN
        RAISE EXCEPTION 'A categoria 1.01 (venda de veículos) é exclusiva dos títulos gerados por vendas';
    END IF;
    IF NEW.situacao <> 'ATIVO' THEN
        RAISE EXCEPTION 'Título deve ser criado como ATIVO';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_titulo_receber_valida BEFORE INSERT OR UPDATE ON titulo_receber
    FOR EACH ROW EXECUTE FUNCTION fn_tg_titulo_receber_valida();

CREATE OR REPLACE FUNCTION fn_tg_titulo_pagar_valida()
RETURNS trigger LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_natureza varchar;
    v_codigo   varchar;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF (to_jsonb(NEW) - ARRAY['situacao', 'data_cancelamento', 'motivo_cancelamento'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['situacao', 'data_cancelamento', 'motivo_cancelamento']) THEN
            RAISE EXCEPTION 'Título a pagar % não pode ser alterado; cancele e lance novamente', OLD.id;
        END IF;
        IF OLD.situacao = 'CANCELADO' THEN
            RAISE EXCEPTION 'Título a pagar % já está cancelado', OLD.id;
        END IF;
        IF NEW.situacao = 'CANCELADO' THEN
            IF OLD.compra_veiculo_id IS NOT NULL OR OLD.custo_veiculo_id IS NOT NULL THEN
                RAISE EXCEPTION 'Títulos de compra ou custo de veículo não podem ser cancelados (o custo já integra o estoque)';
            END IF;
            IF OLD.venda_id IS NOT NULL
               AND (SELECT situacao FROM venda WHERE id = OLD.venda_id) <> 'CANCELADA' THEN
                RAISE EXCEPTION 'Comissão % pertence a uma venda ativa; use fn_cancelar_venda', OLD.id;
            END IF;
            IF EXISTS (SELECT 1 FROM pagamento WHERE titulo_pagar_id = OLD.id AND situacao = 'EFETIVO') THEN
                RAISE EXCEPTION 'Título a pagar % tem pagamentos efetivos; estorne-os antes de cancelar', OLD.id;
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    SELECT natureza, codigo INTO v_natureza, v_codigo
      FROM categoria_financeira WHERE id = NEW.categoria_id AND ativo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Categoria % inexistente ou inativa', NEW.categoria_id;
    END IF;
    IF v_natureza NOT IN ('DESPESA', 'ESTOQUE') THEN
        RAISE EXCEPTION 'Título a pagar exige categoria de DESPESA ou ESTOQUE (categoria % é %)', v_codigo, v_natureza;
    END IF;
    IF (v_natureza = 'ESTOQUE') <> (NEW.compra_veiculo_id IS NOT NULL OR NEW.custo_veiculo_id IS NOT NULL) THEN
        RAISE EXCEPTION 'Categorias de ESTOQUE são exclusivas de compras e custos de veículos (categoria %)', v_codigo;
    END IF;
    IF (NEW.venda_id IS NOT NULL) <> (v_codigo = '3.01') THEN
        RAISE EXCEPTION 'A categoria 3.01 (comissões) é exclusiva dos títulos de comissão gerados por vendas';
    END IF;
    IF NEW.situacao <> 'ATIVO' THEN
        RAISE EXCEPTION 'Título deve ser criado como ATIVO';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_titulo_pagar_valida BEFORE INSERT OR UPDATE ON titulo_pagar
    FOR EACH ROW EXECUTE FUNCTION fn_tg_titulo_pagar_valida();

-- -----------------------------------------------------------------------------
-- Baixas: saldo em aberto, conta, datas e imutabilidade
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tg_recebimento_valida()
RETURNS trigger LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_titulo titulo_receber%ROWTYPE;
    v_conta  conta_bancaria%ROWTYPE;
    v_saldo  numeric(14,2);
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF (to_jsonb(NEW) - ARRAY['situacao', 'data_estorno', 'motivo_estorno', 'valor_total'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['situacao', 'data_estorno', 'motivo_estorno', 'valor_total']) THEN
            RAISE EXCEPTION 'Recebimento % não pode ser alterado; estorne e registre novamente', OLD.id;
        END IF;
        IF OLD.situacao = 'ESTORNADO' THEN
            RAISE EXCEPTION 'Recebimento % já foi estornado', OLD.id;
        END IF;
        RETURN NEW;
    END IF;

    -- Bloqueia o título: duas baixas simultâneas não conseguem ultrapassar o saldo.
    SELECT * INTO v_titulo FROM titulo_receber WHERE id = NEW.titulo_receber_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Título a receber % não existe', NEW.titulo_receber_id;
    END IF;
    IF v_titulo.situacao <> 'ATIVO' THEN
        RAISE EXCEPTION 'Título a receber % está cancelado e não aceita recebimentos', v_titulo.id;
    END IF;
    IF NEW.situacao <> 'EFETIVO' THEN
        RAISE EXCEPTION 'Recebimento deve ser registrado como EFETIVO';
    END IF;
    IF NEW.data_recebimento < v_titulo.data_emissao THEN
        RAISE EXCEPTION 'Recebimento em % anterior à emissão do título (%)', NEW.data_recebimento, v_titulo.data_emissao;
    END IF;
    SELECT * INTO v_conta FROM conta_bancaria WHERE id = NEW.conta_bancaria_id;
    IF FOUND AND NEW.data_recebimento <= v_conta.data_saldo_inicial THEN
        RAISE EXCEPTION 'Recebimento em % anterior ao saldo inicial da conta %', NEW.data_recebimento, v_conta.codigo;
    END IF;
    v_saldo := fn_saldo_titulo_receber(v_titulo.id);
    IF NEW.valor_principal > v_saldo THEN
        RAISE EXCEPTION 'Valor principal % excede o saldo em aberto % do título % parcela %',
            NEW.valor_principal, v_saldo, v_titulo.documento, v_titulo.numero_parcela;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_recebimento_valida BEFORE INSERT OR UPDATE ON recebimento
    FOR EACH ROW EXECUTE FUNCTION fn_tg_recebimento_valida();

CREATE OR REPLACE FUNCTION fn_tg_pagamento_valida()
RETURNS trigger LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_titulo titulo_pagar%ROWTYPE;
    v_conta  conta_bancaria%ROWTYPE;
    v_saldo  numeric(14,2);
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF (to_jsonb(NEW) - ARRAY['situacao', 'data_estorno', 'motivo_estorno', 'valor_total'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['situacao', 'data_estorno', 'motivo_estorno', 'valor_total']) THEN
            RAISE EXCEPTION 'Pagamento % não pode ser alterado; estorne e registre novamente', OLD.id;
        END IF;
        IF OLD.situacao = 'ESTORNADO' THEN
            RAISE EXCEPTION 'Pagamento % já foi estornado', OLD.id;
        END IF;
        RETURN NEW;
    END IF;

    SELECT * INTO v_titulo FROM titulo_pagar WHERE id = NEW.titulo_pagar_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Título a pagar % não existe', NEW.titulo_pagar_id;
    END IF;
    IF v_titulo.situacao <> 'ATIVO' THEN
        RAISE EXCEPTION 'Título a pagar % está cancelado e não aceita pagamentos', v_titulo.id;
    END IF;
    IF NEW.situacao <> 'EFETIVO' THEN
        RAISE EXCEPTION 'Pagamento deve ser registrado como EFETIVO';
    END IF;
    IF NEW.data_pagamento < v_titulo.data_emissao THEN
        RAISE EXCEPTION 'Pagamento em % anterior à emissão do título (%)', NEW.data_pagamento, v_titulo.data_emissao;
    END IF;
    SELECT * INTO v_conta FROM conta_bancaria WHERE id = NEW.conta_bancaria_id;
    IF FOUND AND NEW.data_pagamento <= v_conta.data_saldo_inicial THEN
        RAISE EXCEPTION 'Pagamento em % anterior ao saldo inicial da conta %', NEW.data_pagamento, v_conta.codigo;
    END IF;
    v_saldo := fn_saldo_titulo_pagar(v_titulo.id);
    IF NEW.valor_principal > v_saldo THEN
        RAISE EXCEPTION 'Valor principal % excede o saldo em aberto % do título % parcela %',
            NEW.valor_principal, v_saldo, v_titulo.documento, v_titulo.numero_parcela;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_pagamento_valida BEFORE INSERT OR UPDATE ON pagamento
    FOR EACH ROW EXECUTE FUNCTION fn_tg_pagamento_valida();

-- =============================================================================
-- Funções de negócio
-- =============================================================================

-- Gera N parcelas mensais de um título a pagar. A última parcela absorve a
-- diferença de arredondamento, de modo que a soma das parcelas é exata.
CREATE OR REPLACE FUNCTION fn_gerar_titulos_pagar(
    p_documento          text,
    p_descricao          text,
    p_categoria_id       integer,
    p_centro_custo_id    smallint,
    p_fornecedor_id      integer,
    p_vendedor_id        integer,
    p_compra_veiculo_id  integer,
    p_custo_veiculo_id   bigint,
    p_venda_id           integer,
    p_data_emissao       date,
    p_data_competencia   date,
    p_primeiro_venc      date,
    p_valor_total        numeric,
    p_parcelas           integer
)
RETURNS integer
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_base  numeric(14,2);
    v_valor numeric(14,2);
    i       integer;
BEGIN
    IF p_parcelas IS NULL OR p_parcelas < 1 THEN
        RAISE EXCEPTION 'Quantidade de parcelas inválida: %', p_parcelas;
    END IF;
    IF p_valor_total IS NULL OR p_valor_total <= 0 THEN
        RAISE EXCEPTION 'Valor total deve ser positivo: %', p_valor_total;
    END IF;
    v_base := trunc(p_valor_total / p_parcelas, 2);
    FOR i IN 1 .. p_parcelas LOOP
        v_valor := CASE WHEN i < p_parcelas THEN v_base ELSE p_valor_total - v_base * (p_parcelas - 1) END;
        INSERT INTO titulo_pagar (
            documento, numero_parcela, total_parcelas, fornecedor_id, vendedor_id,
            categoria_id, centro_custo_id, compra_veiculo_id, custo_veiculo_id, venda_id,
            descricao, data_emissao, data_competencia, data_vencimento, valor)
        VALUES (
            p_documento, i, p_parcelas, p_fornecedor_id, p_vendedor_id,
            p_categoria_id, p_centro_custo_id, p_compra_veiculo_id, p_custo_veiculo_id, p_venda_id,
            CASE WHEN p_parcelas > 1 THEN p_descricao || ' (' || i || '/' || p_parcelas || ')' ELSE p_descricao END,
            p_data_emissao, p_data_competencia,
            (p_primeiro_venc + make_interval(months => i - 1))::date,
            v_valor);
    END LOOP;
    RETURN p_parcelas;
END $$;

-- Lança uma despesa operacional (aluguel, salários, marketing etc.), à vista ou parcelada.
CREATE OR REPLACE FUNCTION fn_lancar_conta_pagar(
    p_documento             text,
    p_descricao             text,
    p_categoria             text,
    p_centro_custo          text,
    p_fornecedor_documento  text,
    p_data_competencia      date,
    p_primeiro_vencimento   date,
    p_valor_total           numeric,
    p_parcelas              integer DEFAULT 1,
    p_data_emissao          date    DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
BEGIN
    RETURN fn_gerar_titulos_pagar(
        p_documento, p_descricao, fn_id_categoria(p_categoria), fn_id_centro_custo(p_centro_custo),
        fn_id_fornecedor(p_fornecedor_documento), NULL, NULL, NULL, NULL,
        COALESCE(p_data_emissao, LEAST(p_data_competencia, p_primeiro_vencimento)),
        p_data_competencia, p_primeiro_vencimento, p_valor_total, p_parcelas);
END $$;
COMMENT ON FUNCTION fn_lancar_conta_pagar(text, text, text, text, text, date, date, numeric, integer, date)
    IS 'Lança despesa operacional em uma ou mais parcelas mensais. A despesa vai à DRE pela data de competência.';

-- Lança uma conta a receber que não vem de venda de veículo (ex.: serviço de despachante).
CREATE OR REPLACE FUNCTION fn_lancar_conta_receber(
    p_documento          text,
    p_descricao          text,
    p_categoria          text,
    p_centro_custo       text,
    p_cliente_documento  text,
    p_data_competencia   date,
    p_data_vencimento    date,
    p_valor              numeric
)
RETURNS bigint
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE v_id bigint;
BEGIN
    INSERT INTO titulo_receber (
        documento, numero_parcela, total_parcelas, cliente_id, venda_id, categoria_id, centro_custo_id,
        descricao, data_emissao, data_competencia, data_vencimento, valor)
    VALUES (
        p_documento, 1, 1, fn_id_cliente(p_cliente_documento), NULL, fn_id_categoria(p_categoria),
        fn_id_centro_custo(p_centro_custo), p_descricao, LEAST(p_data_competencia, p_data_vencimento),
        p_data_competencia, p_data_vencimento, p_valor)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

-- Compra de veículo: cadastra o veículo, registra a compra e gera as contas a pagar.
-- O valor vai para o ESTOQUE (ativo), não para a DRE.
CREATE OR REPLACE FUNCTION fn_registrar_compra_veiculo(
    p_numero_compra         text,
    p_fornecedor_documento  text,
    p_data_compra           date,
    p_valor_compra          numeric,
    p_parcelas              integer,
    p_primeiro_vencimento   date,
    p_chassi                text,
    p_placa                 text,
    p_renavam               text,
    p_marca                 text,
    p_modelo                text,
    p_versao                text,
    p_ano_fabricacao        integer,
    p_ano_modelo            integer,
    p_cor                   text,
    p_quilometragem         integer,
    p_preco_anunciado       numeric
)
RETURNS integer
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_veiculo_id    integer;
    v_compra_id     integer;
    v_fornecedor_id integer := fn_id_fornecedor(p_fornecedor_documento);
BEGIN
    IF p_primeiro_vencimento < p_data_compra THEN
        RAISE EXCEPTION 'Primeiro vencimento (%) anterior à compra (%)', p_primeiro_vencimento, p_data_compra;
    END IF;

    INSERT INTO veiculo (chassi, placa, renavam, marca, modelo, versao, ano_fabricacao, ano_modelo,
                         cor, quilometragem, situacao, preco_anunciado)
    VALUES (p_chassi, p_placa, p_renavam, p_marca, p_modelo, p_versao, p_ano_fabricacao, p_ano_modelo,
            p_cor, p_quilometragem, 'EM_PREPARACAO', p_preco_anunciado)
    RETURNING id INTO v_veiculo_id;

    INSERT INTO compra_veiculo (numero_compra, veiculo_id, fornecedor_id, data_compra, valor_compra, quantidade_parcelas)
    VALUES (p_numero_compra, v_veiculo_id, v_fornecedor_id, p_data_compra, p_valor_compra, p_parcelas)
    RETURNING id INTO v_compra_id;

    PERFORM fn_gerar_titulos_pagar(
        p_numero_compra, 'Compra ' || p_marca || ' ' || p_modelo || ' chassi ' || p_chassi,
        fn_id_categoria('2.01'), fn_id_centro_custo('COM'), v_fornecedor_id, NULL,
        v_compra_id, NULL, NULL, p_data_compra, p_data_compra, p_primeiro_vencimento,
        p_valor_compra, p_parcelas);

    RETURN v_veiculo_id;
END $$;

-- Custo adicional do veículo (capitalizado no estoque) e respectivo título a pagar.
-- p_documento é o número da nota/recibo do prestador e identifica o título gerado.
CREATE OR REPLACE FUNCTION fn_registrar_custo_veiculo(
    p_documento             text,
    p_chassi                text,
    p_fornecedor_documento  text,
    p_tipo                  text,
    p_descricao             text,
    p_data_custo            date,
    p_valor                 numeric,
    p_data_vencimento       date
)
RETURNS bigint
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_custo_id      bigint;
    v_fornecedor_id integer := fn_id_fornecedor(p_fornecedor_documento);
BEGIN
    INSERT INTO custo_veiculo (veiculo_id, fornecedor_id, tipo, descricao, data_custo, valor)
    VALUES (fn_id_veiculo(p_chassi), v_fornecedor_id, p_tipo, p_descricao, p_data_custo, p_valor)
    RETURNING id INTO v_custo_id;

    PERFORM fn_gerar_titulos_pagar(
        p_documento, p_descricao || ' - chassi ' || p_chassi,
        fn_id_categoria('2.02'), fn_id_centro_custo('OFI'), v_fornecedor_id, NULL,
        NULL, v_custo_id, NULL, p_data_custo, p_data_custo, p_data_vencimento, p_valor, 1);

    RETURN v_custo_id;
END $$;

CREATE OR REPLACE FUNCTION fn_disponibilizar_veiculo(p_chassi text)
RETURNS void
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
BEGIN
    UPDATE veiculo SET situacao = 'DISPONIVEL'
     WHERE chassi = p_chassi AND situacao = 'EM_PREPARACAO';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Veículo % não encontrado ou não está EM_PREPARACAO', p_chassi;
    END IF;
END $$;

-- Venda: registra a venda (receita e CMV por competência), gera entrada/parcelas
-- a receber e o título de comissão. Não movimenta caixa: o dinheiro só entra
-- com fn_registrar_recebimento.
CREATE OR REPLACE FUNCTION fn_registrar_venda(
    p_numero_venda         text,
    p_chassi               text,
    p_cliente_documento    text,
    p_vendedor_cpf         text,
    p_data_venda           date,
    p_valor_venda          numeric,
    p_valor_entrada        numeric,
    p_parcelas             integer,
    p_primeiro_vencimento  date DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_vendedor    vendedor%ROWTYPE;
    v_venda       venda%ROWTYPE;
    v_cliente_id  integer := fn_id_cliente(p_cliente_documento);
    v_categoria   integer := fn_id_categoria('1.01');
    v_centro      smallint := fn_id_centro_custo('COM');
    v_veiculo     text;
    v_financiado  numeric(14,2);
    v_base        numeric(14,2);
    i             integer;
BEGIN
    SELECT * INTO v_vendedor FROM vendedor WHERE cpf = p_vendedor_cpf AND ativo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Vendedor com CPF % inexistente ou inativo', p_vendedor_cpf;
    END IF;
    IF p_parcelas > 0 AND (p_primeiro_vencimento IS NULL OR p_primeiro_vencimento <= p_data_venda) THEN
        RAISE EXCEPTION 'Venda parcelada exige primeiro vencimento posterior à data da venda';
    END IF;

    INSERT INTO venda (numero_venda, veiculo_id, cliente_id, vendedor_id, data_venda, valor_venda,
                       valor_entrada, quantidade_parcelas, custo_veiculo_vendido,
                       percentual_comissao, valor_comissao)
    VALUES (p_numero_venda, fn_id_veiculo(p_chassi), v_cliente_id, v_vendedor.id, p_data_venda, p_valor_venda,
            p_valor_entrada, p_parcelas, NULL,  -- custo preenchido pelo gatilho tg_venda_antes
            v_vendedor.percentual_comissao, round(p_valor_venda * v_vendedor.percentual_comissao / 100, 2))
    RETURNING * INTO v_venda;

    SELECT marca || ' ' || modelo INTO v_veiculo FROM veiculo WHERE id = v_venda.veiculo_id;

    -- Parcela 0: entrada (ou valor integral, se à vista), vence na data da venda.
    IF p_valor_entrada > 0 THEN
        INSERT INTO titulo_receber (documento, numero_parcela, total_parcelas, cliente_id, venda_id,
                                    categoria_id, centro_custo_id, descricao, data_emissao,
                                    data_competencia, data_vencimento, valor)
        VALUES (p_numero_venda, 0, p_parcelas, v_cliente_id, v_venda.id, v_categoria, v_centro,
                CASE WHEN p_parcelas = 0 THEN 'Venda à vista ' ELSE 'Entrada da venda ' END || v_veiculo,
                p_data_venda, p_data_venda, p_data_venda, p_valor_entrada);
    END IF;

    -- Parcelas mensais; a última absorve o arredondamento.
    IF p_parcelas > 0 THEN
        v_financiado := p_valor_venda - p_valor_entrada;
        v_base := trunc(v_financiado / p_parcelas, 2);
        FOR i IN 1 .. p_parcelas LOOP
            INSERT INTO titulo_receber (documento, numero_parcela, total_parcelas, cliente_id, venda_id,
                                        categoria_id, centro_custo_id, descricao, data_emissao,
                                        data_competencia, data_vencimento, valor)
            VALUES (p_numero_venda, i, p_parcelas, v_cliente_id, v_venda.id, v_categoria, v_centro,
                    'Parcela ' || i || '/' || p_parcelas || ' ' || v_veiculo,
                    p_data_venda, p_data_venda,
                    (p_primeiro_vencimento + make_interval(months => i - 1))::date,
                    CASE WHEN i < p_parcelas THEN v_base ELSE v_financiado - v_base * (p_parcelas - 1) END);
        END LOOP;
    END IF;

    -- Comissão: despesa de vendas na competência da venda; paga no dia 10 do mês seguinte.
    IF v_venda.valor_comissao > 0 THEN
        INSERT INTO titulo_pagar (documento, numero_parcela, total_parcelas, vendedor_id, categoria_id,
                                  centro_custo_id, venda_id, descricao, data_emissao, data_competencia,
                                  data_vencimento, valor)
        VALUES ('COM-' || p_numero_venda, 1, 1, v_vendedor.id, fn_id_categoria('3.01'), v_centro, v_venda.id,
                'Comissão ' || v_vendedor.nome || ' venda ' || p_numero_venda,
                p_data_venda, p_data_venda,
                (date_trunc('month', p_data_venda) + interval '1 month' + interval '9 days')::date,
                v_venda.valor_comissao);
    END IF;

    RETURN v_venda.id;
END $$;

-- Baixa de título a receber (total ou parcial) + movimento bancário de entrada.
CREATE OR REPLACE FUNCTION fn_registrar_recebimento(
    p_documento        text,
    p_numero_parcela   integer,
    p_data             date,
    p_conta            text,
    p_valor_principal  numeric,
    p_juros_multa      numeric DEFAULT 0,
    p_desconto         numeric DEFAULT 0,
    p_forma            text    DEFAULT 'PIX',
    p_observacao       text    DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_titulo_id bigint;
    v_rec       recebimento%ROWTYPE;
BEGIN
    SELECT id INTO v_titulo_id FROM titulo_receber
     WHERE documento = p_documento AND numero_parcela = p_numero_parcela;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Título a receber % parcela % não encontrado', p_documento, p_numero_parcela;
    END IF;

    INSERT INTO recebimento (titulo_receber_id, conta_bancaria_id, data_recebimento, valor_principal,
                             valor_juros_multa, valor_desconto, forma_pagamento, observacao)
    VALUES (v_titulo_id, fn_id_conta(p_conta), p_data, p_valor_principal,
            p_juros_multa, p_desconto, p_forma, p_observacao)
    RETURNING * INTO v_rec;

    INSERT INTO movimento_bancario (conta_bancaria_id, data_movimento, tipo, natureza, valor, historico, recebimento_id)
    VALUES (v_rec.conta_bancaria_id, p_data, 'ENTRADA', 'RECEBIMENTO', v_rec.valor_total,
            'Recebimento ' || p_documento || ' parcela ' || p_numero_parcela, v_rec.id);

    RETURN v_rec.id;
END $$;

-- Baixa de título a pagar (total ou parcial) + movimento bancário de saída.
CREATE OR REPLACE FUNCTION fn_registrar_pagamento(
    p_documento        text,
    p_numero_parcela   integer,
    p_data             date,
    p_conta            text,
    p_valor_principal  numeric,
    p_juros_multa      numeric DEFAULT 0,
    p_desconto         numeric DEFAULT 0,
    p_forma            text    DEFAULT 'PIX',
    p_observacao       text    DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_titulo_id bigint;
    v_pag       pagamento%ROWTYPE;
BEGIN
    SELECT id INTO v_titulo_id FROM titulo_pagar
     WHERE documento = p_documento AND numero_parcela = p_numero_parcela;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Título a pagar % parcela % não encontrado', p_documento, p_numero_parcela;
    END IF;

    INSERT INTO pagamento (titulo_pagar_id, conta_bancaria_id, data_pagamento, valor_principal,
                           valor_juros_multa, valor_desconto, forma_pagamento, observacao)
    VALUES (v_titulo_id, fn_id_conta(p_conta), p_data, p_valor_principal,
            p_juros_multa, p_desconto, p_forma, p_observacao)
    RETURNING * INTO v_pag;

    INSERT INTO movimento_bancario (conta_bancaria_id, data_movimento, tipo, natureza, valor, historico, pagamento_id)
    VALUES (v_pag.conta_bancaria_id, p_data, 'SAIDA', 'PAGAMENTO', v_pag.valor_total,
            'Pagamento ' || p_documento || ' parcela ' || p_numero_parcela, v_pag.id);

    RETURN v_pag.id;
END $$;

-- Estorno de recebimento (cheque devolvido, devolução ao cliente): o recebimento
-- original é preservado e marcado como ESTORNADO; um movimento de saída é criado.
CREATE OR REPLACE FUNCTION fn_estornar_recebimento(p_recebimento_id bigint, p_data date, p_motivo text)
RETURNS void
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE v_rec recebimento%ROWTYPE;
BEGIN
    SELECT * INTO v_rec FROM recebimento WHERE id = p_recebimento_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Recebimento % não encontrado', p_recebimento_id;
    END IF;
    IF v_rec.situacao <> 'EFETIVO' THEN
        RAISE EXCEPTION 'Recebimento % já foi estornado', p_recebimento_id;
    END IF;

    UPDATE recebimento
       SET situacao = 'ESTORNADO', data_estorno = p_data, motivo_estorno = p_motivo
     WHERE id = p_recebimento_id;

    INSERT INTO movimento_bancario (conta_bancaria_id, data_movimento, tipo, natureza, valor, historico, recebimento_id)
    VALUES (v_rec.conta_bancaria_id, p_data, 'SAIDA', 'ESTORNO_RECEBIMENTO', v_rec.valor_total,
            'Estorno do recebimento ' || p_recebimento_id || ': ' || p_motivo, p_recebimento_id);
END $$;

CREATE OR REPLACE FUNCTION fn_estornar_pagamento(p_pagamento_id bigint, p_data date, p_motivo text)
RETURNS void
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE v_pag pagamento%ROWTYPE;
BEGIN
    SELECT * INTO v_pag FROM pagamento WHERE id = p_pagamento_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pagamento % não encontrado', p_pagamento_id;
    END IF;
    IF v_pag.situacao <> 'EFETIVO' THEN
        RAISE EXCEPTION 'Pagamento % já foi estornado', p_pagamento_id;
    END IF;

    UPDATE pagamento
       SET situacao = 'ESTORNADO', data_estorno = p_data, motivo_estorno = p_motivo
     WHERE id = p_pagamento_id;

    INSERT INTO movimento_bancario (conta_bancaria_id, data_movimento, tipo, natureza, valor, historico, pagamento_id)
    VALUES (v_pag.conta_bancaria_id, p_data, 'ENTRADA', 'ESTORNO_PAGAMENTO', v_pag.valor_total,
            'Estorno do pagamento ' || p_pagamento_id || ': ' || p_motivo, p_pagamento_id);
END $$;

-- Transferência entre contas próprias: uma saída e uma entrada de mesmo valor.
CREATE OR REPLACE FUNCTION fn_registrar_transferencia(
    p_conta_origem   text,
    p_conta_destino  text,
    p_data           date,
    p_valor          numeric,
    p_descricao      text
)
RETURNS bigint
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_id      bigint;
    v_origem  smallint := fn_id_conta(p_conta_origem);
    v_destino smallint := fn_id_conta(p_conta_destino);
BEGIN
    INSERT INTO transferencia (conta_origem_id, conta_destino_id, data_transferencia, valor, descricao)
    VALUES (v_origem, v_destino, p_data, p_valor, p_descricao)
    RETURNING id INTO v_id;

    INSERT INTO movimento_bancario (conta_bancaria_id, data_movimento, tipo, natureza, valor, historico, transferencia_id)
    VALUES (v_origem,  p_data, 'SAIDA',   'TRANSFERENCIA', p_valor, 'Transferência enviada para ' || p_conta_destino || ': ' || p_descricao, v_id),
           (v_destino, p_data, 'ENTRADA', 'TRANSFERENCIA', p_valor, 'Transferência recebida de ' || p_conta_origem || ': ' || p_descricao, v_id);

    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION fn_cancelar_titulo_pagar(p_documento text, p_numero_parcela integer, p_data date, p_motivo text)
RETURNS void
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
BEGIN
    UPDATE titulo_pagar
       SET situacao = 'CANCELADO', data_cancelamento = p_data, motivo_cancelamento = p_motivo
     WHERE documento = p_documento AND numero_parcela = p_numero_parcela;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Título a pagar % parcela % não encontrado', p_documento, p_numero_parcela;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION fn_cancelar_titulo_receber(p_documento text, p_numero_parcela integer, p_data date, p_motivo text)
RETURNS void
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
BEGIN
    UPDATE titulo_receber
       SET situacao = 'CANCELADO', data_cancelamento = p_data, motivo_cancelamento = p_motivo
     WHERE documento = p_documento AND numero_parcela = p_numero_parcela;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Título a receber % parcela % não encontrado', p_documento, p_numero_parcela;
    END IF;
END $$;

-- Cancelamento de venda (desistência, distrato). Em uma única transação:
--   1. marca a venda como CANCELADA (o gatilho devolve o veículo ao estoque);
--   2. estorna todos os recebimentos efetivos (devolução do dinheiro ao cliente);
--   3. cancela as parcelas a receber e o título de comissão.
-- Receita e CMV são revertidos na DRE no mês do cancelamento; o mês da venda
-- original não é reescrito. Se a comissão já foi paga, o cancelamento é
-- recusado: primeiro estorne o pagamento da comissão.
CREATE OR REPLACE FUNCTION fn_cancelar_venda(p_numero_venda text, p_data date, p_motivo text)
RETURNS void
LANGUAGE plpgsql SET search_path = fastcar, public AS $$
DECLARE
    v_venda venda%ROWTYPE;
    v_rec   record;
BEGIN
    SELECT * INTO v_venda FROM venda WHERE numero_venda = p_numero_venda FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Venda % não encontrada', p_numero_venda;
    END IF;
    IF v_venda.situacao <> 'ATIVA' THEN
        RAISE EXCEPTION 'Venda % já está cancelada', p_numero_venda;
    END IF;
    IF EXISTS (SELECT 1
                 FROM pagamento p
                 JOIN titulo_pagar t ON t.id = p.titulo_pagar_id
                WHERE t.venda_id = v_venda.id AND p.situacao = 'EFETIVO') THEN
        RAISE EXCEPTION 'A comissão da venda % já foi paga; estorne o pagamento da comissão antes de cancelar', p_numero_venda;
    END IF;

    UPDATE venda
       SET situacao = 'CANCELADA', data_cancelamento = p_data, motivo_cancelamento = p_motivo
     WHERE id = v_venda.id;

    FOR v_rec IN
        SELECT r.id
          FROM recebimento r
          JOIN titulo_receber t ON t.id = r.titulo_receber_id
         WHERE t.venda_id = v_venda.id AND r.situacao = 'EFETIVO'
         ORDER BY r.id
    LOOP
        PERFORM fn_estornar_recebimento(v_rec.id, p_data, 'Devolução por cancelamento da venda ' || p_numero_venda);
    END LOOP;

    UPDATE titulo_receber
       SET situacao = 'CANCELADO', data_cancelamento = p_data,
           motivo_cancelamento = 'Cancelamento da venda ' || p_numero_venda || ': ' || p_motivo
     WHERE venda_id = v_venda.id AND situacao = 'ATIVO';

    UPDATE titulo_pagar
       SET situacao = 'CANCELADO', data_cancelamento = p_data,
           motivo_cancelamento = 'Cancelamento da venda ' || p_numero_venda || ': ' || p_motivo
     WHERE venda_id = v_venda.id AND situacao = 'ATIVO';
END $$;

-- -----------------------------------------------------------------------------
-- Documentação das funções (aparece no dicionário de dados)
-- -----------------------------------------------------------------------------
COMMENT ON FUNCTION fn_id_conta(text)          IS 'Retorna o id da conta bancária ativa pelo código; erro se não existir.';
COMMENT ON FUNCTION fn_id_categoria(text)      IS 'Retorna o id da categoria ativa pelo código; erro se não existir.';
COMMENT ON FUNCTION fn_id_centro_custo(text)   IS 'Retorna o id do centro de custo ativo pelo código; erro se não existir.';
COMMENT ON FUNCTION fn_id_cliente(text)        IS 'Retorna o id do cliente pelo CPF/CNPJ; erro se não existir.';
COMMENT ON FUNCTION fn_id_fornecedor(text)     IS 'Retorna o id do fornecedor pelo CPF/CNPJ (nulo se o documento for nulo); erro se não existir.';
COMMENT ON FUNCTION fn_id_veiculo(text)        IS 'Retorna o id do veículo pelo chassi; erro se não existir.';
COMMENT ON FUNCTION fn_saldo_titulo_receber(bigint) IS 'Saldo em aberto do título a receber: valor - principal das baixas efetivas.';
COMMENT ON FUNCTION fn_saldo_titulo_pagar(bigint)   IS 'Saldo em aberto do título a pagar: valor - principal das baixas efetivas.';
COMMENT ON FUNCTION fn_gerar_titulos_pagar(text, text, integer, smallint, integer, integer, integer, bigint, integer, date, date, date, numeric, integer)
    IS 'Gera parcelas mensais de um título a pagar; a última parcela absorve a diferença de arredondamento.';
COMMENT ON FUNCTION fn_lancar_conta_receber(text, text, text, text, text, date, date, numeric)
    IS 'Lança conta a receber que não vem de venda de veículo (ex.: serviço de despachante). Vai à DRE pela competência.';
COMMENT ON FUNCTION fn_registrar_compra_veiculo(text, text, date, numeric, integer, date, text, text, text, text, text, text, integer, integer, text, integer, numeric)
    IS 'Cadastra o veículo (EM_PREPARACAO), registra a compra e gera os títulos a pagar. O valor vai para o estoque, não para a DRE.';
COMMENT ON FUNCTION fn_registrar_custo_veiculo(text, text, text, text, text, date, numeric, date)
    IS 'Registra custo adicional capitalizado no veículo em estoque e o título a pagar correspondente.';
COMMENT ON FUNCTION fn_disponibilizar_veiculo(text) IS 'Libera para venda um veículo EM_PREPARACAO (passa a DISPONIVEL).';
COMMENT ON FUNCTION fn_registrar_venda(text, text, text, text, date, numeric, numeric, integer, date)
    IS 'Registra a venda (receita e CMV por competência), a entrada/parcelas a receber e o título de comissão. Não movimenta caixa.';
COMMENT ON FUNCTION fn_registrar_recebimento(text, integer, date, text, numeric, numeric, numeric, text, text)
    IS 'Baixa total ou parcial de título a receber e movimento bancário de entrada (principal + juros/multa - desconto).';
COMMENT ON FUNCTION fn_registrar_pagamento(text, integer, date, text, numeric, numeric, numeric, text, text)
    IS 'Baixa total ou parcial de título a pagar e movimento bancário de saída (principal + juros/multa - desconto).';
COMMENT ON FUNCTION fn_estornar_recebimento(bigint, date, text)
    IS 'Estorna um recebimento: marca como ESTORNADO e gera saída na mesma conta. O saldo do título volta a ficar em aberto.';
COMMENT ON FUNCTION fn_estornar_pagamento(bigint, date, text)
    IS 'Estorna um pagamento: marca como ESTORNADO e gera entrada na mesma conta. O saldo do título volta a ficar em aberto.';
COMMENT ON FUNCTION fn_registrar_transferencia(text, text, date, numeric, text)
    IS 'Transferência entre contas próprias: uma saída na origem e uma entrada no destino. Não afeta a DRE.';
COMMENT ON FUNCTION fn_cancelar_titulo_pagar(text, integer, date, text)
    IS 'Cancela título a pagar sem pagamentos efetivos. A despesa é revertida na DRE no mês do cancelamento.';
COMMENT ON FUNCTION fn_cancelar_titulo_receber(text, integer, date, text)
    IS 'Cancela título a receber avulso sem recebimentos efetivos. Parcelas de venda só são canceladas via fn_cancelar_venda.';
COMMENT ON FUNCTION fn_cancelar_venda(text, date, text)
    IS 'Cancela a venda: estorna recebimentos (devolução), cancela parcelas e comissão e devolve o veículo ao estoque.';
