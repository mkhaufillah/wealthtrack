"""
Migration v0.7.1: Remove penalty_rate and penalty_amount columns from kpr_extra_payments.

Usage: python3 migrate_v0_7_1.py
"""
import os, subprocess, sys

# Read DATABASE_URL from .env
env_path = os.path.expanduser('~/dev/wealthtrack/backend/.env')
if not os.path.exists(env_path):
    print(f"ERROR: .env not found at {env_path}")
    sys.exit(1)

result = subprocess.run(
    ['grep', '-oP', r'^DATABASE_URL=\K.*', env_path],
    capture_output=True, text=True
)
db_url = result.stdout.strip()
if not db_url:
    print("ERROR: DATABASE_URL not found in .env")
    sys.exit(1)

# Run the ALTER TABLE
try:
    subprocess.run([
        'psql', db_url, '-c',
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS penalty_rate;"
    ], check=True, capture_output=True, text=True)
    print("✓ Column penalty_rate dropped successfully")
    subprocess.run([
        'psql', db_url, '-c',
        "ALTER TABLE kpr_extra_payments DROP COLUMN IF EXISTS penalty_amount;"
    ], check=True, capture_output=True, text=True)
    print("✓ Column penalty_amount dropped successfully")
except subprocess.CalledProcessError as e:
    print(f"ERROR: {e.stderr}")
    sys.exit(1)
