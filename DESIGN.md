# Dayline design — the point of view

**A field journal, not a lifestyle blog.** Dayline is one person's
private record of their days. It should feel like a well-made notebook
that happens to have photos in it — not like a content app, and not
like every other AI-assisted app that shipped the same warm-beige
palette in 2026.

## The rules (enforced in `Theme.swift`, not by taste alone)

1. **One accent, used sparingly.** Rust is the mic (the one action),
   the selected calendar day, and the favorite mark. Everything else is
   ink on paper. If rust shows up in a fourth place, it is a bug.
2. **Hairlines, not shadows.** Surfaces are separated by a 1px ink
   hairline, never a drop shadow — except the mic, the one element
   allowed to float.
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

## What we refuse

- Streaks, scores, coaching copy, or anything that turns a journal
  into a habit app. The perfect-day program is paused by Steen's
  choice; the journal is not that app.
- Generic "delight" — confetti, gradients, glassmorphism, emoji as
  decoration. If a surface needs more emphasis, it gets a different
  layout, not a heavier effect.
- Invented narrative prose in stories (see DISCOVERY.md): the agent
  curates and labels; the words stay Steen's.
