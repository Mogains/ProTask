# ProTask progress

Updated with every commit. Newest first in each section.

## In progress

**Appearance settings and task/timeline linking** (Mac app)
- [x] 1. Appearance: mode, six styles with previews, accent picker, contrast check in the build. Committed as "Appearance: modes, styles, accents and a contrast check".
- [ ] 2 onward: not received yet. The spec was cut off after item 1, so the task/timeline linking items still need to be pasted.

**Long Term Vision, Phase 1: data and timelines** (Mac app)
- [x] 1. Data model: timelines, goals, goal log, images (downscaled, thumbnails, EXIF/location stripped). Committed `2a2efb2`.
- [x] 2. Timeline lanes view: zoom, pan, today marker, drag to move and resize, lane management, quick add. Committed as "Vision: timeline lanes view".
- [x] 3. Goal detail panel: notes, metric graph, images, links, update log. Committed as "Vision: goal detail panel".
- [ ] Phase 1 review: correctness, privacy, design system, light and dark UI pass

## Next

- **Phase 2:** graph view, vision board, task models and Insights charts, linking goals to daily work
- **Phase 3:** Routines, easier-to-click check boxes app-wide, animation and polish pass
- **Phase 4:** goal forecasting (on-device Monte Carlo projection)
- **Phase 5:** calendar provider layer, direct Google Calendar connection, two-way sync for routines and goals
- **Phase 6:** reviews, search and command palette, local export and backup, chat snapshot Vision section
- **Final pass:** build, light and dark UI pass, no SF Symbols or emojis, secrets scan, setup summary

## Done

- README: screenshots of Today, Plan your day, the Vision board with a goal open, all six appearance styles and Settings > Appearance, plus feature lines for Vision and Appearance. Rendered from demo data on a throwaway store; metadata chunks stripped from the PNGs (docs/images, 1.1 MB).
- Appearance (Settings > Appearance, a new tab beside General): Mode is System (the default), Light or Dark, and keeps the light/dark choice saved before. Style is Graphite (the original greys), Paper (warm off-white, serif or humanist face), Midnight (navy-black, dark only), Mono (pure black and white, thin lines, no accent), Sand (warm greys, clay accent) or Slate (softer cool grey, teal accent). Each card previews its style with your accent in the mode it would show in, and the mode picker only offers what the style has. Accent is one of eight muted colors for checkboxes, selection indicators, links and chart highlights (Review now marks the best day); Reset goes back to the style's own. Every style is a full token set (colors, lines, radii, face), so all views, the Vision board and goal panel, and the desktop widgets follow it. Changes cross-fade over 0.18s from a still picture of each window, so nothing flashes, and they're saved for the next launch. scripts/check-contrast.sh runs during every build and fails it if any of the 74 style, mode and accent combinations has text below 4.5:1 or hints, checkbox fills and timeline marks below 3:1. 15 new tests, 188 in total.
- Plan your day: an "Add a task" field under the Top 3 with the same parsing as quick add (dates, !!!, 30m, #tags; "~" for Nice to do, "?" for Parking Lot). New tasks show under "Added just now" so they can go straight into the Top 3 with a click or 1, 2, 3. N jumps to the field, and Esc leaves it.
- Vision goal detail panel: clicking a goal now opens a full panel beside the board, edited in place. Title (Return saves, an empty title is refused), type, timeline, status, start and target dates with "4 months left", and progress (manual, or automatic from the metric). The metric has a name, unit, start, current and target, with a small line graph of logged values and the target as a line; hover reads out a point. Notes are Markdown, shown rendered (headings, lists, checklists, quotes, code, rules) and edited as plain text. Images come in by drag and drop, Cmd-V while the panel has focus, or the file picker; one is the cover, and clicking a thumbnail opens a full-size viewer where Left and Right move between images and Esc closes. Linked goals show what this goal depends on and what it is needed for; the picker dims choices that would make a loop and says why. Linked tasks can be ticked off or unlinked from the panel. The update log is newest first, and an entry can carry the metric's value for that day, which feeds the graph. Esc closes the panel, and it closes on its own if its goal is deleted. 19 new tests, 173 in total.
- Vision timeline lanes view: a new Vision section in the sidebar (below Calendar, Option-Cmd-5) shows one lane per timeline under a shared date axis, with a today line. Zoom between decade, year, quarter and month with the header buttons, pinch, Cmd-scroll, Cmd-= and Cmd-- (or + and -); pan by dragging empty space or scrolling sideways; Today (Cmd-T) jumps back. Goals are rounded bars with a tonal progress fill, milestones are diamonds, and active goals past their date get a small terracotta dot. Drag a bar to move it, drag its edges to resize (whole days, never shorter than one day), click to open a summary beside the board, double-click empty lane space to type a new goal in place. Lane headers show the color, a collapse toggle and a short summary such as "3 active, 42%"; lanes can be renamed, recolored, reordered (menu or drag), archived (hidden behind Show archived) and deleted, and deleting a lane with goals asks where to move them first. New timeline offers Blank or six templates that only add the lane. Shift-Cmd-V opens a quick add goal sheet from any section. The keyboard covers it all: arrows move between goals, Option-arrows move the selected goal, Return opens, Delete asks, Esc closes. Only goals in view get drawn, and Reduce Motion turns zoom and pan animations into instant changes. 31 new tests for the date scale, axis ticks, culling, row packing, drag math, keyboard navigation and lane reordering, 154 in total.
- Vision data model (`2a2efb2`): five SwiftData models (timelines, goals, logs, images, dependencies) plus a goal link on tasks, added as an automatic migration (tested on an older store: all tasks kept). Images are capped at 2000px with a 480px thumbnail, and every metadata block is removed, including the one ImageIO always writes. They're stored owner-only. JSON backups carry Vision records and image file names, and older backups still import. 23 new tests, 123 in total.
- Calendar: runs on a throwaway store (tests, screenshots, demo data) never touch the real calendar
- AI chat panel (Cmd-J): provider switcher, copy tasks snapshot, paste reply with Approve and Undo, real sign-in popups
- Two-way calendar sync on web (Google) and Mac (EventKit), multiple events per task, unscheduled tasks
- Security: Keychain token storage, redacted logs, gitleaks hook and CI scan, password login on the web app, owner-only Mac data files

## Known issues

- Appearance: to pass the new contrast check, Graphite changed slightly. Secondary text is a step darker in light mode, tertiary text (section labels, counts, hints) is darker in both modes, bar titles and percentages on the Vision board use primary text, and the dark-mode progress fill on bars is lighter (0.42 instead of 0.55).
- Appearance: tertiary text is held to 3:1, not 4.5:1. At 4.5:1 it would look the same as secondary text.
- Appearance: the cross-fade was checked by a test run (a cover is made for each window and removed after the fade), not by eye. Its corners assume the 10pt window radius of macOS 14 and 15.
- Appearance: Paper's humanist face is Seravek, which comes with macOS. If it's missing, the system font is used.
- Vision: Cmd-V into the goal panel was tested by calling the paste code directly, because test runs have no key window to send the shortcut to. A quick check with a real image on the clipboard is still worth doing.
- Vision: the goal panel has no linked routines yet. They come with the Routines section in Phase 3.
- Vision: bars are stacked into rows once per zoom level, not per scroll position, so a lane can keep a row that is empty in the current view. That keeps bars from jumping between rows while you pan.
- Vision: dragging a lane to reorder it lifts it over the others and shows where it will land, but the other lanes don't slide aside while you drag.
- Vision: trackpad and scroll-wheel panning were tested by calling the board's scroll handler directly, because test runs can't send real scroll events to a window. A quick check with a real trackpad is still worth doing.
- Vision images aren't in the daily backup yet: JSON backups store file names only. Image files in backups come in Phase 6, item 17.
- Commits stay local; pushing is up to you. If you push, the GitHub login first needs the `workflow` scope: `gh auth refresh -h github.com -s workflow`.
- Google sign-in inside the AI chat panel may still be refused by Google. Email sign-in works.
- Quick add goal (Cmd-Shift-V) works inside ProTask only, not system-wide, so it doesn't break Paste and Match Style in other apps.
- Vision item 18: there is no MCP server in this project, so the MCP tools are skipped. The chat snapshot gets its Vision section.
- Calendar sync limits (see docs/web-app.md and macos/README.md): web pulls only while a tab is open, event descriptions don't sync back, single-occurrence edits of repeating events aren't read back on Mac.
