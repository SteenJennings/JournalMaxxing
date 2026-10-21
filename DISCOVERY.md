# Dayline Discovery — auto-collections & search (design research)

Status: **research only** (Steen, 2026-10-21). Build nothing until the core
app is proven on a real phone. This doc designs the historical/discovery
layer so that when we do build it, we're executing a plan, not improvising.

## The reference experience: Apple Photos → Collections

Photos' Collections tab (see Steen's screenshot) works because **nothing
there is a folder**. It is one facet index rendered many ways:

- **Memories** — auto-curated stories, grouped by place / event / people /
  time span, titled from metadata ("Exploring Santa Clara — Oct 21, 2022")
- **Pinned** — user-pinned shortcuts to collections (Favorites, Map,
  Recently Saved)
- **Albums** — user albums + smart albums
- Elsewhere: **People & Pets** (face clustering), **Places** (map),
  **Media Types**, and one **search** box that queries everything —
  objects ("pool"), places, dates, people — returning typed results
  (photos, albums, people, places), with token suggestions as you type.

The mechanics worth copying:

1. Every asset is annotated once into a **facet index**: faces, scene
   labels, location, timestamp, quality, favorites.
2. **Collections are computed views** over that index, not containers.
   Nothing is "filed"; criteria decide membership, so one item can live in
   many collections.
3. **Search is the same index**, queried with mixed facets at once
   ("pool october"), ranked, and grouped by result type — a matching
   *collection* is offered above individual items.
4. Auto-created things are **explainable and manageable**: you can pin,
   hide, rename, or remove them without destroying data.

Dayline's advantage: our corpus is tiny (a personal journal — hundreds to
low thousands of entries), and our facets are richer in *meaning*: we have
the words themselves.

## Dayline facets (what we can index on-device, $0, local)

| Facet | Source | Status |
|---|---|---|
| Entry text (raw + polished) | DayEntry | stored today |
| Tags, mood | DayEntry (FM/fallback at polish) | stored today |
| Date / time spans | DayEntry.date | stored today |
| Entry favorite | DayEntry.isFavorite | modeled, unused in UI |
| Media labels (pool, food, dog…) | Vision classification of entry media | computed at ranking time, **not persisted** ← key gap |
| Media aesthetics / faces / favorite / video | Vision + PHAsset | computed at ranking time, not persisted |
| Media location | PHAsset.location | never read yet |
| Place names | CLGeocoder reverse-geocode of media location (cached) | new |
| Home location | derived: modal nighttime location cluster | new, derived |

**Proposal: persist an `AssetFeatureCache`** — one SwiftData record per
media localIdentifier: labels, aestheticScore, faceCount, isFavorite,
isVideo, latitude/longitude, computedAt. Filled lazily whenever ranking
already computes features (free), plus a backfill pass from the Data tab
("Build photo index"). This one cache powers collections, place search,
and label search. Text facets need no new storage.

**Hard platform limits (design around them):**
- iOS does **not** expose Photos' person identities or Memories to
  third-party apps. No "Malia" collection by face. People facets stop at
  faceCount and names mentioned in text (which *are* searchable — arguably
  better for a journal).
- Location depends on photo EXIF; missing GPS ⇒ the day simply has no
  place facet (fall back to other facets).
- CLGeocoder is rate-limited; geocode once per location cluster, cache
  forever.

## Auto-collections taxonomy (computed views, in priority order)

1. **Trips** — the Photos-Memories analog and the highest-value one.
   Detection: cluster entry-days by media location; a *trip* is a maximal
   run of days whose dominant location is > 80 km from home, spanning
   ≥ 2 days **or** a single day > 150 km away. Home = the modal nighttime
   (20:00–06:00) location cluster over the last 90 days. Title: place name
   + date range ("Puerto Vallarta — Sep 24–27"). Cover: the trip's
   highest-quality asset. Optional FM flourish (later): a title from the
   entries' own words ("Puerto Vallarta Bach Trip").
2. **Themes** — tag/topic collections: any normalized tag or concept with
   ≥ 3 entries becomes a collection ("Gym", "Dinners", "Park Days").
   Normalization via a **concept map** (below) so *gym / workout /
   leg day* land in one collection instead of three anemic ones.
3. **Places** — city-level groups from geocoded media locations
   ("San Francisco", "Vashon Island") with entry counts; ≥ 2 entries.
4. **On This Day** — journal-native: entries from this calendar day in
   prior months/years; also "One year ago this week" rails. Cheap to
   compute, emotionally the strongest rail in a journal app.
5. **Media collections** — "Entries with video", "Favorites" (uses the
   dormant isFavorite), "Longest entries", mood collections ("Happy days",
   mood = happy) if they prove interesting in Trends data first.

Every collection object is `{ id, kind, title, subtitle (rule in words),
coverAssetId, entryDates, count }` — **the subtitle states the rule**
("5 entries tagged gym · Oct 2026") so auto-creation is never mysterious.

## Search design

One search field (lives in the future Explore tab; see IA) over a single
`SearchIndex` built from entries + AssetFeatureCache:

- **Matchers per token:** exact tag → concept-expanded tags → entry text
  (raw + polished, word-boundary contains) → media labels (via cache) →
  place names → mood → date phrases.
- **Date phrases:** "october", "last summer", "2025", "last week" parsed
  with NSDataDetector + a small grammar for month/season/year names;
  treated as a filter facet combined with other tokens.
- **Concept map (the "Gym" problem):** a small curated, editable table:
  `gym → gym, workout, leg day, deadlift, squat, lifting, run, basketball…`.
  Search and Themes both expand through it. Seeded with ~30 concepts from
  Steen's actual tag vocabulary (visible in Trends), stored as data
  (JSON in the app bundle, later editable) — not hardcoded logic.
- **Result shape (Photos-like):** a matching *collection card first*
  ("Gym — 14 entries, Oct 2025–Oct 2026 →"), then matching entries as
  Timeline cards, newest first, with the matched snippet highlighted.
  Ranking: facet strength (tag > text > label) then recency.
- **"Gym" walkthrough:** token `gym` → tag match on entries tagged gym/
  workout → concept expansion catches a "leg day" entry whose text says
  *deadlift* and whose photos are Vision-labeled *weightlifting* →
  place/date facets idle → 14 results + a Gym theme collection card on
  top. Zero ML models required for v1 of search.

### Semantic upgrade path (later, only if literal search disappoints)
MobileCLIP (Apple's open CoreML CLIP) embeddings for media + NLContextual
embeddings for text would make "gym" match bench-press photos with no
shared vocabulary, and "that cozy cabin weekend" match an untagged trip.
This is the parked Phase-2 item from FEASIBILITY.md; the facet index and
AssetFeatureCache are forward-compatible with it (add an embedding blob
column). Do **not** start here — literal + concepts is explainable,
testable, and probably enough at journal scale.

## Information architecture

- **Trends tab → "Explore" tab**: Search field pinned on top; rails:
  On This Day · Trips · Themes · Places · Tags (today's Trends content,
  demoted to one rail) · Favorites. Year tab stays the pure chronological
  grid — history browsing splits into *time* (Year) and *meaning*
  (Explore), mirroring Photos' Library vs Collections.
- **Collection detail**: cover header (hero asset, title, rule subtitle,
  date span), the entries as Timeline cards (tap → EntryDetail), and a
  horizontal photo strip of the collection's best media.
- **Management (Photos-like, non-destructive):** long-press / Edit mode on
  rails: **Pin** (moves to a Pinned rail on top), **Hide**, **Rename**
  (custom title override). Stored as a tiny `CollectionPrefs`
  { collectionId, pinned, hidden, customTitle } — collections stay
  computed; only preferences persist.
- **Explainability:** every auto-collection shows its rule as its
  subtitle; search results can show *why* ("matched tag: gym") in small
  print during development of the feature. Trust in auto-organization
  comes from seeing the rule.

## When things compute

- Facet cache: opportunistically at polish/save (already computing);
  full backfill button in Data tab with progress + cancel.
- Collections: recomputed on Explore appearance and after saves; at
  journal scale this is milliseconds. Geocoding amortized and cached.
- No background daemons, no network, nothing leaves the device —
  consistent with Dayline's local/$0 constraints.

## Phasing (for when the core app is proven)

1. **Search v1** — text/tags/mood/date-phrase search over entries +
   result grouping. (No new storage; proves the query model.)
2. **Themes** — concept map + tag-normalized theme collections in a
   renamed Explore tab; Trends content folds in.
3. **AssetFeatureCache + Places/Trips** — persist facets; geocode cache;
   home derivation; trip clustering.
4. **On This Day + Pinned/Hidden/Rename** — the journal-native rail and
   the management layer.
5. *(Optional)* **Semantic layer** — MobileCLIP media embeddings; only
   with evidence that literal search is missing things Steen looks for.

## Open questions for Steen (answer when we build, not now)

- Should Trips require journal entries, or also surface photo-only days
  (days you shot but never journaled — Photos does; Dayline could offer
  "you never wrote about Puerto Vallarta day 2")?
- Is "People" worth doing via *names in text* (entries mentioning Malia)
  as pseudo-collections, given face identity is off-limits?
- Concept map: fully curated by us, or should the app propose new
  concepts from his tags for one-tap approval?
