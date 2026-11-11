# Dashboard chart gate hardening

Prediction: 5a9c576; corrected runnable measurement: 8fc9fff. Both precede
the browser baseline and the implementation. The source stays frozen while
the queued browser control suite runs. No additional full dotfiles gate is
queued before the exact delivery union is assembled.

## Hypothesis and thresholds

Goal: reliable hourly charts and interaction evidence. UTC bucket keys and
direct browser checks should preserve 168 of 168 elapsed hours through each
clock change, produce zero keyboard/touch failures, and keep each chart line
at or above 3:1 contrast in light and dark. Measurement:
`heavy-run bats tests/tooling-checkup-dashboard-hours.bats tests/tooling-checkup-dashboard.bats`.

Success requires every threshold. Any lost hour, interaction failure, or
line under 3:1 abandons this implementation until a reliable gate covers the
failing case. Anchor: WCAG 2.2 non-text contrast (1.4.11); Basili, Caldiera,
Rombach (1994), Goal Question Metric.

## Changes and measurement scope

- Exporter buckets by epoch-derived UTC hour. The page parses the full
  timezone-bearing key and formats only display labels in local time.
- Fixed 168-hour spring/fall fixtures verify unique, ordered instants and
  original sample binding. A local calendar week can instead span 167 or
  169 elapsed hours; these fixtures do not assert otherwise.
- Phone checks send a real touchscreen tap and require an earlier selected
  point. ArrowLeft must change the tooltip. Planted broken controls must fail.
- Chart colors retain their hue. Lightness changes only when the line needs
  more contrast against the panel token and nearest opaque ancestor. The
  browser fixture gate independently measures the panel ratio at 3:1.

The browser baseline failed on all 168 shifted hours in each of four theme
and viewport combinations. Dark chart lines also failed at 2.86:1 and
2.97:1. The exporter UTC regression failed before its fix, then passed both
168-hour cases. Final browser control results are pending; read their
actual exit and assertions before changing the source or claiming success.

## Delivery and real-host proof

The harness uses the production fragment in a synthetic host with
fabricated datasets. This is unit proof only. A deployed test dashboard
needs labeled before-left/after-right screenshots for hourly chart binding
and chart contrast, in light/dark and phone/desktop, followed by an
independent blind review. Do not commit screenshots or private metrics.

Inspect the existing dashboard read-only through the task-owned pinned
browser tab. Do not upload new payloads or change the owner's dashboard.
If the deployed host is inaccessible or the Dashboard writer is unavailable,
retain this UI work as a draft with an explicit blocked validation task.
Keep the exact union gate separate from that external proof requirement.
