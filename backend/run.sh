#!/bin/bash
cd "$(dirname "$0")/.."
source .venv/bin/activate
cd backend
uvicorn app.main:app --host 127.0.0.1 --port 8080 --reload
