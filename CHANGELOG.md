# Changelog

## [2026-07-19 00:48] Backend core scaffold
- What changed: Added the FastAPI application factory, environment-backed settings, SQLite/PostgreSQL-compatible SQLAlchemy setup, constant-time bearer-key authentication, append-only ledger models/services, conservative local customer matching, speaker-embedding enrollment, health, and customer-ledger read endpoints.
- Files touched: `backend/`, `CHANGELOG.md`.
- Why: Provides the secure persistence and API foundation for the ingestion, correction, inventory, analytics, Android, and web feature branches.
- Known issues / follow-ups: The sandbox blocks AnyIO's threaded FastAPI test transport, so endpoint tests are included but need one normal-host run; raw audio remains intentionally unsupported and is never persisted.

## [2026-07-19 00:10] Secure project baseline
- What changed: Added repository ignore rules, a safe environment template, and the implementation contract for parallel development.
- Files touched: `.gitignore`, `.env.example`, `CHANGELOG.md`, `docs/IMPLEMENTATION_CONTRACT.md`.
- Why: Establishes secret handling and stable cross-team contracts before feature branches begin.
- Known issues / follow-ups: Backend, Flutter app, and deployment files are still to be implemented in their feature branches.
