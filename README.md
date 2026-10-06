# ProTask

**Pick three things. Get them done.**

ProTask is a native macOS to-do app built around a daily **Top 3**: each day you pick the three tasks that matter most, and everything else waits its turn. No account, no server; your data stays on your Mac.

Requires macOS 14 (Sonoma) or later.

---

## What it does

- **Top 3 for today.** Three slots at the top of the day. Unfinished picks roll back to their list overnight, and a streak counts days where you finished all three.
- **Two lists.** *Have to do* and *Nice to do*, sorted by due date and priority, or dragged into your own order.
- **Parking Lot.** Jot down an idea and keep working. An hour later a notification asks where it belongs.
- **Quick add from anywhere.** Press <kbd>⌥</kbd> <kbd>Space</kbd> and type something like `email prof friday 3pm !!! 30m #school`. ProTask picks up the date, priority, time estimate and tag.
- **Two-way calendar sync.** Tasks with due dates and your Top 3 appear in a "ProTask" calendar, wherever Calendar.app shows it: iCloud, Google, Outlook. Move or rename an event there and the task follows. Delete one and the task stays, flagged on Today.
- **Daily rhythm.** A morning planning screen, an evening wrap-up and a weekly review.
- **Focus timer.** 25 or 50 minutes, or your own length, on any task.
- **Waiting On.** Track things you've handed off and get a nudge to follow up.
- **Menu bar and widget.** See "2/3" progress in the menu bar. Desktop widgets show your Top 3 and Parking Lot.
- **Backups.** Automatic daily backups, plus JSON and Markdown export.

## Install

1. Build the installer (see [Build from source](#build-from-source)), then open `macos/dist/ProTask.dmg`.
2. Drag **ProTask** into **Applications**.
3. Open it. The first launch is blocked because the app isn't signed with a paid Apple Developer ID. To allow it:
   - **macOS 15 and later:** go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
   - **macOS 14:** right-click the app, choose **Open**, then click **Open**.

ProTask asks for **Notifications**, used for Parking Lot reminders, and **Calendars**, used for calendar sync. You can say no to either one, and the rest of the app keeps working.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| <kbd>⌥</kbd> <kbd>Space</kbd> | Quick add, from any app |
| <kbd>⌘</kbd> <kbd>K</kbd> | Command palette |
| <kbd>⌘</kbd> <kbd>N</kbd> | New task |
| <kbd>⌘</kbd> <kbd>1</kbd> / <kbd>2</kbd> / <kbd>3</kbd> | Put the selected task in Top 3 slot 1, 2 or 3 |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>P</kbd> | Park an idea |
| <kbd>⇧</kbd> <kbd>⌘</kbd> <kbd>F</kbd> | Start or stop focus |
| <kbd>⌘</kbd> <kbd>Return</kbd> | Mark done |

The full list is in the [Mac app guide](macos/README.md#keyboard-shortcuts).

## Build from source

You need Xcode 15 or later. Run these from the `macos/` folder:

```bash
cd macos
xcodebuild -project Top3.xcodeproj -scheme Top3 -derivedDataPath build build   # build
xcodebuild -project Top3.xcodeproj -scheme Top3 -derivedDataPath build test    # run the tests
./scripts/package.sh                                                           # make dist/ProTask.dmg
```

## Secrets and setup

This repo is public, so nothing secret is committed, and the Mac app needs no credentials at all: it talks to Calendar.app through EventKit.

The web version needs your own Google OAuth client to sync with Google Calendar:

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project and enable the **Google Calendar API**.
2. Set up the OAuth consent screen (External, Testing) and add yourself as a test user.
3. Create an **OAuth client ID** of type *Web application*, with the redirect URI `http://localhost:3000/api/google/callback`.
4. Copy `.env.example` to `.env` and paste in the client ID and secret. `.env` is gitignored.

When you connect, Google's access and refresh tokens are stored in your **macOS Keychain** (item "ProTask Web: Google Calendar"), never in the database or a file. On other systems, set `TOKEN_STORE=encrypted` and a `TOKEN_ENCRYPTION_KEY` (`openssl rand -base64 32`), and they are stored encrypted with AES-256-GCM.

To keep secrets out of git:

- `npm install` turns on a pre-commit hook that runs [gitleaks](https://github.com/gitleaks/gitleaks) on staged changes (`brew install gitleaks`).
- A GitHub Actions workflow scans the full history on every push.
- Logs show only error codes. Tokens, URLs, emails and task titles are stripped out.

If a secret ever lands in a commit, rotate it first, then scrub it from history. Deleting it in a new commit is not enough.

## Learn more

- [Mac app guide](macos/README.md): every feature, how calendar sync works, where your data lives, and the project layout.
- [Web version](docs/web-app.md): the earlier Next.js prototype. Its code is at the top level of this repo.
