# Dayline design — the point of view

**A field journal, not a lifestyle blog.** Dayline is one person's
private record of their days. It should feel like a well-made notebook
that happens to have photos in it — not like a content app, and not
like every other AI-assisted app that shipped the same warm-beige
palette in 2026.

## The rules (enforced in `Theme.swift`, not by taste alone)

1. **Ink only, no accent color.** There is no accent hue. Ink marks
   the thing that matters on the page: the mic (the one action), the
   selected calendar day, the favorite mark, the mood word, the section
   kicker, the scrapbook margin tick. Everything is ink on paper. Ink
   never does two jobs in one view, and never decorates chrome (tab
   bar, buttons, navigation). The rust accent was cut 2026-11-25 —
   Steen called the orange-brown palette overdone AI slop; the layout
   and elements stayed, the color went. `accent` and `accentText` both
   resolve to `ink`, so the call sites keep reading the same.
2. **Hairlines, not shadows.** Surfaces are separated by a 1px ink
   hairline, never a drop shadow — except the mic, the one element
   allowed to float, and the small dark shadow that keeps white
   caption text legible over photos (text-over-photo is the one
   exception, and it is for legibility, not depth).
3. **Tags are words, not pills.** Tags and mood are set as plain
   lowercase text, separated by middots, under a small-caps label.
   No blue, no purple, no capsules anywhere in the app.
4. **Serif has a job.** Serif is for dates and titles only. Body text
   is the system font — readable, honest, not costume.
5. **Photos are prints.** Media gets a thin frame and a plain-text
   caption (video duration, Live), never a black pill badge.

## What changed in the taste pass (2026-11-23)

- `journalCard` went from 16pt radius + shadow to 12pt radius +
  hairline, no shadow. One card style, everywhere.
- The tab bar and the Polish + Save button went from rust to ink;
  the mic kept rust (later cut to ink with the rest of the accent).
- Tag pills (blue/purple capsules) are gone in Today, Year, and the
  mood display; `TagLine` replaces them everywhere. Mood is the one
  expressive word on a page: italic serif, ink.
- The Year grid is now a month-grouped index (serif month headers,
  day counts, newest first) instead of an undifferentiated grid.
  Favorites finally exist as a feature: `isFavorite` had been an
  orphaned model field since the scaffold — it now has a star toggle
  in EntryDetail and an ink star on Year cards.
- Scrapbook text chunks carry a short ink tick (the margin mark of a
  journal); media badges became plain caption text.
- Trends stopped being a default iOS `List` and joined the design
  language (scroll sections, hairline rows, tabular counts).
- DataView's Form buttons stopped being system blue (`.tint(.ink)`).
- The keyboard no longer covers Polish + Save: interactive dismissal
  plus a Done key (BACKLOG item 9, closed here).

## What changed in the swarm fix pass (2026-11-23)

- DataView stopped being a default iOS `Form` and joined the design
  language (scroll sections, journal cards, hairline rows).
- Trends got a loading state: tapping a tag clears the previous
  insight, shows a spinner, and marks the selected row — it no longer
  shows yesterday's insight while the new one loads.
- The day browser's black pill badge became plain caption text, like
  every other photo caption in the app.
- The success label went from system green to ink.
- Link previews are journal cards now (title + host), not LPLinkView's
  native chrome.
- Ink's text-safe shade (`accentText`, which is just ink now) is used
  for kickers, the mood word, and the selected-day disc.

## What changed in the ink-only palette swap (2026-11-25)

- Steen picked Ink only: `accent` and `accentText` in `Theme.swift`
  both resolve to `ink`. The mic, selected day, favorite mark, mood
  word, kicker, and margin tick are all ink now — no hue anywhere.
- The app icon's rust circle became ink (same circle + lines, no
  color). The layout and elements are unchanged; only the color went.
- The Year card's date + preview text were checked against a real
  screenshot and are on light paper, not over the photo — the dark
  area in the shot is the sunset test image's own dark bottom edge,
  not a background behind the text. No legibility defect there.

## What we refuse

- Streaks, scores, coaching copy, or anything that turns a journal
  into a habit app. The perfect-day program is paused by Steen's
  choice; the journal is not that app.
- Generic "delight" — confetti, gradients, glassmorphism, emoji as
  decoration. If a surface needs more emphasis, it gets a different
  layout, not a heavier effect.
- Invented narrative prose in stories (see DISCOVERY.md): the agent
  curates and labels; the words stay Steen's.
