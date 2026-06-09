#!/bin/bash
cd /home/hermes/dev/wealthtrack/backend
export WEALTHTRACK_TEST_DATABASE_URL="postgresql://wealthtrack_test:wealthtrack_test123@localhost:5432/wealthtrack_test"
source ../.venv/bin/activate
exec python -m pytest "$@"
