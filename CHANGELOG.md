# Changelog

## [2026-07-19 00:40] Flutter queue foundation
- What changed: Added the Android/web Flutter project, adaptive Material 3 shell, text-only manual transcript entry, local queue abstraction, bearer-authenticated ingest client, and Dart tests.
- Files touched: `app/`, `CHANGELOG.md`.
- Why: Gives the product an offline-safe client foundation that follows the shared ingest and privacy contract.
- Known issues / follow-ups: Set `KIRANA_API_BASE_URL` and `KIRANA_APP_API_KEY` with Dart defines before syncing; voice capture and dashboard destinations remain owned by their dedicated feature branch.

## [2026-07-19 00:10] Secure project baseline
- What changed: Added repository ignore rules, a safe environment template, and the implementation contract for parallel development.
- Files touched: `.gitignore`, `.env.example`, `CHANGELOG.md`, `docs/IMPLEMENTATION_CONTRACT.md`.
- Why: Establishes secret handling and stable cross-team contracts before feature branches begin.
- Known issues / follow-ups: Backend, Flutter app, and deployment files are still to be implemented in their feature branches.
