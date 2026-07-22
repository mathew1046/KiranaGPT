# KiranaGPT

KiranaGPT is an offline-tolerant voice ledger for Kirana stores. It pairs a FastAPI backend with a Flutter Android/web client so shopkeepers can capture approved transcripts, sync them when online, and turn them into validated credit, payment, inventory, and analytics records.

Raw audio is processed in memory and is not persisted. The client queues only shopkeeper-approved text transcripts, and backend ledger changes are append-only.

## What It Includes

- FastAPI backend with SQLite-by-default persistence through SQLAlchemy.
- Flutter client for Android and web.
- Transcript ingestion, natural-language query, correction, and analysis-preview routes.
- In-memory WAV transcription endpoint backed by OpenAI audio transcription.
- Customer credit ledger with immutable sale/payment entries.
- Inventory, restock, low-stock, and daily analytics APIs.
- Optional best-effort Google Sheets mirror for completed ledger entries.
- Test coverage for backend routing, ledger, inventory, customers, health, and client queue/API behavior.

## Repository Layout

```text
.
├── app/                  # Flutter Android/web client
├── backend/              # FastAPI application and backend tests
├── docs/                 # API and implementation contracts
├── tests/                # Cross-feature backend tests
├── .env.example          # Local environment template
└── CHANGELOG.md
```

## Backend Setup

From the repository root:

```sh
cp .env.example .env
../.venv/bin/python -m pip install -r backend/requirements.txt
```

Load the `.env` values into your shell or IDE before starting the API. The code reads process environment variables directly and does not load `.env` on its own.

Start the backend:

```sh
../.venv/bin/python -m uvicorn backend.app.main:app --reload
```

The API will be available at `http://localhost:8000`. The public health endpoint is:

```sh
curl http://localhost:8000/health
```

## Backend Configuration

Key environment variables are defined in `.env.example`:

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | SQLAlchemy database URL. Defaults to `sqlite:///./kirana.db`. |
| `APP_ENV` | Runtime environment label returned by `/health`. |
| `CORS_ALLOW_ORIGINS` | Comma-separated browser origins allowed to call the API. |
| `OPENAI_API_KEY` | Backend-only OpenAI credential for transcription and LLM extraction/query routes. |
| `OPENAI_AUDIO_MODEL` | Audio transcription model. Defaults to `whisper-1`. |
| `OPENAI_EXTRACTION_MODEL` | Primary transcript extraction model. |
| `OPENAI_ESCALATION_MODEL` | Escalation model for mid-confidence extraction results. |
| `OPENAI_QUERY_MODEL` | Natural-language query model. |
| `GOOGLE_SHEETS_SPREADSHEET_ID` | Optional spreadsheet ID for audit mirroring. |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | Optional service account JSON for Google Sheets writes. |
| `MODEL_DIR` | Local speech-model asset directory. Defaults to `../models`. |

Do not put `OPENAI_API_KEY` or Google credentials in the Flutter app. Secrets stay in the backend environment only.

## API Overview

The backend exposes these primary routes:

| Route | Purpose |
| --- | --- |
| `GET /health` | Public liveness check. |
| `POST /v1/transcribe` | Accept one WAV upload, transcribe it in memory, and return text. |
| `POST /v1/analyze-preview` | Generate a reviewed proposal without writing ledger or stock state. |
| `POST /v1/analyze-preview/{proposal_id}/approve` | Persist an approved proposal. |
| `POST /v1/ingest` | Sync queued transcript events. |
| `POST /v1/query` | Answer balance or summary questions. |
| `POST /v1/correction` | Add an immutable correction entry. |
| `GET /v1/ledger/{customer_id}` | Read recent customer ledger entries and balance. |
| `GET /v1/credits` | List customers with outstanding credit. |
| `POST /v1/credits` | Add a credit sale. |
| `POST /v1/credits/payment` | Record a repayment. |
| `GET /v1/inventory` | List inventory and low-stock state. |
| `POST /v1/inventory/restock` | Restock an item. |
| `PUT /v1/inventory/{item_id}` | Update an inventory item. |
| `DELETE /v1/inventory/{item_id}` | Delete an inventory item. |
| `GET /v1/analytics/daily` | Return daily sales/debtor/top-item metrics. |
| `POST /v1/enroll-speaker` | Store a numeric speaker embedding for a customer. |

See `docs/IMPLEMENTATION_CONTRACT.md` for the shared API boundary and invariants.

## Flutter Client

The Flutter app lives in `app/`.

Install dependencies:

```sh
cd app
flutter pub get
```

Run against a local backend from an Android emulator:

```sh
flutter run --dart-define=KIRANA_API_BASE_URL=http://10.0.2.2:8000
```

Run against a local backend from web or desktop:

```sh
flutter run --dart-define=KIRANA_API_BASE_URL=http://localhost:8000
```

For a physical Android device, replace the host with the LAN address of the machine running the backend. For Firebase or other hosted web builds, configure `CORS_ALLOW_ORIGINS` on the backend and build with the deployed API URL:

```sh
flutter build web --dart-define=KIRANA_API_BASE_URL=https://api.example.com
```

More client details are in `app/README.md`.

## Testing

Run backend tests from the repository root:

```sh
../.venv/bin/python -m pytest
```

Run Flutter tests from `app/`:

```sh
flutter test
```

## Development Notes

- Ledger entries are append-only; corrections create offsetting entries rather than editing history.
- LLM output is parsed and validated before any mutation is attempted.
- Low-confidence or unavailable model results return `needs_review` instead of creating zero-value transactions.
- Google Sheets mirroring is best-effort. SQLite remains authoritative, and a Sheets outage should not block local persistence.
- Feature branches may be developed in `agent1` through `agent5` worktrees as described in `docs/IMPLEMENTATION_CONTRACT.md`.
