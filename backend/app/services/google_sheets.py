"""Best-effort Google Sheets mirror for completed shop ledger entries."""

from __future__ import annotations

import json
import logging
from typing import Any


logger = logging.getLogger(__name__)
_SHEETS_SCOPE = "https://www.googleapis.com/auth/spreadsheets"


class GoogleSheetsMirror:
    """Append a compact audit row when Sheets credentials are configured.

    SQLite remains authoritative. A Sheets outage never prevents a sale, credit,
    or customer payment from being persisted locally.
    """

    def __init__(self, settings: object) -> None:
        self._spreadsheet_id = getattr(settings, "google_sheets_spreadsheet_id", None)
        self._service_account_json = getattr(settings, "google_service_account_json", None)

    @property
    def enabled(self) -> bool:
        return bool(self._spreadsheet_id and self._service_account_json)

    def append_ledger_entry(self, *, entry: Any, customer_name: str, extraction: Any) -> None:
        if not self.enabled:
            return
        try:
            from google.auth.transport.requests import AuthorizedSession
            from google.oauth2.service_account import Credentials

            credentials = Credentials.from_service_account_info(
                json.loads(self._service_account_json), scopes=[_SHEETS_SCOPE]
            )
            session = AuthorizedSession(credentials)
            values = [[
                entry.created_at.isoformat() if entry.created_at else "",
                str(entry.id),
                customer_name,
                extraction.entry_type.value,
                str(entry.amount),
                extraction.item_name or "",
                str(extraction.quantity) if extraction.quantity is not None else "",
                extraction.unit or "",
            ]]
            response = session.post(
                f"https://sheets.googleapis.com/v4/spreadsheets/{self._spreadsheet_id}/values/Ledger!A:H:append",
                params={"valueInputOption": "USER_ENTERED", "insertDataOption": "INSERT_ROWS"},
                json={"values": values},
                timeout=10,
            )
            response.raise_for_status()
        except Exception as exc:
            # Never log credentials, customer input, or transcript content.
            logger.warning("Google Sheets mirror failed (%s)", type(exc).__name__)
