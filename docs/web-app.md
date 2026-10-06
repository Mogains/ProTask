# Top 3

> This is the earlier Next.js web version. Its code lives at the top level of the repo (`app/`, `components/`, `lib/`, `prisma/`); run the commands below from there. For the Mac app, see the [main README](../README.md).

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

ProTask only listens on `127.0.0.1`, and it accepts requests from other devices only over HTTPS. The easiest way to reach it from your phone is an HTTPS proxy on the same Mac, so the app itself never listens on the network. For example, with [Tailscale](https://tailscale.com):

```bash
tailscale serve --bg 3000          # https://<your-mac>.<tailnet>.ts.net, only reachable inside your tailnet
```

Then add to `.env`, and restart:

```bash
PUBLIC_HOSTS=<your-mac>.<tailnet>.ts.net
TRUST_PROXY=1                       # the proxy tells ProTask the request came in over HTTPS
```

Any other TLS reverse proxy (Caddy, nginx) works the same way. On touch screens, press and hold a task briefly to drag it. Connect Google Calendar from your computer at `http://localhost:3000`, because Google only allows plain-http redirects to `localhost`.

For a longer-lived setup, run `npm run build && npm start` instead of the dev server.

## Environment variables

| Variable | Required | Description |
| --- | --- | --- |
| `DATABASE_URL` | yes | SQLite file, relative to `prisma/`. Default `file:./dev.db`. |
| `NEXT_PUBLIC_RESET_HOUR` | no | Local hour (0–23) when a new day starts and the Top 3 resets. Default `4`. |
| `GOOGLE_CLIENT_ID` | for calendar | OAuth client ID from Google Cloud. |
| `GOOGLE_CLIENT_SECRET` | for calendar | OAuth client secret from Google Cloud. |
| `GOOGLE_REDIRECT_URI` | for calendar | Must exactly match the URI registered in Google Cloud. Default `http://localhost:3000/api/google/callback`. |
| `TOKEN_STORE` | no | `keychain` (default on macOS) or `encrypted`. Where Google tokens are kept. |
| `TOKEN_ENCRYPTION_KEY` | with `encrypted` | 32 random bytes, base64 (`openssl rand -base64 32`). |
| `HOST` / `PORT` | no | Listen address. Default `127.0.0.1:3000`. Anything but loopback is refused until a password is set. |
| `PUBLIC_HOSTS` | no | Comma-separated hostnames other than localhost that ProTask answers to. Requests for any other `Host` are rejected. |
| `TRUST_PROXY` | no | `1` when behind your own TLS proxy, so `X-Forwarded-Proto` is trusted. |
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

**Calendar sync (two way, with the "Top 3" calendar only)**
- A task with a due date and time becomes a timed event lasting its estimate, or 30 minutes without one.
- A task with only a due date becomes an all-day event on that date.
- A Top 3 pick that is due on another day (or has no due date) also gets an all-day ⭐ event today. Unpinning removes only that event.
- Completing a task adds ✅ to its event titles. Deleting a task deletes all of its events.
- Changes go to Google in the background after each edit, so the UI never waits. Failures show a small "⚠ calendar" tag on the task and are retried on the next change.
- **Edits in Google Calendar come back.** Change an event's title, date, time or length and the task follows. The app checks every minute while it's open, and again when you return to the tab. It uses Google's incremental sync tokens, and if a token expires it does one full resync.
- **Deleting an event keeps the task.** It's marked "off calendar" and listed on Today under *Removed from your calendar*. **Put back**, a new due date, or pinning it puts it back on the calendar.
- **Conflicts.** If a task and its event were both changed since the last sync, the newer edit wins. The other version goes into a sync history, and the latest five changes are under *Recent sync changes* in the sidebar. Pushes use the event's etag, so an edit made in Google is never overwritten blindly.
- Moving a ⭐ Top 3 event to another day moves it back, because it follows the Top 3 day. Its title change is kept.
- If Google revokes access, sync pauses and the sidebar shows **Reconnect**.
- Only the dedicated "Top 3" calendar is read or written. Your other calendars are only read for the sidebar's list of today's events.
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
npm test           # vitest: sorting, Top 3 limit, auth, calendar mapping, two-way sync against a fake Google
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

## Security

- **Password.** The first time you open the app you set an owner password, stored as an argon2id hash. Only a request from the same computer can set it. Every page, API route and server action needs a login session.
- **Login limits.** After 5 wrong passwords, logins lock for 30 seconds, doubling with each further miss up to 1 hour. The lock is stored in the database, so restarting doesn't reset it. Anyone who can reach the login page can also trigger the lock.
- **Sessions.** A random 256-bit token in an `httpOnly`, `SameSite=Lax` cookie, which is `Secure` and `__Host-` prefixed over HTTPS. Sessions last 14 days, and only a SHA-256 of the token is stored. **Log out** ends the session on the server.
- **CSRF.** Any request that changes something must come from the app's own origin. Server actions also check the session themselves.
- **Network.**
  - It binds to `127.0.0.1` by default, and requests for unknown `Host` names are rejected, which blocks DNS rebinding.
  - Any host other than localhost needs HTTPS. `npm run dev`/`start` refuse to listen on a non-loopback address until a password exists and `PUBLIC_HOSTS` is set.
- **Headers.** A nonce-based Content Security Policy, plus `frame-ancestors 'none'`, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy: no-referrer` and HSTS over HTTPS.
- **Data at rest.**
  - Google tokens are in your Keychain. The SQLite file holds your tasks and is `chmod 600`.
  - Anyone with your macOS account can still read the SQLite file and the Keychain item, so this protects against other people on the network, not other software running as you.
- **No share links.** The app has no calendar feed or share URL. Calendar access goes through Google's API with your own OAuth client.
- **Not built for the open internet.** It hasn't had a security audit and is meant for one person. If you expose it beyond your own devices, put it behind a VPN like Tailscale.

## Limitations

What is solved now: two-way sync, multiple events per task (due date and Top 3 day), password login, and tokens kept in the Keychain. Still not solved:

- Calendar edits are only pulled while the app is open in a browser. Instant updates would need Google push notifications, which require a public HTTPS address.
- Only the title, date, time and length come back from Google. Edits to an event's description are overwritten by the task's notes.
- Deleting one of a task's events takes the whole task off the calendar, including its other event, until you put it back.
- The sync history keeps the newest 200 changes and shows five. There's no one-click restore: copy the old version back by hand.
- Conflict order depends on your computer's clock agreeing with Google's.
- One user. There are no shared lists or accounts.
