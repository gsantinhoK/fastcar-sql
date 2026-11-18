-- =============================================================================
-- Fast Car - Sistema Financeiro em SQL
-- Arquivo : sql/run_all.sql
-- Objetivo: criar tudo do zero na ordem correta de dependências.
--   01_schema    -> tabelas, restrições e índices (recria o schema fastcar)
--   02_functions -> gatilhos e funções de negócio (dependem das tabelas)
--   03_seed      -> dados fictícios (usam as funções)
--   04_views     -> views e funções de relatório (dependem das tabelas e funções)
-- Uso: psql -d fastcar -f sql/run_all.sql
-- Relatórios e testes são executados à parte (05_reports.sql e tests/financial_checks.sql).
-- =============================================================================

\set ON_ERROR_STOP on
\echo 'Fast Car: 01_schema.sql'
\ir 01_schema.sql
\echo 'Fast Car: 02_functions.sql'
\ir 02_functions.sql
\echo 'Fast Car: 03_seed.sql'
\ir 03_seed.sql
\echo 'Fast Car: 04_views.sql'
\ir 04_views.sql
\echo 'Fast Car: estrutura e dados carregados com sucesso.'
