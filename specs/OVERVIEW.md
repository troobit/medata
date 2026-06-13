# Specs Overview

| Name | Creation Date | Status | Summary |
|------|---------------|--------|---------|
| [Rawframe Rgb Conversion](#rawframe-rgb-conversion) | 2026-05-06 | Done | Convert ARKit YCbCr frames to BGRA8 at the capture boundary so downstream consumers read correct bytes. |
| [Ui](#ui) | 2026-05-22 | Done | v1 iPhone experience: three-tab shell, live AR preview, result view, meal history, and settings. |
| [Research](#research) | 2026-05-24 | Done | Low-compute on-device system estimating carbohydrate content from one or two iPhone photos. |
| [Shutter Blocked Feedback](#shutter-blocked-feedback) | 2026-05-31 | In Progress | Surface haptic, indicator badge, and OSLog diagnostics when the disabled Photo-tab shutter is tapped. |
| [Event Log Schema](#event-log-schema) | 2026-06-10 | Done | Uplift persistence to a long-form event log with fixed timestamp/event_type/value columns and JSON metadata. |

---

## Rawframe Rgb Conversion

Convert ARKit YCbCr frames to BGRA8 at the capture boundary so downstream consumers read correct bytes.

- [decision_log.md](rawframe-rgb-conversion/decision_log.md)
- [design.md](rawframe-rgb-conversion/design.md)
- [requirements.md](rawframe-rgb-conversion/requirements.md)
- [tasks.md](rawframe-rgb-conversion/tasks.md)

## Ui

v1 iPhone experience: three-tab shell, live AR preview, result view, meal history, and settings.

- [decision_log.md](ui/decision_log.md)
- [design.md](ui/design.md)
- [prerequisites.md](ui/prerequisites.md)
- [requirements.md](ui/requirements.md)
- [tasks.md](ui/tasks.md)

## Research

Low-compute on-device system estimating carbohydrate content from one or two iPhone photos.

- [decision_log.md](research/decision_log.md)
- [design.md](research/design.md)
- [prerequisites.md](research/prerequisites.md)
- [requirements.md](research/requirements.md)
- [tasks.md](research/tasks.md)

## Shutter Blocked Feedback

Surface haptic, indicator badge, and OSLog diagnostics when the disabled Photo-tab shutter is tapped.

- [decision_log.md](shutter-blocked-feedback/decision_log.md)
- [smolspec.md](shutter-blocked-feedback/smolspec.md)
- [tasks.md](shutter-blocked-feedback/tasks.md)

## Event Log Schema

Uplift persistence to a long-form event log with fixed timestamp/event_type/value columns and JSON metadata.

- [decision_log.md](event-log-schema/decision_log.md)
- [design.md](event-log-schema/design.md)
- [requirements.md](event-log-schema/requirements.md)
- [tasks.md](event-log-schema/tasks.md)
