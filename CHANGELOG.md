# Changelog

## 0.3.1 — 2026-08-23

- Keep the Atoll card action enabled after monitoring starts.
- Turn the action into a reusable “刷新额度” command with in-progress and result feedback.
- Wait for each manual refresh to finish before reporting success in the card.
- Retry Codex every 15 seconds while offline and return to the 60-second interval after reconnecting.
- Replace a persisted stale Atoll card when the plugin relaunches.

## 0.3.0 — 2026-08-21

- Publish quota data as a regular Atoll swipeable extension card.
- Add a one-page 60% / 20% / 20% layout.
- Add Codex and Atoll connection indicators and update time.
- Add the interactive “启用额度监控” action.
- Remove the “今天” metric and estimated-reset marker.
- Add Atoll 2.3.3 extension-host compatibility checks.
