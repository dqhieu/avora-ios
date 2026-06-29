-- Default generation quality is now `low` (cost reduction over `medium`).
-- Quality is captured onto each generation row from styles.default_quality at
-- submit time, so this changes both the column default (future styles) and the
-- existing seeded styles. Revertable by setting these back to 'medium'.
alter table public.styles alter column default_quality set default 'low';
update public.styles set default_quality = 'low';
