# Nukku TODOs

## Product

- Browser rich metadata for Zen / Firefox needs a future companion extension. The current app-level
  fallback intentionally avoids active-tab/window-title guessing so Nukku does not display unrelated
  reading-page titles as media titles.

## Deferred polish

- Cache the source app icon in `MediaViewModel` and refresh it only when the source bundle identifier
  changes, instead of resolving the same workspace icon on every media refresh.
- Prefer a Center-Stage-capable camera format near 720p for the small notch preview instead of always
  selecting the highest-resolution supported format.
- Include the year in `DateChip` when an event crosses a year boundary or the selected date is outside
  the current year.
- Re-evaluate hover collapse when a notch popover closes while the pointer is already outside the
  interactive region; today the next mouse movement triggers that re-evaluation.
