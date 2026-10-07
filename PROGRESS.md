# ProTask progress

Updated with every commit. Newest first in each section.

## In progress

**Long Term Vision, Phase 1: data and timelines** (Mac app)
- [ ] 1. Data model: timelines, goals, goal log, images (downscaled, thumbnails, EXIF/location stripped)
- [ ] 2. Timeline lanes view: zoom, pan, today marker, drag to move and resize, lane management, quick add
- [ ] 3. Goal detail panel: notes, metric graph, images, links, update log
- [ ] Phase 1 review: correctness, privacy, design system, light and dark UI pass

## Next

- **Phase 2:** graph view, vision board, task models and Insights charts, linking goals to daily work
- **Phase 3:** Routines, easier-to-click check boxes app-wide, animation and polish pass
- **Phase 4:** goal forecasting (on-device Monte Carlo projection)
- **Phase 5:** calendar provider layer, direct Google Calendar connection, two-way sync for routines and goals
- **Phase 6:** reviews, search and command palette, local export and backup, chat snapshot Vision section
- **Final pass:** build, light and dark UI pass, no SF Symbols or emojis, secrets scan, setup summary

## Done

- Calendar: runs on a throwaway store (tests, screenshots, demo data) never touch the real calendar
- AI chat panel (Cmd-J): provider switcher, copy tasks snapshot, paste reply with Approve and Undo, real sign-in popups
- Two-way calendar sync on web (Google) and Mac (EventKit), multiple events per task, unscheduled tasks
- Security: Keychain token storage, redacted logs, gitleaks hook and CI scan, password login on the web app, owner-only Mac data files

## Known issues

- Not pushed: the GitHub login lacks the `workflow` scope. Run `gh auth refresh -h github.com -s workflow`, then `git push`.
- Google sign-in inside the AI chat panel may still be refused by Google. Email sign-in works.
- Quick add goal (Cmd-Shift-V) works inside ProTask only, not system-wide, so it doesn't break Paste and Match Style in other apps.
- Vision item 18: there is no MCP server in this project, so the MCP tools are skipped. The chat snapshot gets its Vision section.
- Calendar sync limits (see docs/web-app.md and macos/README.md): web pulls only while a tab is open, event descriptions don't sync back, single-occurrence edits of repeating events aren't read back on Mac.
