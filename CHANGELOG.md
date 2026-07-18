# Changelog

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
