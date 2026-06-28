begin;
select plan(9);

select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'styles', 'styles exists');
select has_table('public', 'generations', 'generations exists');
select has_table('public', 'purchases', 'purchases exists');
select has_table('public', 'daily_spend', 'daily_spend exists');

select col_default_is('public', 'profiles', 'extra_credits', '50', 'starter extra credits = 50');
select col_has_check('public', 'generations', 'status', 'status is constrained');
select has_column('public', 'generations', 'charged_amount', 'charged_amount column exists');
select col_is_pk('public', 'purchases', 'transaction_id', 'purchases pk is transaction_id');

select * from finish();
rollback;
