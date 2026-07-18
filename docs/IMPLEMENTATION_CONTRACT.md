# KiranaGPT implementation contract

This document translates the supplied project plan into stable, merge-friendly boundaries.

## Product boundary

KiranaGPT captures a shopkeeper-approved transcript, queues it locally while offline, turns it into a validated ledger mutation when online, and gives a concise spoken/displayed confirmation. Raw audio is never uploaded or persisted; only text transcripts and speaker embeddings are handled.

## API boundary

All HTTP routes are prefixed with `/v1` and require `Authorization: Bearer <APP_API_KEY>` except `/health`.

| Route | Request role | Response role |
| --- | --- | --- |
| `POST /v1/ingest` | Batch of locally queued transcripts | Per-item sync/needs-review result |
| `POST /v1/query` | Natural-language balance/summary question | Short spoken-friendly answer |
| `POST /v1/correction` | Cancel/amend a recent ledger event | Immutable offsetting ledger entry |
| `GET /v1/analytics/daily` | Date-range metrics | Revenue, debtors, and top items |
| `GET /v1/inventory` | Inventory state | Current stock and low-stock items |
| `POST /v1/inventory/restock` | Manual stock addition | Updated inventory item |
| `POST /v1/enroll-speaker` | Numeric speaker embedding only | Enrollment acknowledgement |

## Mandatory invariants

- `ledger_entries` are append-only. Corrections add offsetting rows, never mutate historical rows.
- LLM output must be parsed and validated before a ledger mutation is attempted.
- Inference routing lives in one configuration/function, with an explicit low-confidence escalation path.
- An extraction failure returns `needs_review`; it must not create a zero-value transaction.
- The app keeps only transcripts in its local SQLite queue. Its recording buffer is discarded immediately.
- Client code must work on Android and web. Native voice capture should degrade safely to manual transcript entry on web.

## Parallel ownership

| Worktree / branch | Ownership |
| --- | --- |
| `agent1` / `feature/backend-core` | FastAPI application, persistence, auth, ledger service, tests |
| `agent2` / `feature/llm-routing` | Extraction schemas, OpenAI adapter, confidence router, ingest/query/correction endpoints |
| `agent3` / `feature/flutter-shell` | Flutter project, design system, local transcript queue, API client |
| `agent4` / `feature/inventory-analytics` | Inventory, low-stock logic, analytics API/service and tests |
| `agent5` / `feature/flutter-voice-dashboard` | Flutter voice capture abstraction, speaker enrollment, dashboard and confirmation UI |

Each branch adds its own tests and updates `CHANGELOG.md`. Avoid changing another branch's owned files unless needed to resolve a documented contract mismatch.
