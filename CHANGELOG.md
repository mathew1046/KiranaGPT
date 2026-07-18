# Changelog

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
