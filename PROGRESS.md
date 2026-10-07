# ProTask progress

Updated with every commit. Newest first in each section.

## In progress

**Long Term Vision, Phase 1: data and timelines** (Mac app)
- [x] 1. Data model: timelines, goals, goal log, images (downscaled, thumbnails, EXIF/location stripped). Committed `2a2efb2`.
- [x] 2. Timeline lanes view: zoom, pan, today marker, drag to move and resize, lane management, quick add. Committed as "Vision: timeline lanes view".
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

- Vision timeline lanes view: a new Vision section in the sidebar (below Calendar, Option-Cmd-5) shows one lane per timeline under a shared date axis, with a today line. Zoom between decade, year, quarter and month with the header buttons, pinch, Cmd-scroll, Cmd-= and Cmd-- (or + and -); pan by dragging empty space or scrolling sideways; Today (Cmd-T) jumps back. Goals are rounded bars with a tonal progress fill, milestones are diamonds, and active goals past their date get a small terracotta dot. Drag a bar to move it, drag its edges to resize (whole days, never shorter than one day), click to open a summary beside the board, double-click empty lane space to type a new goal in place. Lane headers show the color, a collapse toggle and a short summary such as "3 active, 42%"; lanes can be renamed, recolored, reordered (menu or drag), archived (hidden behind Show archived) and deleted, and deleting a lane with goals asks where to move them first. New timeline offers Blank or six templates that only add the lane. Shift-Cmd-V opens a quick add goal sheet from any section. The keyboard covers it all: arrows move between goals, Option-arrows move the selected goal, Return opens, Delete asks, Esc closes. Only goals in view get drawn, and Reduce Motion turns zoom and pan animations into instant changes. 31 new tests for the date scale, axis ticks, culling, row packing, drag math, keyboard navigation and lane reordering, 154 in total.
- Vision data model (`2a2efb2`): five SwiftData models (timelines, goals, logs, images, dependencies) plus a goal link on tasks, added as an automatic migration (tested on an older store: all tasks kept). Images are capped at 2000px with a 480px thumbnail, and every metadata block is removed, including the one ImageIO always writes. They're stored owner-only. JSON backups carry Vision records and image file names, and older backups still import. 23 new tests, 123 in total.
- Calendar: runs on a throwaway store (tests, screenshots, demo data) never touch the real calendar
- AI chat panel (Cmd-J): provider switcher, copy tasks snapshot, paste reply with Approve and Undo, real sign-in popups
- Two-way calendar sync on web (Google) and Mac (EventKit), multiple events per task, unscheduled tasks
- Security: Keychain token storage, redacted logs, gitleaks hook and CI scan, password login on the web app, owner-only Mac data files

## Known issues

- Vision: clicking a goal opens a short summary beside the board for now. The full goal detail panel is item 3.
- Vision: bars are stacked into rows once per zoom level, not per scroll position, so a lane can keep a row that is empty in the current view. That keeps bars from jumping between rows while you pan.
- Vision: dragging a lane to reorder it lifts it over the others and shows where it will land, but the other lanes don't slide aside while you drag.
- Vision: trackpad and scroll-wheel panning were tested by calling the board's scroll handler directly, because test runs can't send real scroll events to a window. A quick check with a real trackpad is still worth doing.
- Vision images aren't in the daily backup yet: JSON backups store file names only. Image files in backups come in Phase 6, item 17.
- Commits stay local; pushing is up to you. If you push, the GitHub login first needs the `workflow` scope: `gh auth refresh -h github.com -s workflow`.
- Google sign-in inside the AI chat panel may still be refused by Google. Email sign-in works.
- Quick add goal (Cmd-Shift-V) works inside ProTask only, not system-wide, so it doesn't break Paste and Match Style in other apps.
- Vision item 18: there is no MCP server in this project, so the MCP tools are skipped. The chat snapshot gets its Vision section.
- Calendar sync limits (see docs/web-app.md and macos/README.md): web pulls only while a tab is open, event descriptions don't sync back, single-occurrence edits of repeating events aren't read back on Mac.
