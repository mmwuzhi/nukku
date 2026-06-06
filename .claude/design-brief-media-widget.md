# Media Widget Polish — Design Brief

A macOS notch utility widget that lives in the MacBook hardware notch area.
When the user hovers near the notch, a floating panel grows out from it.
One of the widgets inside is a media player showing what's currently playing.
This brief asks for design polish on that widget.

(Reference: similar product is Alcove. Screenshot of current state is
attached separately.)

## What we have now

Width: panel is fixed **280 pt** wide. The media row content area is
**~256 pt × 50 pt** (after the widget's own 12pt padding). Sits below a
tab strip and a thin divider that's part of the larger panel.

Single horizontal row, three columns left-to-right:

```
[ 40x40 artwork ]   ( title marquee, flexible width )   [ 40x40 play/pause ]
```

Spacing between columns: 10 pt. Content padding inside the widget: 12 pt.

- **Artwork (left)** — 40×40, currently 8 pt rounded corners. Album art when
  available; soft gradient + `music.note` SF Symbol fallback.
- **Title (middle)** — 13 pt semibold white, single line. Custom marquee
  scrolls left when text overflows. 30 pt/sec, 0.8s lead-in pause, 32 pt
  gap between loop copies. Restarts from start on track change or play press.
  Format: `"Track Title  ·  Artist"`.
- **Play/Pause button (right)** — 22 pt SF Symbol (`pause.fill` /
  `play.fill`), in a 40×40 hit area, plain button style.

Visual envelope around the media row (provided by the parent panel — not
the widget itself, mentioning for context):
- macOS 26 Liquid Glass (`.glassEffect(.clear)`) over a 0.20 black scrim
- An orange accent color halo gradient at the very top of the panel
  (Media widget's accent color = orange; other widgets have other accents)
- Squircle bottom corners
- The top edge of the panel concave-flares from notch width to panel width
  (see issue 1)

## What's wrong (please address)

### Issue 1 — the top of the panel narrows weirdly

The panel's top silhouette tapers inward to the hardware notch width
(~234 pt), then flares back out to the full panel width (280 pt) over the
first ~38 pt vertically. We wanted the panel to look like it grows out of
the hardware notch; the resulting concave curve reads as awkward / "what
is that narrowing for".

The shape is parametric. Three levers a designer can pull:

1. `topWidth` — width at y=0. Currently set to the actual hardware notch
   width (~234 pt). Could be smaller, equal, or larger than the notch.
2. `flareHeight` — vertical span over which the curve flares from `topWidth`
   to the full `width (280 pt)`. Currently ~38 pt (equal to the hardware
   notch's vertical depth). Could be smaller or larger.
3. Bezier control points for the flare curve. Currently:
   ```swift
   // Path goes from topL = (midX - topWidth/2, 0)
   //              to shoulderL = (midX - width/2, flareHeight)
   p.addCurve(
       to: shoulderL,
       control1: (topL.x,      flareHeight * 0.55),  // pulls down
       control2: (shoulderL.x, flareHeight * 0.45)   // pulls out
   )
   ```
   Mirror on the right side.

The hardware notch is a physical black cutout at the very top of the
display (no pixels there). The menubar runs across the rest of the top
strip on either side of the notch. Above the menubar there's the wallpaper
or whatever app is fullscreen.

Designer can: tighten/relax control points, change `flareHeight`, change
`topWidth`, or recommend abandoning the concave-shoulder approach in
favor of a different top treatment (e.g., panel just hangs below the
notch without trying to fuse with it).

### Issue 2 — title text vertically misaligned

The "Zen" text in the current screenshot sits low / at the bottom of the
row, while the artwork and play button are visually centered. Just confirm
the expected alignment (probably: vertically center the title relative
to the 50 pt content row, baseline aligned with the artwork's vertical
midpoint).

### Issue 3 — open polish invitation

Anything else that would make this widget feel more crafted: typography
weight, letter spacing, color emphasis (accent color use), artwork corner
radius, play-button visual weight (filled circle? bare symbol? subtle
fill?), spacing, hover/press micro-interactions, etc.

## Constraints (don't change)

- **Width**: panel is 280 pt. Don't widen.
- **Content height**: media row is 50 pt. Don't make taller.
- **Single play/pause button** only. No prev/next in the UI.
- **Always-on marquee** for the title. Don't hide-by-default and
  show-on-hover.
- **macOS 26 Liquid Glass** (`.clear` variant) + 0.20 black scrim is the
  established surface treatment.
- The panel must grow from the top of the screen (anchored to the hardware
  notch position). The widget can't be repositioned independently.

## Output we'd love back

1. **Concrete numbers** for the top-shoulder geometry: control point
   multipliers, `flareHeight`, `topWidth`. Or a recommendation to abandon
   the concave shape entirely + the alternative.
2. **Vertical centering** confirmation for the title (and any related
   refinement, e.g., font size / letter-spacing tweak).
3. **Polish recommendations** with concrete values where possible —
   corner radii, opacities, font weights / sizes, spacing adjustments,
   color/accent usage.

No need to produce Swift code. Written recommendations with numbers
are perfect — implementation follows separately.

## Reference inspirations

- **Alcove** (macOS notch utility) — clean dark pill, marquee scrolling
  title, single big play button. We've already pulled the always-on
  marquee + single-button patterns from it. Open to more of its DNA.
- **Apple Dynamic Island** (iOS) — content-aware morph, generally
  inspiration for "panel grows from the notch".

## Attached separately

- Current-state screenshot of the media widget showing both issues
- Reference screenshots of Alcove for visual vocabulary
