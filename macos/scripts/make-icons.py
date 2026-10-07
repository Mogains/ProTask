#!/usr/bin/env python3
"""Writes the ProTask icon set: hand-written 16x16 SVGs, 1.25 stroke, no fills
(except tiny dots), square caps, 1px corner radius at most. Each becomes a
template image set in Assets.xcassets/Icons so it tints with the theme."""
import json, os, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "Top3/Resources/Assets.xcassets/Icons"
S = 'stroke="#000" stroke-width="1.25" stroke-linecap="square" stroke-linejoin="miter" fill="none"'

def line(x1, y1, x2, y2): return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" {S}/>'
def rect(x, y, w, h, r=1): return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" {S}/>'
def poly(*pts): return f'<polyline points="{" ".join(f"{x},{y}" for x, y in pts)}" {S}/>'
def circle(cx, cy, r): return f'<circle cx="{cx}" cy="{cy}" r="{r}" {S}/>'
def path(d): return f'<path d="{d}" {S}/>'
def dot(x, y, s=1.5): return f'<rect x="{x}" y="{y}" width="{s}" height="{s}" fill="#000"/>'
BOX = rect(2.5, 2.5, 11, 11)

ICONS = {
    # Sidebar set (used if the sidebar shows icons; Today doubles as the Top 3 star)
    "today":      BOX + dot(9.5, 4, 2.5),
    "have-to":    BOX + line(5.5, 8, 10.5, 8),
    "nice-to":    circle(8, 8, 5.5) + line(5.5, 8, 10.5, 8),
    "parking":    rect(2.5, 2.5, 11, 11, 1) + line(8, 5.5, 8, 10.5),
    "calendar":   rect(2.5, 3.5, 11, 10) + line(2.5, 6.5, 13.5, 6.5) + line(5.5, 2, 5.5, 4) + line(10.5, 2, 10.5, 4),
    "done":       BOX + poly((5.5, 8), (7.25, 9.75), (10.5, 6.5)),
    "settings":   line(2.5, 5.5, 13.5, 5.5) + line(2.5, 10.5, 13.5, 10.5) + line(10, 3.5, 10, 7.5) + line(6, 8.5, 6, 12.5),
    # Toolbar and actions
    "add":        line(8, 3, 8, 13) + line(3, 8, 13, 8),
    "auto-sort":  line(2.5, 5, 8.5, 5) + line(2.5, 10, 6, 10) + line(12, 3.5, 12, 12) + poly((10, 10.5), (12, 12.5), (14, 10.5)),
    "manual":     dot(5, 3.25) + dot(9.5, 3.25) + dot(5, 7.25) + dot(9.5, 7.25) + dot(5, 11.25) + dot(9.5, 11.25),
    "panel":      BOX + line(10, 2.5, 10, 13.5),
    "quick-add":  BOX + line(8, 5.5, 8, 10.5) + line(5.5, 8, 10.5, 8),
    "more":       dot(2.75, 7.25) + dot(7.25, 7.25) + dot(11.75, 7.25),
    "delete":     line(2.5, 4.5, 13.5, 4.5) + line(6.5, 2.5, 9.5, 2.5) + poly((4.5, 4.5), (5.25, 13.5), (10.75, 13.5), (11.5, 4.5)),
    "send":       line(2.5, 8, 9.5, 8) + poly((6.5, 5), (9.5, 8), (6.5, 11)) + poly((11, 2.5), (13.5, 2.5), (13.5, 13.5), (11, 13.5)),
    "later":      BOX + poly((8, 5), (8, 8.5), (10.5, 8.5)),
    "close":      line(4, 4, 12, 12) + line(12, 4, 4, 12),
    # Task row
    "drag":       dot(5, 3.25) + dot(9.5, 3.25) + dot(5, 7.25) + dot(9.5, 7.25) + dot(5, 11.25) + dot(9.5, 11.25),
    "due":        rect(3.5, 3.5, 9, 9) + line(3.5, 6.5, 12.5, 6.5),
    "priority-1": line(5, 6, 5, 11),
    "priority-2": line(5, 6, 5, 11) + line(8, 6, 8, 11),
    "priority-3": line(5, 6, 5, 11) + line(8, 6, 8, 11) + line(11, 6, 11, 11),
    "notes":      line(3, 4.5, 13, 4.5) + line(3, 8, 13, 8) + line(3, 11.5, 9, 11.5),
    "idea":       rect(2.5, 2.5, 11, 11, 1) + line(8, 5.5, 8, 10.5),
    "sidebar":    BOX + line(6, 2.5, 6, 13.5),
    "search":     rect(2.5, 2.5, 8, 8, 1) + line(10.5, 10.5, 13.5, 13.5),
    "waiting":    BOX + line(5.5, 6, 10.5, 6) + line(5.5, 10, 10.5, 10) + poly((7, 6), (8, 8), (9, 6)),
    "repeat":     poly((3, 7.5), (3, 4.5), (12.5, 4.5)) + poly((10.5, 2.5), (12.5, 4.5), (10.5, 6.5))
                  + poly((13, 8.5), (13, 11.5), (3.5, 11.5)) + poly((5.5, 9.5), (3.5, 11.5), (5.5, 13.5)),
    # AI chat panel
    "chat":       rect(2.5, 3, 11, 8) + poly((5.5, 11), (5.5, 13.5), (8.5, 11)),
    "copy":       rect(5.5, 5.5, 8, 8) + poly((10.5, 3.5), (10.5, 2.5), (2.5, 2.5), (2.5, 10.5), (3.5, 10.5)),
    "paste":      rect(3, 3.5, 10, 10) + rect(6, 2, 4, 3, 0.5) + line(5.5, 8, 10.5, 8) + line(5.5, 10.5, 9, 10.5),
    "popout":     poly((7, 2.5), (2.5, 2.5), (2.5, 13.5), (13.5, 13.5), (13.5, 9)) + line(8, 8, 13.5, 2.5)
                  + poly((9.5, 2.5), (13.5, 2.5), (13.5, 6.5)),
    "reload":     path("M13 8.5A5 5 0 1 1 11.5 4.5") + poly((12, 1.5), (12, 5), (8.5, 5)),
    # Disclosure (Vision lane collapse)
    "chevron-right": poly((6, 3.5), (10.5, 8), (6, 12.5)),
    "chevron-down": poly((3.5, 6), (8, 10.5), (12.5, 6)),
    "chevron-left": poly((10, 3.5), (5.5, 8), (10, 12.5)),
    # Vision goal panel
    "image":      BOX + poly((2.5, 11.5), (6, 8), (9.5, 11.5)) + poly((8.5, 10.5), (10.5, 8.5), (13.5, 11.5)) + dot(9.25, 4.5),
    "link":       path("M6.5 5.5H5A2.5 2.5 0 0 0 5 10.5H6.5") + path("M9.5 5.5H11A2.5 2.5 0 0 1 11 10.5H9.5") + line(6, 8, 10, 8),
    # Brand mark (menu bar)
    "mark":       BOX + dot(9.5, 4, 2.5),
}

os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "Contents.json"), "w") as f:
    json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}}, f, indent=2)
for name, body in ICONS.items():
    d = os.path.join(OUT, f"icon-{name}.imageset")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, f"{name}.svg"), "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">{body}</svg>\n')
    with open(os.path.join(d, "Contents.json"), "w") as f:
        json.dump({
            "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
        }, f, indent=2)
print(f"Wrote {len(ICONS)} icons to {OUT}")
