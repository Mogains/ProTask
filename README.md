# Top 3

A minimal goals and to-do app built around one idea: every day, pick the **three** things that matter and get them done.

- **Two lists**: "Have to do" and "Nice to do", side by side (stacked on phones), with drag and drop.
- **Today's Top 3**: three pinned slots. Pick tasks with ☆, by dragging, or with the 1/2/3 keys. Finish all three for confetti and a streak.
- **Auto sort** per list: due date, then priority, then shortest first. Dragging switches the list to manual until you turn auto sort back on.
- **Google Calendar**: tasks with due dates and today's Top 3 appear on a dedicated "Top 3" calendar. A sidebar shows today's meetings and free time.
- Dark mode by default, light mode toggle, optimistic updates, works on mobile.

## Quick start

Requires Node.js 20 or newer.

```bash
npm install
cp .env.example .env
npx prisma db push        # creates prisma/dev.db
npm run dev               # http://localhost:3000
```

The app works fully without Google. Calendar setup is optional and described below.

> **npm 11+ note:** recent npm versions block package install scripts by default. `package.json` already allows the Prisma scripts. If `npm install` still warns, run `npm install-scripts approve prisma @prisma/client @prisma/engines` and then `npx prisma generate`.

### Using it on your phone

Run the dev server on your network and open it from your phone on the same Wi-Fi:

```bash
# find your Mac's IP: System Settings → Wi-Fi → Details, or `ipconfig getifaddr en0`
DEV_ORIGINS=192.168.1.23 npm run dev -- -H 0.0.0.0
# then open http://192.168.1.23:3000 on your phone
```

On touch screens, press and hold a task briefly to drag it. Connect Google Calendar from your computer at `http://localhost:3000`, because Google only allows plain-http redirects to `localhost`. Once connected, syncing works from any device.

For a longer-lived setup, run `npm run build && npm start` instead of the dev server.

## Environment variables

| Variable | Required | Description |
| --- | --- | --- |
| `DATABASE_URL` | yes | SQLite file, relative to `prisma/`. Default `file:./dev.db`. |
| `NEXT_PUBLIC_RESET_HOUR` | no | Local hour (0–23) when a new day starts and the Top 3 resets. Default `4`. |
| `GOOGLE_CLIENT_ID` | for calendar | OAuth client ID from Google Cloud. |
| `GOOGLE_CLIENT_SECRET` | for calendar | OAuth client secret from Google Cloud. |
| `GOOGLE_REDIRECT_URI` | for calendar | Must exactly match the URI registered in Google Cloud. Default `http://localhost:3000/api/google/callback`. |
| `DEV_ORIGINS` | no | Comma-separated hosts allowed to load the dev server, such as your Mac's LAN IP. |

Restart the dev server after changing `.env`.

## Google Calendar setup

You create your own OAuth credentials once. It takes about five minutes.

1. **Create a project.** Go to [console.cloud.google.com](https://console.cloud.google.com), open the project picker at the top, and click **New project**. Name it "Top 3" and create it.
2. **Enable the Calendar API.** Go to **APIs & Services → Library**, search for **Google Calendar API**, and click **Enable**.
3. **Configure the consent screen.** Go to **Google Auth Platform** (or **APIs & Services → OAuth consent screen**) and click **Get started**.
   - App name: `Top 3`. User support email: your email.
   - Audience: **External**.
   - Contact email: your email. Accept the policy and click **Create**.
   - Under **Audience → Test users**, click **Add users** and add the Google account whose calendar you want to use.
4. **Create the OAuth client.** Go to **Clients → Create client** (or **Credentials → Create credentials → OAuth client ID**).
   - Application type: **Web application**. Name: `Top 3 local`.
   - Authorized redirect URIs: add `http://localhost:3000/api/google/callback`.
   - Click **Create** and copy the **Client ID** and **Client secret**.
5. **Add them to `.env`:**
   ```bash
   GOOGLE_CLIENT_ID="1234-abc.apps.googleusercontent.com"
   GOOGLE_CLIENT_SECRET="GOCSPX-..."
   GOOGLE_REDIRECT_URI="http://localhost:3000/api/google/callback"
   ```
6. **Connect.** Restart `npm run dev`, open `http://localhost:3000`, and click **Connect Google Calendar** in the sidebar. Google will warn that the app isn't verified. That is expected for your own private app: click **Continue**.

The app requests the `calendar` scope so it can create the "Top 3" calendar, write events there, and read today's events from your primary calendar. It only writes to the "Top 3" calendar.

**The 7-day catch.** While the consent screen is in *Testing* mode, Google expires refresh tokens after 7 days. You'll then see a sync warning and need to click **Disconnect** and connect again. To avoid this, go to **Audience** and click **Publish app**. A personal unverified app still works; you just keep seeing the "unverified" warning when connecting.

If connecting says Google didn't return a refresh token, remove "Top 3" at [myaccount.google.com/permissions](https://myaccount.google.com/permissions) and connect again.

## How it behaves

**Top 3 and the morning reset**
- A pinned task leaves its list and returns to the same spot when unpinned.
- Starring when all three slots are full shows a friendly message instead.
- Dropping a task on an occupied slot, or pressing its number key, swaps: the old task moves to the newcomer's previous slot or back to its list.
- At the reset hour (default 4am), unfinished picks return to their lists, finished picks move to Done, and a prompt asks you to pick a new 3. The reset runs the next time the app loads or regains focus, so no background job is needed.
- The **streak** counts consecutive days on which all three picks were completed. Today counts once you finish it; until then the streak runs through yesterday.
- **Today %** is tasks completed today divided by today's workload, which is completed-today plus open tasks that are pinned or due today or earlier.

**Calendar sync (one way, app → Google)**
- A task with a due date and time becomes a timed event lasting its estimate, or 30 minutes without one.
- A task with only a due date becomes an all-day event on that date.
- A Top 3 pick with no due date becomes an all-day event today, prefixed with ⭐.
- Completing a task adds ✅ to the event title. Deleting a task deletes its event. Unpinning an undated task removes its event.
- Sync runs in the background after each change, so the UI never waits for Google. Failures show a small "⚠ calendar" tag on the task and are retried on the next change.
- The sidebar reads today's events from your **primary** calendar and lists free blocks between 8am and 8pm.

**Keyboard shortcuts**

| Key | Action |
| --- | --- |
| `N` | New task |
| `1` `2` `3` | Put the hovered or focused task into that Top 3 slot |
| `Esc` | Close the task form |
| `Space` / arrows | Pick up and move a focused task with the keyboard |

## Scripts

```bash
npm run dev        # dev server
npm run build      # production build
npm start          # run the production build
npm test           # vitest: sorting, Top 3 limit, calendar mapping, mocked sync
npm run typecheck  # tsc
npx prisma studio  # browse the database
```

Tests use their own `prisma/test.db` and never touch your data.

## Project layout

```
app/
  actions.ts              server actions (every mutation returns a fresh snapshot)
  api/google/*            OAuth connect + callback, today's events
components/
  App.tsx                 state, drag and drop, shortcuts
  TopThree.tsx, TaskList.tsx, TaskCard.tsx, TaskForm.tsx, CalendarSidebar.tsx, ...
lib/
  sort.ts                 auto sort comparator
  top3.ts                 Top 3 slot rules (the 3-task limit)
  topServer.ts            morning reset + streak log
  calendarEvent.ts        task → calendar event mapping
  google.ts               Google OAuth and Calendar sync
  freeTime.ts             free-time gaps for the sidebar
prisma/schema.prisma      database schema
tests/                    vitest tests
```

## Limitations (v1)

- Single user with no login. Don't expose it to the internet as is: anyone who can reach it can see and edit your tasks and calendar link.
- Sync is one way. Edits made in Google Calendar are not pulled back and are overwritten on the next change to that task.
- Each task has one event. A pinned task that is due on another day keeps its due-date event.
