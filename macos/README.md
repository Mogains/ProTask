# Top 3 for Mac

A native macOS goals and to-do app built around one idea: every day, pick the **three** things that matter and get them done.

- **Today**: three Top 3 slots above your two lists, a streak counter and today's completion.
- **Have to do / Nice to do**: drag to reorder or move between lists. Auto sort orders by due date, then priority, then shortest first. Dragging switches a list to manual until you click **Auto** again.
- **Parking Lot**: type an idea, press Return. An hour later you get a notification asking where it goes.
- **Calendar**: tasks with due dates and today's Top 3 go to a "Top 3" calendar through Calendar.app, so they work with iCloud, Google, Outlook or any account you've added there. A side panel shows today's events and free time.
- SwiftUI, SwiftData, EventKit and UserNotifications. macOS 14 or later. No account, no server.

## Install from the .dmg

1. Open `dist/Top3.dmg` (build it first, see below).
2. Drag **Top 3** onto the **Applications** shortcut.
3. Eject the disk image and open Top 3 from Applications.

### If macOS blocks it

The app is not signed with an Apple Developer ID, so the first launch is blocked.

- **macOS 15 (Sequoia) and later:** open Top 3 once and click **Done** on the warning. Then go to **System Settings → Privacy & Security**, scroll to the message about "Top 3", click **Open Anyway**, and confirm with your password. Open the app again and click **Open**.
- **macOS 14 (Sonoma):** right-click Top 3 in Applications, choose **Open**, then click **Open** in the dialog.

If macOS says the app "is damaged and can't be opened", the download quarantine flag is the cause. Clear it with:

```bash
xattr -dr com.apple.quarantine "/Applications/Top 3.app"
```

You only need to do this once per version.

### Permissions on first launch

Top 3 asks for two permissions:

- **Notifications**: needed for the one-hour Parking Lot reminders. Change it in **System Settings → Notifications → Top 3**.
- **Calendars (full access)**: needed to create the "Top 3" calendar and to read today's events. Change it in **System Settings → Privacy & Security → Calendars**.

Both can also be checked from **Top 3 → Settings** (Command-comma).

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
open "build/Build/Products/Debug/Top 3.app"

# Unit tests (sorting, Top 3 limit, day rollover and streak, free time, calendar mapping)
xcodebuild -project Top3.xcodeproj -scheme Top3 -derivedDataPath build test

# Release build packaged as dist/Top3.dmg
./scripts/package.sh
```

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated project is committed, so you only need XcodeGen (`brew install xcodegen`, then `xcodegen generate`) if you change `project.yml` or add files. `package.sh` regenerates it automatically when XcodeGen is installed.

To redraw the app icon: `swift scripts/make-icon.swift Top3/Resources/Assets.xcassets/AppIcon.appiconset`.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Command-N | New task |
| Shift-Command-P | Quick add to Parking Lot |
| Command-1 / 2 / 3 | Put the selected task in Top 3 slot 1, 2 or 3 |
| Command-E | Edit the selected task |
| Command-Return | Mark the selected task done or not done |
| Option-Command-0 | Go to Today |
| Option-Command-1 / 2 / 3 | Go to Have to do, Nice to do, Parking Lot |
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
- Each idea is timestamped and schedules its own notification for one hour later. macOS delivers it even if Top 3 is closed.
- The notification's options are **Send to Have to do**, **Send to Nice to do**, **Keep in Parking Lot** (reminds again in an hour) and **Delete**. The same actions are on each idea's row and context menu. You can also drag an idea onto a list in the sidebar or on the Today screen.
- The menu bar icon (a checklist) lets you park an idea without opening the window. Turn it off in Settings.

**Calendar (one way, app to calendar)**
- Due date and time: a timed event lasting the estimate, or 30 minutes.
- Due date only: an all-day event.
- Today's Top 3 pick without a due date: an all-day event today.
- Completing a task adds a "✓" to the event title. Deleting a task removes its event. Edits made in Calendar.app are not read back.
- The "Top 3" calendar is created in your default calendar account. Some accounts, including Google, don't let apps create calendars. In that case Top 3 falls back to iCloud or "On My Mac". You can also create a calendar named "Top 3" yourself in Calendar.app, and the app will use it.
- The side panel lists today's events from every calendar except "Top 3", plus free blocks between 8 AM and 8 PM.

## Data

Tasks are stored with SwiftData in `~/Library/Application Support/Top 3/Top3.store`. Delete that folder to start over.

## Project layout

```
macos/
  project.yml                 XcodeGen spec (source of Top3.xcodeproj)
  Top3/
    App/                      @main app, menu commands, app delegate
    Model/Models.swift        SwiftData models
    Logic/                    pure logic, also compiled into the tests
    Services/                 AppModel (all changes), EventKit and notification services
    Views/                    SwiftUI views
    Resources/Assets.xcassets icon and the muted accent color
  Top3Tests/                  XCTest unit tests
  scripts/                    package.sh (.dmg), make-icon.swift
```
