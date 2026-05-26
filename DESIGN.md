# tymeline - Design (v0.2 draft)

**Status:** v0.2 draft, 25.05.2026
**Author:** Dario Ristic
**License:** MIT
**Reviewers:** Solo (Dario)
**Target audience:** Individual developers (and small teams) who track time on Linear issues via Clockify and want it automated

> v0.2 reframes the project from "Coorpix internal tool" (v0.1) to "solo open-source side project". Scope changes: anyone can install, multi-workspace support is now core (not edge case), trust model is "audit the source or trust the signing identity" rather than "trust the publishing organization". Items marked `[TBD: ...]` are open questions. Items in *italics* are non-binding recommendations.

---

## 1. Goal

Eliminate manual Clockify time tracking for developers who work off Linear issues, by tying time entries to Linear issue state changes. API keys live only on the user's machine; the project has no central server and no telemetry.

**Success criteria:**

- Starting work on a Linear issue starts a Clockify timer with zero or one click
- Closing or unassigning the issue stops the timer automatically
- Users don't lose hours to forgetting to start/stop a timer
- API keys and time data never leave the user's machine
- A solo developer or a small team can install and use the app within 10 minutes of first download

**Non-goals (v1):**

- Replacing Clockify (still used for reports, approvals, invoicing)
- Replacing Linear (issues, comments, transitions stay there)
- Project management (no scheduling, sprint reports, etc.)
- Cross-platform beyond macOS (Tauri port deferred to v2, see section 12)

---

## 2. User journey - "A day with tymeline"

**Morning (start of day):**

- User opens Mac, menubar icon shows last state (probably "idle, no timer running")
- User opens Linear, drags ENG-153 from Backlog to In Progress
- ~30s later, menubar icon turns green, native notification: "Started timer: ENG-153 - OpenShift SSL setup"
- *No further action needed*

**Mid-task switch:**

- User gets pulled into urgent issue ENG-160. Drags it to In Progress in Linear, drags ENG-153 back to Todo
- Notification: "Switched: stopped ENG-153 (47min), started ENG-160"
- Audit log records both actions

**Lunch break:**

- User locks Mac (Ctrl+Cmd+Q) or screensaver kicks in
- Timer keeps running for `idleThreshold` minutes (default 10min), then auto-stops with end time = last activity
- On unlock app prompts "Resume ENG-153?" if timer was auto-stopped (see section 4.4)

**End of day:**

- User drags ENG-160 to Done in Linear
- Timer stops, notification: "Logged 3h 22min on ENG-160"
- User clicks menubar to see today's summary: 4 issues, 6h 50min total

**Multi-workspace flow:**

- User has two Linear/Clockify workspace pairs configured: "Work" and "Personal"
- Each pair has its own poll loop and its own active-timer state
- *[TBD: can two workspaces hold an active timer simultaneously? Clockify rule is one running entry per user per workspace, but two different Clockify accounts is allowed. See section 4.10]*

**Failure mode - unassigned issue moved to In Progress:**

- Someone creates an issue and transitions it to In Progress without assigning it
- No timer starts (no assignee to start it for)
- *Linear workflow recommendation, not a tool concern - we surface this as a no-op in the audit log*

---

## 3. Architecture overview

```
+---------------------------------------------------+
|                  macOS Menubar App                |
|                                                   |
|  +-----------+   +----------+   +--------------+  |
|  | MenuBar   |   | Settings |   | Onboarding   |  |
|  | (SwiftUI) |   | Window   |   | Wizard       |  |
|  +-----------+   +----------+   +--------------+  |
|        |              |                |          |
|  +---------------------------------------------+  |
|  |        App State (Swift Observation)          |
|  |        Workspace Manager (N workspaces)       |
|  +---------------------------------------------+  |
|        |          |          |          |         |
|  +---------+ +---------+ +--------+ +---------+   |
|  | Linear  | | Clockify| | Local  | | macOS   |   |
|  | Client  | | Client  | | DB     | | System  |   |
|  | (GQL)   | | (REST)  | | (GRDB) | | (Idle,  |   |
|  | per-ws  | | per-ws  | |        | | Keychain|   |
|  |         | |         | |        | | Notify) |   |
|  +---------+ +---------+ +--------+ +---------+   |
+---------------------------------------------------+
         |              |
    Linear API     Clockify API
   (GraphQL +    (REST + per-user
   polling*)      API key)
```

*See section 5.2 for Linear-side mechanics - we poll on a configurable interval (default 30s) because Linear webhooks require a public endpoint, which a client-only app can't expose.*

Workspace Manager owns N independent (Linear client, Clockify client, poll loop) tuples - one per configured workspace pair. See section 4.10.

---

## 4. Core features (v1 scope)

### 4.1 Menubar item

- Icon states: `idle` (gray), `running` (green pulse), `error` (red), `paused` (yellow)
- Tooltip: current task + elapsed time + active workspace name
- Click: opens popover with current timer, "My active Linear issues" list (across all workspaces), today's summary, workspace switcher, settings shortcut

### 4.2 Auto start/stop on Linear status change

- Poll Linear for issues assigned to me, every 30s (configurable), per workspace
- On status transition `unstarted -> started`: start Clockify timer on mapped project, description format `<ISSUE-ID>: <title>`
- On status transition `started -> completed/canceled/unstarted`: stop Clockify timer if currently running for that issue
- On assignee change away from me while `started`: stop my timer
- On assignee change to me on a `started` issue: start my timer (with notification, not silent - this can surprise people)

### 4.3 Multiple In Progress handling
Linear allows multiple issues in "In Progress" simultaneously. Clockify timer can only run on one task at a time **per workspace**.

*Recommendation: "last status change wins" within a workspace. When a user moves a second issue to In Progress, stop the previous timer and start the new one. Notification surfaces both events. This matches user intuition ("I'm switching context") better than treating it as an error.*

### 4.4 Idle / lock handling

- macOS lock, screensaver, sleep, and no-keyboard/mouse activity all feed the same idle signal - one unified policy
- Timer keeps running until `idleThreshold` minutes of idle (default 10min)
- After threshold: stop timer, log entry with end time = last activity, send notification "Timer auto-stopped due to inactivity"
- On unlock or activity resumption with timer auto-stopped: prompt "Resume ENG-153?" with Yes/No
- *[TBD: long-sleep edge case - if Mac slept for 16h overnight, do we still prompt "Resume yesterday's timer?" or auto-discard the prompt after some staleness window (e.g. 2h)?]*

### 4.5 12-hour cap (sanity check)

- If timer has been running > 12h without lock/idle events: send notification "Timer has been running 12h+, did you forget to stop it?"
- If user dismisses or doesn't act within 30min: cap entry at 12h and stop
- Catches the "left Mac running, went on vacation" failure mode

### 4.6 Manual override (always available)

- "Start timer manually" - pick from My Linear Issues list, or enter free-text description
- "Stop timer manually" - one click
- "Edit current entry description" - in case Linear title is bad or there's an addendum
- *Rationale: automation must never block manual flow. If Linear API is down, manual still works.*

### 4.7 Today's summary view

- List of today's time entries with duration, project, Linear ID, workspace badge
- Click an entry: open Clockify web for that entry (deep link)
- "Open Clockify" / "Open Linear" buttons for full UI (per active workspace)

### 4.8 Onboarding wizard (first run)

1. Welcome screen, explanation, link to GitHub repo
2. "Add your first workspace": name it (e.g. "Work", "Personal")
3. Linear: paste API key, with link to Linear settings page
4. Clockify: paste API key, with link to Clockify profile
5. Test connection (fetch current user from both APIs)
6. Project mapping: app shows Linear projects user has access to, asks which Clockify project to map to (suggests by name match)
7. Behavior preferences: auto-start (yes/notification/off), idle threshold, notification style
8. "Add another workspace?" - loop or proceed to done
9. Done - app is now in normal operation

### 4.9 Settings window

- **Workspaces** section: list of configured workspaces with add/edit/delete, per-workspace API key rotation, per-workspace project mappings
- Global behavior toggles (auto-start, idle threshold, 12h cap, notification verbosity)
- "Export audit log" (CSV) - useful for personal reconciliation against Clockify
- About / version / check for updates / link to GitHub repo + issues

### 4.10 Multi-workspace support
The app supports N independent workspace pairs (each = one Linear API key + one Clockify API key). Typical use cases:

- Solo developer with a "Day job" workspace and a "Personal projects" workspace
- Consultant with multiple client workspaces, each with its own Linear+Clockify tenant
- Someone in transition between jobs (overlapping API keys for a few weeks)

**Per-workspace state:**

- Independent poll loop (each polls on the global interval, no shared rate budget concerns - Linear's 1500/hr is per-API-key)
- Independent active timer (one running Clockify entry per workspace is allowed)
- Independent project mapping table
- Workspace name and color visible in UI to disambiguate

**Cross-workspace rules:**

- Idle/lock detection is global - stops all running timers across all workspaces after idle threshold
- 12h cap applies per timer (not summed across workspaces)
- Notifications include workspace name when more than one is configured

*[TBD: should the menubar icon show different state when timers in different workspaces have different status (e.g. one running, one paused)? Recommendation: show the "highest priority" state (running > paused > idle), tooltip enumerates per-workspace state.]*

*[TBD: simultaneous timers in multiple workspaces - allow by default? Some users want this (real concurrent work for two clients in the same hour is rare but legitimate for support+dev split). Others find it confusing. Recommendation: allow, with a notification on first occurrence "You now have timers running in 2 workspaces - this is intentional but unusual."]*

---

## 5. Tech stack

### 5.1 Application

- **Language:** Swift 6 (current stable)
- **UI:** SwiftUI for popover/settings/onboarding. AppKit for the menubar item itself (`NSStatusItem`)
- **State:** Swift Observation framework (macOS 14+ target)
- **Storage:** GRDB.swift (SQLite wrapper) for local audit log + cached Linear issue state + workspace registry
- **Secrets:** macOS Keychain via the `Security` framework (no third-party wrapper needed for our scope). Service: `app.tymeline`, accounts: `linear-<workspaceUUID>` and `clockify-<workspaceUUID>`
- **Notifications:** `UserNotifications` framework
- **Idle detection:** `CGEventSourceSecondsSinceLastEventType` polling + `NSWorkspace` lock/sleep notifications
- **HTTP:** `URLSession` with async/await (no Alamofire / no dependencies)
- **Auto-update:** Sparkle (industry standard for non-App-Store Mac apps)
- **Bundle ID:** `app.tymeline`

### 5.2 External APIs

**Linear (GraphQL):**

- Authenticate with personal API key (header: `Authorization: <api-key>`)
- Poll: query issues where `assignee = me` AND `state.type in [started, unstarted]` ordered by `updatedAt desc`
- Compare with cached state, derive transitions
- *[TBD: Linear has webhook support but requires public endpoint. Could explore Linear's GraphQL subscriptions over WebSocket - if supported for personal API keys, this eliminates polling]*

**Clockify (REST):**

- Authenticate with API key (header: `X-Api-Key`)
- Core operations: `POST /time-entries` (start timer with no end), `PATCH /time-entries/<id>` (stop with end timestamp), `GET /workspaces/<wid>/user/<uid>/time-entries`
- Workspace + user IDs resolved once during onboarding, cached per tymeline workspace

### 5.3 Why Swift native (vs Tauri / Electron)

- Primary developer (Dario) is on Mac, and a polished native menubar experience is what justifies building this rather than living with manual tracking
- Native menubar feel matters when the icon lives on screen all day
- Idle detection, Keychain, Focus modes, notifications: all native APIs, zero glue code
- Binary size ~10MB vs Tauri ~15MB / Electron ~100MB
- Sparkle update mechanism is mature on Mac, Tauri's updater on Mac is younger and less battle-tested

**v2 cross-platform path:** if community contributors want a Linux/Windows version, port to Tauri (Rust + web UI). Estimate: 1-2 weeks for feature parity. Swift business logic should translate cleanly to Rust because we keep it minimal and free of UI framework leakage. This is opportunistic, not a roadmap commitment.

---

## 6. Data model (local SQLite)

```sql
-- Each configured (Linear, Clockify) pair
CREATE TABLE workspaces (
  id TEXT PRIMARY KEY,                  -- UUID
  name TEXT NOT NULL,                   -- user-chosen, e.g. "Work"
  color TEXT NOT NULL,                  -- hex, for UI disambiguation
  linear_user_id TEXT,                  -- resolved on first /me call
  clockify_workspace_id TEXT,           -- resolved on first /workspaces call
  clockify_user_id TEXT,
  poll_interval_seconds INTEGER NOT NULL DEFAULT 30,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- One row per app-managed action (start/stop/error)
CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id),
  timestamp TEXT NOT NULL,              -- ISO 8601
  action TEXT NOT NULL,                 -- 'start' | 'stop' | 'switch' | 'cap_12h' | 'idle_stop' | 'error'
  linear_issue_id TEXT,
  linear_issue_title TEXT,
  clockify_entry_id TEXT,
  trigger TEXT NOT NULL,                -- 'linear_status_change' | 'manual' | 'idle' | 'cap' | 'lock'
  success INTEGER NOT NULL,             -- 0 or 1
  error_message TEXT
);

-- Cache of last-seen Linear issue state (for transition detection)
CREATE TABLE linear_issue_cache (
  workspace_id TEXT NOT NULL REFERENCES workspaces(id),
  issue_id TEXT NOT NULL,
  identifier TEXT NOT NULL,             -- e.g. ENG-153
  title TEXT NOT NULL,
  state_type TEXT NOT NULL,
  state_name TEXT NOT NULL,
  assignee_id TEXT,
  project_id TEXT,
  updated_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  PRIMARY KEY (workspace_id, issue_id)
);

-- Linear project -> Clockify project mapping, scoped to a workspace
CREATE TABLE project_mapping (
  workspace_id TEXT NOT NULL REFERENCES workspaces(id),
  linear_project_id TEXT NOT NULL,
  linear_project_name TEXT NOT NULL,
  clockify_project_id TEXT NOT NULL,
  default_clockify_task_id TEXT,
  PRIMARY KEY (workspace_id, linear_project_id)
);

-- App-level (global) preferences
CREATE TABLE preferences (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

**API keys are NOT in SQLite.** They go in macOS Keychain under service `app.tymeline` with accounts `linear-<workspaceUUID>` and `clockify-<workspaceUUID>`. Deleting a workspace removes the corresponding Keychain entries.

---

## 7. Security & privacy

- API keys stored only in Keychain, never written to disk in plain text or transmitted anywhere except the respective API
- No telemetry, no crash reports sent externally in v1 (could add opt-in Sentry in v2)
- Audit log stays local; user can export but app never uploads
- All HTTP traffic over TLS, Linear/Clockify both enforce this
- No background process running as root; sandboxed standard user-space app
- Code-signed and notarized with Apple Developer ID (current signing identity: Dario Ristic - may transition to a project-specific Apple Developer org if/when the project grows)
- Source code is MIT-licensed and public, so any user can audit before installing

**Trust model:** the user installing the app trusts either (a) the public source code they have audited or built themselves, or (b) the signing identity attached to the released binary. Because there is no central server, the project maintainer cannot see user API keys or time data. This is enforced architecturally, not by policy or promise.

---

## 8. Distribution & updates

- **Repo:** `github.com/darioristic/tymeline` (under personal user). May transfer to a dedicated org later if collaborators join - GitHub redirects old URLs
- **License:** MIT (in `LICENSE` at repo root)
- **Builds:** GitHub Actions on tag push, signed + notarized .dmg uploaded to Releases
- **Install (end user):** Homebrew tap `darioristic/homebrew-tap`, command:

  ```
  brew tap darioristic/tap
  brew install --cask tymeline
  ```
- **Install (from source):** clone repo, open `tymeline.xcodeproj`, build (no signing required for personal use)
- **Updates:** Sparkle checks GitHub Releases atom feed on app launch + every 24h, prompts user to install
- **Code signing:** Apple Developer Program account = Dario's personal subscription ($99/yr). Signing identity "Dario Ristic" appears in Gatekeeper dialogs. Migration to a project org Developer ID is a future option, not a v1 requirement.

---

## 9. Edge cases & open decisions

### 9.1 Multiple devices per user
A user with both a laptop and desktop runs the app on both. Both poll Linear. Both see the same status change. Both try to start a timer.

*Recommendation: Clockify's "start timer" API behavior on duplicate is to either replace the running one or accept both. Either way, last-write-wins on the server. The app should detect "another device started a timer for the same issue within 10s" via Clockify polling and not duplicate. v1 may simply tolerate the rare race and let the user clean up; if it becomes an issue, add device coordination via a tiny shared file in iCloud Drive (no central server still).*

### 9.2 Linear API rate limits
Linear allows 1500 requests/hour per API key. Polling every 30s = 120 req/hr per workspace, well under limit. Even 5 workspaces at default interval stays under 1500/hr per key (since each key has its own budget). No concern for v1.

### 9.3 Clockify project not yet mapped
User starts work on a Linear issue in a project that has no Clockify mapping. App can't auto-start a timer.

*Recommendation: notification "ENG-XXX is in project YYY (workspace 'Work') which is not mapped. Click to configure." Opens settings to the mapping section for the relevant workspace. Manual timer is still available as a fallback.*

### 9.4 Time entry written by app, then user edits in Clockify web
That's fine - app never re-syncs from Clockify, only reads to display today's summary. Edits stick.

### 9.5 Network offline

- Linear polling pauses (errors logged, retried with backoff)
- If timer was running locally and user goes offline: app keeps tracking start time locally; on reconnect, syncs to Clockify with original start time
- *Acceptable lossy mode: if app crashes while offline with timer running, that session is lost. Acceptable for v1.*

### 9.6 User rotates API key in Linear/Clockify
The cached key in Keychain becomes invalid. Next API call returns 401.

*Recommendation: on 401, notify user "Workspace 'X' Linear API key is no longer valid - click to update", open settings to that workspace. Pause poll loop for that workspace until key is fixed.*

---

## 10. Open questions (TBDs collected)

| # | Question | Decision needed by |
|---|---|---|
| 1 | Linear GraphQL subscriptions over personal API key - supported? | During implementation, can fall back to polling |
| 2 | Multi-workspace icon state: union vs highest-priority (section 4.10) | Before v1 release |
| 3 | Multi-workspace simultaneous timers: allow by default? (section 4.10) | Before v1 release |
| 4 | Long-sleep edge case: prompt "Resume?" after 16h sleep, or auto-discard after staleness window (section 4.4) | Before v1 release |
| 5 | iCloud Drive coordination for multi-device race - v1 or v2 | After we see if it's a real problem |
| 6 | Migration path from Dario's personal Apple Dev ID to a project org ID (if ever) | Not blocking, future consideration |

**Resolved in v0.2:**

- Project name: `tymeline`
- License: MIT
- Reviewers: solo (Dario)
- Apple Developer Program: Dario's personal account for v1
- Project scope: solo OSS, multi-workspace, public release
- Repo location: `github.com/darioristic/tymeline`
- Homebrew tap: `darioristic/homebrew-tap` (`brew tap darioristic/tap`)
- Idle threshold default: 10 minutes
- Lock/sleep/screensaver behavior: unified idle policy, threshold applies to all (no special-case for lock or sleep)

---

## 11. Rough milestones / effort estimate

| Milestone | Scope | Estimate (focused work) |
|---|---|---|
| **M0 - design ratified** | This doc reviewed and approved (solo: Dario reads and signs off) | 0.5 day |
| **M1 - skeleton** | Xcode project, menubar item shows, settings window stub, Keychain wiring, single-workspace API clients call `/me` successfully | 2-3 days |
| **M2 - core loop** | Polling Linear, detecting transitions, auto start/stop Clockify, manual override, basic notifications | 3-4 days |
| **M3 - multi-workspace** | Workspace CRUD, N parallel poll loops, per-workspace state, workspace UI in popover + settings | 2-3 days |
| **M4 - hardening** | Idle/lock handling, 12h cap, audit log + viewer, multi-issue rules, error handling, retry | 2-3 days |
| **M5 - onboarding + settings** | Full onboarding wizard (incl. multi-workspace flow), project mapping UI, behavior preferences | 2 days |
| **M6 - distribution** | Sparkle integration, GitHub Actions for signed+notarized builds, Homebrew tap, README + LICENSE | 2-3 days |
| **M7 - private beta** | Install on Dario's machines + 1-2 friendly testers, 1-week observation, bug fixes | 1 week elapsed (low effort, mostly waiting) |
| **M8 - v1.0 public release** | Tag v1.0, publish Release with .dmg + Sparkle appcast, finalize README, announce (Show HN / r/swift / r/MacOS - optional) | 1-2 days |

**Total focused dev time:** ~3 weeks.
**Total elapsed to v1.0 public release:** ~5-6 weeks including private beta buffer.

---

## 12. v2 considerations (out of v1 scope)

- Tauri port for Linux/Windows (triggered by community demand or contributor PR)
- iCloud Drive multi-device coordination
- Opt-in anonymous usage analytics (Plausible-style, self-hosted)
- Slack integration for daily summary post
- Pomodoro-style focus timer integration
- "Suggested entry" - ML on past patterns to propose a description when user is about to start manual timer
- JIRA / GitHub Issues as alternative task sources (the "Linear" half of the bridge becomes pluggable)
- Toggl / Harvest as alternative time trackers (the "Clockify" half becomes pluggable)

These are explicitly deferred. v1 ships Linear + Clockify + Mac only.
