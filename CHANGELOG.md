# Changelog

## [2026-07-19 00:55] Wire feature routers into the application
- What changed: Registered processing and inventory/analytics routes in the FastAPI application factory, with authenticated single-store MVP inventory state and immutable-ledger analytics projections.
- Files touched: `backend/app/main.py`, `CHANGELOG.md`.
- Why: Makes the merged feature modules available to the Android/web client through the documented API contract.
- Known issues / follow-ups: Inventory persistence and automatic LLM-sale deduction are the next production hardening step; this MVP route keeps state for the running demo process.

## [2026-07-19 00:48] Backend core scaffold
- What changed: Added the FastAPI application factory, environment-backed settings, SQLite/PostgreSQL-compatible SQLAlchemy setup, constant-time bearer-key authentication, append-only ledger models/services, conservative local customer matching, speaker-embedding enrollment, health, and customer-ledger read endpoints.
- Files touched: `backend/`, `CHANGELOG.md`.
- Why: Provides the secure persistence and API foundation for the ingestion, correction, inventory, analytics, Android, and web feature branches.
- Known issues / follow-ups: The sandbox blocks AnyIO's threaded FastAPI test transport, so endpoint tests are included but need one normal-host run; raw audio remains intentionally unsupported and is never persisted.

## [2026-07-19 00:48] Validated LLM processing boundary
- What changed: Added strict transcript/LLM schemas, one bounded confidence router, a `store=False` OpenAI Responses adapter with structured JSON validation/retry and safe offline fallback, plus protected ingest/query/correction route factories.
- Files touched: `backend/app/llm/`, `backend/app/routers/processing.py`, `backend/app/routes/llm.py`, `tests/test_llm_routing.py`, `tests/test_processing_router.py`, `CHANGELOG.md`.
- Why: Ensures only validated, high-confidence text extraction can reach append-only ledger operations; malformed, unavailable, or low-confidence inference is returned as `needs_review` without creating a zero-value transaction.
- Known issues / follow-ups: Backend app factory must include `create_llm_router()` from `backend.app.routes.llm`; runtime OpenAI SDK dependency is pinned by backend-core.

## [2026-07-19 00:40] Flutter queue foundation
- What changed: Added the Android/web Flutter project, adaptive Material 3 shell, text-only manual transcript entry, local queue abstraction, bearer-authenticated ingest client, and Dart tests.
- Files touched: `app/`, `CHANGELOG.md`.
- Why: Gives the product an offline-safe client foundation that follows the shared ingest and privacy contract.
- Known issues / follow-ups: Set `KIRANA_API_BASE_URL` and `KIRANA_APP_API_KEY` with Dart defines before syncing; voice capture and dashboard destinations remain owned by their dedicated feature branch.

## [2026-07-19 00:35] Flutter voice capture and dashboard feature
- What changed: Added a transcript-only voice-capture boundary with manual/browser fallback, consent-first speaker-enrollment UI/controller, and compact capture, queue, and confirmation dashboard cards.
- Files touched: `app/lib/features/voice/`, `app/lib/features/dashboard/`, `CHANGELOG.md`.
- Why: Adds merge-ready Flutter feature destinations without changing the app shell, dependencies, or raw-audio privacy boundary.
- Known issues / follow-ups: The host app must register `kiranaVoiceDashboardDestinations(...)` through `KiranaApp.additionalDestinations` and provide production native recognizer/enrollment adapters when available.

## [2026-07-19 00:10] Secure project baseline
- What changed: Added repository ignore rules, a safe environment template, and the implementation contract for parallel development.
- Files touched: `.gitignore`, `.env.example`, `CHANGELOG.md`, `docs/IMPLEMENTATION_CONTRACT.md`.
- Why: Establishes secret handling and stable cross-team contracts before feature branches begin.
- Known issues / follow-ups: Backend, Flutter app, and deployment files are still to be implemented in their feature branches.

## [2026-07-19 00:18] Inventory and analytics domain services
- What changed: Added validated inventory restock/sale contracts, append-only inventory transaction recording, low-stock detection, and immutable-ledger analytics aggregation.
- Files touched: `backend/app/inventory/`, `backend/app/routers/inventory.py`, `backend/tests/test_inventory_service.py`, `CHANGELOG.md`.
- Why: Keeps stock updates non-blocking for ledger writes and makes daily analytics auditable from immutable ledger events.
- Known issues / follow-ups: The backend-core branch must inject its persistence/auth hooks into `build_inventory_router` during integration.

## [2026-07-19 00:28] Inventory API route verification
- What changed: Added authenticated route tests for inventory, restocking, analytics, and invalid payloads; fixed dependency injection so store identity is resolved through the injected auth dependency.
- Files touched: `backend/app/routers/inventory.py`, `backend/tests/test_inventory_router.py`, `CHANGELOG.md`.
- Why: Ensures API requests cannot silently bypass store scoping or write invalid stock values.
- Known issues / follow-ups: FastAPI client tests need the permitted local runtime because the filesystem sandbox blocks its threaded portal; all nine inventory tests pass there.
