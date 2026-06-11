# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in `pitchplatforms/pitchin-issues`.

| Canonical role    | Label in our tracker | Meaning                                  |
| ----------------- | -------------------- | ---------------------------------------- |
| `needs-triage`    | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`      | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent` | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human` | `ready-for-human`    | Requires human implementation            |
| `wontfix`         | `wontfix`            | Will not be actioned                     |

Additional workspace labels (beyond the canonical five):

| Label                | Meaning                                                  |
| -------------------- | -------------------------------------------------------- |
| `needs-human-verify` | Agent finished; human must verify before close            |
| `repo:api`           | Slice touches `pitchINAPI`                                |
| `repo:admin`         | Slice touches `PitchinAdminWeb`                           |
| `repo:customer`      | Slice touches `PitchinCustomerWeb`                        |
| `needs:e2e`          | Requires a Playwright e2e run                             |
| `needs:ocr`          | Requires Gemini OCR / receipt check                       |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.
