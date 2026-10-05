# ProTask

A native macOS goals and to-do app built around one idea: every day, pick your **Top 3**, the three things that matter, and get them done.

- **Today**: three Top 3 slots above your two lists, a streak counter and today's completion.
- **Have to do / Nice to do**: drag to reorder or move between lists. Auto sort orders by due date, then priority, then shortest first. Dragging switches a list to manual until you click **Auto** again.
- **Parking Lot**: type an idea, press Return. An hour later you get a notification asking where it goes.
- **Calendar**: tasks with due dates and today's Top 3 go to a "ProTask" calendar through Calendar.app, so they work with iCloud, Google, Outlook or any account you've added there. A side panel shows today's events and free time.
- SwiftUI, SwiftData, EventKit and UserNotifications. macOS 14 or later. No account, no server.
- A custom design system (`Top3/Views/Theme.swift`): flat window, Inter type, greys with one muted accent, following the system light/dark setting.

## Features at a glance

| Area | What it does |
| --- | --- |
| Quick add anywhere | Option-Space (change it in Settings) opens a floating field from any app. `~` sends to Nice to do, `?` to the Parking Lot. |
| Natural language | "email prof friday 3pm !!! 30m #work" sets the due date and time, priority (`!` low, `!!` medium, `!!!` high), estimate and tags. A muted preview shows what was understood; Backspace right after the date removes a wrong guess. |
| Recurring tasks | Daily, weekdays, weekly, monthly, or every N days or weeks on chosen weekdays. Completing one creates the next; the calendar shows it as a repeating event. |
| Command palette | Command-K: fuzzy search across tasks, ideas, sections and actions. |
| Morning planning | The first open of each day shows a planning screen with rolled-over picks, overdue and due-today tasks, and today's calendar. Pick with 1/2/3, Return to start, Esc to skip. |
| Evening wrap-up | An optional notification (6 PM by default) opens what you finished, what rolls over, a brain-dump field into the Parking Lot, and Close the day. |
| Focus timer | 25, 50 or custom minutes from a task's menu, the palette, or Shift-Command-F. Shows in the sidebar footer, notifies at the end, logs actual time against the estimate. |
| Waiting On | Handed-off items with who and a follow-up date. The follow-up notifies, appears on Today, and offers Received, Snooze 1 day, Move to Have to do. |
| Tags | `#tag` in a title or Tags… in the row menu. The sidebar's Tags section filters the current view. |
| Menu bar | Shows Top 3 progress like "2/3"; the dropdown checks items off and quick-adds. |
| Weekly review | Completed this week vs last, completion rate, streak, focus time, actual vs estimated, full Top 3 days, and one sparkline. |
| Desktop widget | Small and medium widgets with today's Top 3. |
| Export and backup | File menu: JSON backup, Markdown export, import from JSON. A daily backup keeps the newest seven. |

The left sidebar can be hidden with Control-Command-S or the header button.

## Install from the .dmg

1. Open `dist/ProTask.dmg` (build it first, see below).
2. Drag **ProTask** onto the **Applications** shortcut.
3. Eject the disk image and open ProTask from Applications.

### If macOS blocks it

The app is not signed with an Apple Developer ID, so the first launch is blocked.

- **macOS 15 (Sequoia) and later:** open ProTask once and click **Done** on the warning. Then go to **System Settings → Privacy & Security**, scroll to the message about "ProTask", click **Open Anyway**, and confirm with your password. Open the app again and click **Open**.
- **macOS 14 (Sonoma):** right-click ProTask in Applications, choose **Open**, then click **Open** in the dialog.

If macOS says the app "is damaged and can't be opened", the download quarantine flag is the cause. Clear it with:

```bash
xattr -dr com.apple.quarantine "/Applications/ProTask.app"
```

You only need to do this once per version.

### Permissions on first launch

ProTask asks for two permissions:

- **Notifications**: needed for the one-hour Parking Lot reminders. Change it in **System Settings → Notifications → ProTask**.
- **Calendars (full access)**: needed to create the "ProTask" calendar and to read today's events. Change it in **System Settings → Privacy & Security → Calendars**.

Both can also be checked from **ProTask → Settings** (Command-comma).

## Build from source

Requirements: Xcode 15 or later (built and tested with Xcode 16.3 on macOS 15). No other setup is needed. If you've never opened Xcode, run this once to accept the license and install its components:

```bash
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
```

Then, from this `macos/` folder:

```bash
# Debug build
xcodebuild -project Top3.xcodeproj -scheme Top3 -derivedDataPath build build
open "build/Build/Products/Debug/ProTask.app"

# Unit tests: sorting, Top 3 limit, rollover, natural language parser, recurrence, fuzzy search,
# weekly stats, backups, day keys, free time, calendar mapping
xcodebuild -project Top3.xcodeproj -scheme Top3 -derivedDataPath build test

# Release build packaged as dist/ProTask.dmg
./scripts/package.sh
```

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated project is committed, so you only need XcodeGen (`brew install xcodegen`, then `xcodegen generate`) if you change `project.yml` or add files. `package.sh` regenerates it automatically when XcodeGen is installed.

To redraw the app icon: `swift scripts/make-icon.swift Top3/Resources/Assets.xcassets/AppIcon.appiconset`.

### Icons

ProTask uses its own icon set, not SF Symbols. Each icon is a hand-written 16×16 SVG (1.25 stroke, square caps, no fills except tiny dots) stored as a template image in `Top3/Resources/Assets.xcassets/Icons`, so it tints with the theme. Views draw them with `Icon(.name)` from `Top3/Views/Icon.swift`.

- Edit or add icons in `scripts/make-icons.py`, then run `python3 scripts/make-icons.py`.
- `scripts/check-icons.sh` fails if any `systemName`, `systemImage` or `Label(` appears in the code. `package.sh` runs it before every release build.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Option-Space (anywhere) | Quick add (configurable) |
| Command-K | Command palette |
| Command-N | New task |
| Shift-Command-P | Quick add to Parking Lot |
| Command-1 / 2 / 3 | Put the selected task in Top 3 slot 1, 2 or 3 |
| Command-E | Edit the selected task |
| Shift-Command-F | Start or stop the focus timer on the selected task |
| Control-Command-S | Hide or show the sidebar |
| Command-Return | Mark the selected task done or not done |
| Option-Command-0 | Go to Today |
| Option-Command-1 / 2 / 3 / 4 | Go to Have to do, Nice to do, Waiting On, Parking Lot |
| Command-comma | Settings |

Click a task to select it. Double-click to edit. Right-click for every action.

## How it behaves

**Top 3**
- Add a task with its star, by dragging it onto a slot, by dragging it onto **Today** in the sidebar, or with Command-1/2/3.
- Starring when all three slots are full shows a message instead. Dropping onto a filled slot swaps the two tasks or sends the old one back to its list.
- A pinned task leaves its list and returns to the same spot when unpinned.
- At the start of each day (4 AM by default, configurable in Settings), unfinished picks go back to their lists, finished ones move to Done, and the Today screen asks you to pick a new 3.
- Finishing all three plays a short animation and a sound. The streak counts consecutive days with all three done.

**Parking Lot**
- Each idea is timestamped and schedules its own notification for one hour later. macOS delivers it even if ProTask is closed.
- The notification's options are **Send to Have to do**, **Send to Nice to do**, **Keep in Parking Lot** (reminds again in an hour) and **Delete**. The same actions are on each idea's row and context menu. You can also drag an idea onto a list in the sidebar or on the Today screen.
- The menu bar icon (a checklist) lets you park an idea without opening the window. Turn it off in Settings.

**Calendar (one way, app to calendar)**
- Due date and time: a timed event lasting the estimate, or 30 minutes.
- Due date only: an all-day event.
- Today's Top 3 pick without a due date: an all-day event today.
- Completing a task adds a "✓" to the event title. Deleting a task removes its event. Edits made in Calendar.app are not read back.
- The "ProTask" calendar is created in your default calendar account. Some accounts, including Google, don't let apps create calendars. In that case ProTask falls back to iCloud or "On My Mac". You can also create a calendar named "ProTask" yourself in Calendar.app, and the app will use it.
- If you used the app when it was called Top 3, its "Top 3" calendar is renamed to "ProTask" in place, so existing events carry over.
- The side panel lists today's events from every calendar except "ProTask", plus free blocks between 8 AM and 8 PM.

## Widget note

The widget is a WidgetKit extension inside ProTask.app. It reads a small snapshot file the app writes to `~/Library/Application Support/ProTask/widget.json`, so it needs no app group or Developer account. Because the app is ad-hoc signed, macOS may not list the widget in the widget gallery on every system. If it is missing after opening ProTask once, signing the app with a free Apple ID team in Xcode makes it appear.

## Data

Automatic backups go to `~/Library/Application Support/ProTask/Backups` (or the folder chosen in Settings), one per day, newest seven kept. Schema changes are additive, so SwiftData migrates existing data automatically.

Tasks are stored with SwiftData in `~/Library/Application Support/ProTask/Top3.store`. Data from the old `Top 3` folder is moved there automatically. Delete that folder to start over.

The bundle identifier (`com.anmolbhatt.top3`) is unchanged from the app's earlier name so existing permissions carry over. The bundled Inter font is licensed under the SIL Open Font License (`Top3/Resources/Fonts/Inter-LICENSE.txt`).

## Project layout

```
macos/
  project.yml                 XcodeGen spec (source of Top3.xcodeproj)
  Top3/
    App/                      @main app, menu commands, app delegate
    Model/Models.swift        SwiftData models
    Logic/                    pure logic, also compiled into the tests
    Services/                 AppModel (all changes), EventKit and notification services
    Views/                    SwiftUI views; Theme.swift holds every design token, Components.swift the custom controls
    Resources/                app icon, custom icon set, accent color, Inter font
  Top3Tests/                  XCTest unit tests
  scripts/                    package.sh (.dmg), make-icon.swift (app icon), make-icons.py (icon set), check-icons.sh
```
