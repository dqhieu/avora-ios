-- Default generation quality is now `medium` (higher fidelity over `low`).
-- Quality is captured onto each generation row from styles.default_quality at
-- submit time, so this changes both the column default (future styles) and the
-- existing seeded styles. Revertable by setting these back to 'low'.
alter table public.styles alter column default_quality set default 'medium';
update public.styles set default_quality = 'medium';
