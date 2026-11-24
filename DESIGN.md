# Dayline design — the point of view

**A field journal, not a lifestyle blog.** Dayline is one person's
private record of their days. It should feel like a well-made notebook
that happens to have photos in it — not like a content app, and not
like every other AI-assisted app that shipped the same warm-beige
palette in 2026.

## The rules (enforced in `Theme.swift`, not by taste alone)

1. **One accent, used sparingly.** Rust marks the thing that matters
   on the page: the mic (the one action), the selected calendar day,
   the favorite mark, the mood word, the section kicker, the scrapbook
   margin tick. Everything else is ink on paper. Rust never does two
   jobs in one view, and never decorates chrome (tab bar, buttons,
   navigation). The taste pass claimed "exactly three jobs" while the
   shipped code used rust in six places — the rule now names the real
   system instead of pretending. Rust has two values of one hue: the
   accent (surfaces, icons) and `accentText`, darkened for small text
   (bright rust on paper is ~3.3:1, failing for 11pt text).
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
  the mic kept rust.
- Tag pills (blue/purple capsules) are gone in Today, Year, and the
  mood display; `TagLine` replaces them everywhere. Mood is the one
  expressive word on a page: italic serif, rust.
- The Year grid is now a month-grouped index (serif month headers,
  day counts, newest first) instead of an undifferentiated grid.
  Favorites finally exist as a feature: `isFavorite` had been an
  orphaned model field since the scaffold — it now has a star toggle
  in EntryDetail and a rust star on Year cards.
- Scrapbook text chunks carry a short rust tick (the margin mark of a
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
- Rust's text-safe shade (`accentText`) is used for kickers, the mood
  word, and the selected-day disc, so small rust text reads at 11pt.

## What we refuse

- Streaks, scores, coaching copy, or anything that turns a journal
  into a habit app. The perfect-day program is paused by Steen's
  choice; the journal is not that app.
- Generic "delight" — confetti, gradients, glassmorphism, emoji as
  decoration. If a surface needs more emphasis, it gets a different
  layout, not a heavier effect.
- Invented narrative prose in stories (see DISCOVERY.md): the agent
  curates and labels; the words stay Steen's.
