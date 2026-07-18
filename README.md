# KiranaGPT

An offline-tolerant voice ledger for Kirana stores, with a FastAPI service and a Flutter Android/web client.

## Local setup

1. Use the supplied environment: `../.venv/bin/python` from this repository directory.
2. Move/copy `.env.example` to `.env` and provide local values. `.env` is ignored.
3. The supplied speech-model assets remain outside Git at `../models`; configure `MODEL_DIR` if they live elsewhere.

Feature branches are developed in the `agent1` through `agent5` worktrees. See [the implementation contract](docs/IMPLEMENTATION_CONTRACT.md) for the shared API and privacy rules.
