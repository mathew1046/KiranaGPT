# KiranaGPT client

The Flutter client runs on Android and web. It keeps approved text transcripts
in a local queue and sends only those transcripts to `POST /v1/ingest`; raw
audio is never persisted or uploaded.

## Run locally

From this directory, provide the backend URL at build time. Do not pass
`OPENAI_API_KEY` to the app: that secret stays only in the backend environment.

```sh
flutter run \
  --dart-define=KIRANA_API_BASE_URL=http://10.0.2.2:8000
```

For a physical Android phone, replace `10.0.2.2` with the LAN address of the
machine running the backend. Web builds need the same defines and a backend
that permits the web origin with CORS.

```sh
flutter build web \
  --dart-define=KIRANA_API_BASE_URL=https://api.example.com
```

The queue storage boundary is intentionally platform-neutral. The included
`shared_preferences` implementation works on Android and web today; a native
SQLite implementation can replace it without changing the queue or sync
service.
