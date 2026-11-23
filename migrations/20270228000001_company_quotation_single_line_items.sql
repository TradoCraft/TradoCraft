ALTER TABLE core.companies
  ADD COLUMN quotation_single_line_items BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN autosave_minutes INTEGER NOT NULL DEFAULT 5;
