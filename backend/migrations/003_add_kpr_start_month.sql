-- Add start_month and start_year to kpr_simulations
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS start_month INTEGER NOT NULL DEFAULT 1;
ALTER TABLE kpr_simulations ADD COLUMN IF NOT EXISTS start_year INTEGER NOT NULL DEFAULT 2026;
