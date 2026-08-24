# Changelog

## 0.4.1 — 2026-08-24

- Reflow the 30-day heatmap to 3 rows × 10 columns so it stays within the card height.
- Rename the Atoll card header to “Codex 额度监控” and remove the visible heatmap caption.
- Show `PLUS`, 7-day usage, and lifetime usage together below the quota progress bar.

## 0.4.0 — 2026-08-24

- Normalize sparse daily token buckets into a fixed 30-day activity series.
- Replace the 7-day and lifetime metrics with a 5 × 6 usage heatmap.
- Keep the 60% / 20% / 20% layout and move both reset times to the right column.
- Add model coverage for missing days, duplicate daily buckets, and the 30-day boundary.

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
