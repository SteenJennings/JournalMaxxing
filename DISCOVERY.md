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

## The concept taxonomy (Steen's direction)

Instead of letting classification invent free-form tags, Dayline gets a
**controlled vocabulary of roughly 100 canonical concepts**. The AI can
only classify entries into concepts from that list. This is the spine for
Themes, collections, and search.

Design rules:

- **Multi-label, not one bucket.** A Phuket dinner entry can be Dinner +
  Dining Out + Travel + Vacation + Beach. A leg-day entry can be Gym +
  Strength Training + Fitness.
- **Broad rollups and specific concepts coexist.** Fitness is a useful
  rollup; Running, Cardio, Strength Training, Gym, and Basketball are
  more specific siblings/children.
- **Concepts are separate from detail tags.** Concepts answer "what kind
  of day/activity was this?" Free-form detail can still hold names and
  specifics ("Bay Club", "Mission Taqueria", a person or restaurant).
- **The taxonomy is data, not code.** A versioned JSON file holds each
  concept's stable ID, display name, group, aliases, text cues, Vision
  label mappings, and parent rollups. Trial and error means editing that
  file and reclassifying, not rewriting the app.
- **Every assignment carries provenance.** Store concept ID + source
  (model text classification, keyword fallback, Vision, place/date, or
  manual correction) + confidence. Collections and search can then say
  *why* an entry belongs, and bad rules can be found and pruned.
- **Manual corrections win.** If Steen removes Gym from an entry, later
  automatic passes do not silently put it back.

### Classification sources

1. **Entry-time model classification:** at polish time, Foundation Models
   choose applicable concepts from the taxonomy using the transcript.
   Guided/constrained output should return concept IDs only.
2. **Deterministic fallback:** aliases and text cues map words to the
   same concepts when the model is unavailable ("deadlift" →
   Strength Training + Gym + Fitness).
3. **Photo classification:** persisted Vision labels map to concepts
   (`swimming_pool` → Pool + Swimming; `bicycle` → Cycling + Cardio).
4. **Place/date signals:** a day clustered away from home can add Travel;
   leisure signals can add Vacation; geocoded country/place remains a
   separate facet rather than becoming a concept.
5. **Manual edits:** Steen can add/remove concepts on an entry; these are
   the ground truth for trial-and-error tuning.

### Starter taxonomy draft (100 concepts, for trial and error)

This is a starting point grounded in Steen's actual life, not a locked
list. Groups are for browsing and rollups; concepts remain flat,
multi-label IDs underneath.

- **Movement & Sport (16):** Fitness, Gym, Strength Training, Cardio,
  Running, Cycling, Swimming, Basketball, Hiking, Walking, Skiing,
  Snowboarding, Golf, Climbing, Yoga, Stretching & Mobility
- **Food & Drink (10):** Dining Out, Dinner, Brunch, Cooking, Baking,
  Coffee, Dessert, Drinks, Groceries, Takeout
- **Travel & Outdoors (14):** Travel, Vacation, Road Trip, Flight,
  Day Trip, City Exploring, Outdoors, Beach, Pool, Camping, Nature,
  Mountains, Winter Trip, Hotel Stay
- **Social (12):** Social, Family, Friends, Partner, Date Night, Party,
  Celebration, Wedding, Hosting, Visitors, Group Trip, Holiday
- **Work & Making (10):** Work, Meetings, Team Event, Deep Work, Career,
  Coding, Side Project, Learning, Planning, Networking
- **Home & Daily Life (12):** Home, Chores, Errands, Shopping, Finances,
  House Hunting, Car, Pets, Gardening, Home Project, Morning Routine,
  Evening Reset
- **Health & Body (11):** Health, Doctor, Dentist, Physical Therapy,
  Therapy, Pain / Injury, Sick, Sleep, Rest & Recovery, Self-Care,
  Grooming
- **Leisure & Culture (15):** Journaling, Reading, Writing, Movies, TV,
  Music, Concert, Gaming, Photography, Art & Culture, Museum,
  Sports Watching, Relaxing, Live Event, Market

Expected tuning: merge concepts that never fire, split concepts that
become catch-alls, and adjust aliases/cues from real misses. The target
is "about 100 useful concepts," not exactly 100 for its own sake.

## Search design

One search field (lives in the future Explore tab; see IA) over a single
`SearchIndex` built from entries + AssetFeatureCache. Search has three
layers: a model that interprets the query, a deterministic executor that
runs it, and visible match reasons.

### 1. Model query planner ("agentic" fuzzy matching, constrained)

At search time, Foundation Models translate natural language into a
**structured query plan constrained to the taxonomy**. The model does not
invent tags or query the database freely. A plan contains:

- exact concept IDs
- related concept IDs (siblings, children, and rollups), each with a
  relationship strength
- text terms and stems/lemmas to scan in raw + polished entry text
- Vision/media labels that would support the query
- place, date, mood, person-name, and media-type facets
- an optional broadening step if the first pass returns too little

The executor validates every concept ID against the taxonomy, runs the
plan, and can run one model-proposed broadening pass when results are
empty or very sparse. If results are abundant, specific matches stay
ranked above broad related matches rather than flooding the page.

The UI shows the expansion as removable chips — e.g. **Cardio × Running
× Gym × "treadmill"** — so fuzzy search remains inspectable rather than
a black box. A lexical fallback (aliases, stemming/lemmatization, and
typo tolerance) covers model-unavailable cases.

### 2. Deterministic matching and ranking

Signals, strongest to weakest:

1. manually assigned or exact concept match
2. model-classified exact concept
3. text term in the polished or raw transcript
4. related concept (child/sibling before broad rollup)
5. matching Vision/media label in AssetFeatureCache
6. generic parent/rollup alone

Place/date facets act as filters when the query names them ("in
Thailand", "last October"). Result shape remains Photos-like: a matching
collection card first ("Cardio — 18 entries"), then Timeline cards with
the matched snippet and a small reason ("Running · text mentions 'ran'").

### "Cardio" walkthrough

Query: **cardio**

The planner emits approximately:

- exact concept: Cardio
- related concepts: Running, Cycling, Swimming, Gym, Fitness
- text terms: cardio, run, ran, running, treadmill, elliptical, rowing,
  bike ride, swim
- media labels: treadmill, bicycle, swimming_pool, track, gym equipment

An entry dictated as "went for a run before work" is found even if the
word *cardio* never appears: entry-time classification assigned Running
+ Cardio + Fitness, and query-time expansion would catch the text anyway.
A strength-only gym entry may appear much lower through Gym/Fitness, but
it should not outrank explicit running/cycling/swimming entries. That
ranking distinction is one of the main trial-and-error tests.

### "Dinner in Thailand" walkthrough

The planner separates facets instead of treating the phrase as one tag:

- concepts: Dinner + Dining Out
- place facet: country = Thailand (Phuket is stored as a child place)
- media labels: food / restaurant / table
- optional relation: entries inside the Thailand trip cluster rank first

This works when the dictated text only says "dinner" and the photo's GPS
supplies Phuket/Thailand, or when the text says Thailand and the photo
has no GPS.

### Semantic upgrade path (later, only if this still misses)
MobileCLIP (Apple's open CoreML CLIP) embeddings for media + contextual
embeddings for text could catch cases with no shared vocabulary at all
("that cozy cabin weekend"). The taxonomy + AssetFeatureCache design is
forward-compatible with an embedding column. Do **not** start here: the
model-planned taxonomy search is more explainable and directly testable.

## The Discover page — "Memory Lane" (deep design)

The page's job is different from Today's (write) and Year's (browse by
time): **resurface the past so it feels alive, and make anything in it
findable in seconds.** Working name for the experience: *Memory Lane*.
(Tab label still open — Discover / Memories / Lane; see Open questions.
Page title can be "Memory Lane" regardless of tab label.)

Visual language: Photos is dark and photo-first; Dayline's version
should stay editorial — photo covers, but serif display titles, paper
backgrounds, rust accents. A memory should read like a page from the
journal, not a stock gallery.

### Page layout, top to bottom

1. **Search** — pinned at top. The model-planned search from above,
   with expansion chips and match reasons. Below the field before typing:
   **Recent searches** and **Suggested searches** generated from his own
   data (concept × place combos that actually exist: "cardio",
   "dinners in Thailand", "beach days", "days with Malia"). Suggestions
   are only ever phrases the index can answer well.
2. **Memory Lane hero** — one featured memory, full-width: hero photo,
   serif title, date context line ("One year ago today" / "From your
   Thailand trip"), two-line entry snippet, mood chip if positive.
   Changes daily; swiping cycles 2–3 alternates. Tap → Story view.
3. **Trips rail** — cards: cover photo, place-hierarchy title
   ("Puerto Vallarta"), date range, entry count, days count.
4. **Themes rail** — concept collections with entry counts; ordered by
   a blend of frequency and recency so living themes surface, dead ones
   sink. ("Gym — 42 this year", "Dinners — 18".)
5. **Places rail** — city/country cards; cover = best photo there;
   subtitle shows both levels ("Phuket · Thailand").
6. **People in words rail** — name collections derived from *text
   mentions only*, labeled honestly ("Malia — mentioned in 63 entries").
   No face claims; this is a journal, names in words are the signal.
7. **Unwritten memories rail** — **recent gaps only** (Steen's rule,
   2026-10-21). A missed day is only worth prompting while he can still
   actually remember it. Eligibility: the day is within the trailing
   **21 days**, AND he was journaling around it (entries in the
   surrounding ±7 days) or the day belongs to a trip cluster that ended
   within the window. "Oct 12 — 23 photos at the beach, no entry." Tap →
   that day in Today, photos pre-loaded, ready to backfill. Prompts
   **expire silently** when the window passes — a 6-month-old photo day
   is never presented as a missed memory, because it isn't one anymore;
   it just becomes part of Places/Themes via its photos. Max 3 shown,
   strongest first. This is the page's growth engine for the present,
   not an archaeology project.
8. **Insights strip** — Trends, matured: gentle, descriptive facts
   computed from concepts + mood + dates. "12 journal days this month."
   "Gym days cluster on Tuesdays." "Your happiest tags: beach, friends."
   Descriptive only — no coaching, no streaks-shaming, no scores.
9. **All memories river** — below the rails, everything in reverse
   chronological order, grouped by month, Timeline cards. The rails are
   shortcuts; the river is the guarantee nothing is hidden by the
   curation.

Rails appear only when they clear a usefulness threshold (Trips ≥ 1,
Themes ≥ 3 entries, Places ≥ 2 entries); a two-week-old journal shows
search + hero + river, not a page of empty sections.

### The resurfacing engine (how the hero memory is picked)

Computed on first page open of the day, then cached for the day
(`ResurfaceState`: featured IDs, shown history, hidden days/themes).

Scoring, in order:
1. **Anniversaries** — same calendar day, prior years first, then prior
   months ("6 months ago today").
2. **Trip highlights** — best entry from a trip that ended ~1/3/6/12
   months ago.
3. **Strong days** — high media quality + long entry + positive mood.

Guardrails (non-negotiable):
- **Never hero** entries whose concepts include Sick, Pain / Injury,
  Therapy, Doctor, Dentist, or whose mood is negative. Sad days remain
  findable and in the river — they're just never the cheerful postcard.
- **No repeats** within 60 days; "Not this memory" hides it forever;
  "Less like this" mutes that theme/place for hero purposes only.
- **One memory a day, in-app only.** No notifications, no badges — the
  page rewards opening; it never nags. (If Steen ever wants a morning
  memory, that's a separate opt-in.)

### Story view (what a memory/trip/theme opens into)

Reuse the scrapbook machinery across days: a continuous editorial page —
cover, title, rule subtitle — then entries in date order, each day a
section with its text chunks interleaved with its best photos
(`ScrapbookLayout`, videos full-width, same as Today). A trip reads as
one story instead of five disconnected entries. Controls: jump-to-day,
share/export the story (image or PDF) as a later extra.

### Management, revisited

Edit mode on the page: reorder rails, pin any collection into a
**Pinned** row above Trips (Photos parity), hide collections or whole
rail types. All of it lives in `CollectionPrefs` + `ResurfaceState`;
collections remain computed, only preferences persist.

## The agentic Memory Builder (chains & stories)

Everything above the line in this doc is retrieval. This section is the
piece Steen asked for explicitly (2026-10-21): an **agentic layer inside
the app** that decides what deserves to be chained together and turns it
into a story. Verdict: yes, buildable on-device — as *bounded agent
passes over structured evidence*, not a free-roaming autonomous agent.

### Two tiers: Collections vs Stories

- **Collection** = complete facet membership. Every Gym entry. Nothing
  is ever excluded; this is the trustworthy, boring layer (search and
  Themes live here).
- **Story (chain)** = a *curated* sequence the agent assembled because
  the entries genuinely connect and the strong ones carry it. A story
  may draw from a collection but only its core entries become chapters.
  Curation can omit; it can never hide anything from the collection
  underneath, and every omission is one tap away ("View all 23 entries"
  at the end of every story).

### What makes a chain (candidate types, in flagship order)

1. **Trips — the flagship.** Temporal + spatial continuity: consecutive
   days away from home. Chapters break at place changes; the chain
   carries a route (San Francisco → Memphis → New Orleans), stats
   (6 days · 4 places · 212 photos · 5 entries), and a cover. Trips are
   where chaining is unambiguous and the payoff is highest, so this
   candidate type ships first and sets the quality bar.
2. **Place × theme series.** Recurring life in one place: "Dinners in
   San Francisco", "Beach days", "Nights at the theater district". The
   agent tests whether the series is *strong*: enough entries where the
   dinner was actually the subject (he wrote about it, there are food
   photos, a restaurant is named) — not every day that happens to
   mention eating. Routine takeout mentions stay in the Dinner
   collection and out of the story.
3. **Rituals & arcs.** Repeated patterns with a shape: ski season,
   a training block, building Dayline, Sunday resets. Detected from
   concept + cadence; proposed only when the arc has a beginning and
   some density — a scatter of mentions is a theme, not an arc.
4. **Explicitly out of scope for auto-stories:** health journeys
   (PT recovery, illness, therapy arcs). Real chains exist there, but
   auto-assembling them into a cheerful story is exactly wrong. Search
   and collections still cover them fully; stories there are
   manual-only if Steen ever wants one.

### Entry strength (how the agent tells a *special* dinner from a mention)

Each entry gets an importance score from observable signals:

- **Text depth** — he actually wrote about it (length, detail, named
  specifics) vs a passing clause
- **Specificity** — named restaurant/place/people, occasion words
  (anniversary, birthday, first time, finally)
- **Superlatives & affect** — "best", "amazing", "incredible", strong
  positive mood
- **Media strength** — photo count, top aesthetic scores, food/people
  labels matching the theme, a video
- **Social weight** — guests/visitors/partner present in text
- **Rarity** — first time at a place, once-a-year events

Chapters require strength above a bar; below-bar entries in the same
collection become "also in this collection" footnotes, not chapters.

### The agent pipeline (bounded passes, cached verdicts)

1. **Candidate generation (deterministic).** Cluster the facet index:
   trip clusters, concept × place clusters, cadence patterns. Cheap,
   complete, no model involved. Output: candidate bundles (member entry
   IDs + facet evidence + stats).
2. **Judge pass (Foundation Models).** Per candidate, the model sees a
   compact evidence card per entry (date, concepts, place, 1–2 sentence
   excerpt, strength signals) — never the whole journal — and returns:
   coherence score, verdict (story / plain collection / reject), core
   vs peripheral membership, and a one-line reason. Constrained output,
   validated against entry IDs.
3. **Assembly pass.** For accepted stories: chronological order (trips)
   or chronological-with-strongest-first-chapter (series), chapter
   breaks at place/date seams, cover pick (best media among core
   entries), title + subtitle **built from his own material** — place
   names, dates, and pull-quotes are verbatim from his entries. The
   agent curates and labels; it does not invent narrative prose for the
   story body. (An optional generated one-line intro is allowed only if
   visually marked as generated.)
4. **Critic pass.** A second, adversarial check before anything is
   shown: duplicates or >40% overlap with an existing story (merge or
   demote to sub-story), sensitivity screen (the hero guardrails apply
   to stories too), minimum gates: ≥3 core entries (trips: ≥2 days),
   ≥half the core entries carrying media or substantial text,
   coherence ≥ threshold. Fail = candidate dies quietly, reason logged.
5. **Human loop (lightweight).** Stories appear with a "Why this
   story?" line (the judge's reason, in plain words). Actions: **Keep**,
   **Not a story** (candidate permanently suppressed), **Edit members**,
   **Rename**. Dismissals and approvals are stored as tuning signals:
   repeated dismissals of a candidate type raise its bar; approvals
   lower it slightly. The agent proposes; Steen's verdicts calibrate it.

### Running it inside a phone app (the honest constraints)

- **No true background agent on iOS.** Passes run incrementally: after
  an entry save (re-judge only affected candidates), and on Discover
  open (drain a small time-boxed job queue). Everything is resumable;
  nothing blocks the UI.
- **Context limits are handled hierarchically.** FM's ~4k-token window
  never sees a whole trip's text: per-entry evidence cards first, then
  the judge works from cards; long trips get per-day one-line digests
  before the chain-level pass.
- **Verdicts are cached by content hash.** If a candidate's membership
  and evidence haven't changed, it is never re-judged. Most opens do
  zero model work.
- **Deterministic fallback.** If Foundation Models is unavailable, trips
  still chain by the clustering rules alone (no judge polish, plainer
  titles), and series/rituals stay collections until a judge exists.
  The app degrades; it doesn't break.
- **Provenance everywhere.** Every story stores: candidate type, member
  entry IDs with core/peripheral flags, judge reason, model/rules
  version, and Steen's verdict. Any story can be traced to *why it
  exists* — the same explainability rule as collections.

### Acceptance tests (trial and error, defined up front)

- A 5-day trip with entries must become one trip story, correctly
  chaptered, with no home days absorbed into it.
- "Dinners in San Francisco": routine takeout one-liners must NOT
  become chapters; the anniversary dinner with photos and a named
  restaurant MUST.
- A candidate Steen dismisses must never reappear in altered disguise
  (same core membership ±1 entry = same candidate).
- No story may be built from Sick/Pain/Therapy/medical entries.
- Every story's "Why this story?" must cite signals a human can verify
  from the entries themselves.

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
- No background daemons and no third-party backend. One nuance:
  CLGeocoder resolves coordinates through Apple's geocoding service, so
  place-name lookup is not strictly offline; cache aggressively by
  location cluster. If strict fully-offline places ever matter, the
  alternative is bundled coarse geographic boundary data for
  country/region lookup. Everything else here is on-device and $0.

## Phasing (for when the core app is proven)

1. **Taxonomy + entry classification** — ship the ~100-concept data file;
   classify entries at polish/save with provenance and manual override;
   backfill existing entries; build theme collections from concepts.
2. **Deterministic search** — exact concepts, text terms, mood, dates,
   and result grouping/reasons. (Proves the index and ranking.)
3. **Model query planner** — natural-language plans constrained to the
   taxonomy, visible expansion chips, one broadening pass for sparse
   results, and the trial-query suite (Cardio, Gym, Thailand dinners…).
4. **AssetFeatureCache + Places/Trips** — persist Vision/location facets;
   geocode hierarchy (Phuket ⊂ Thailand); home derivation; trip
   clustering; photo evidence joins search and themes.
5. **Agentic Memory Builder** — candidate generation, judge/assembly/
   critic passes, story storage with provenance, and the Keep /
   Not-a-story calibration loop. Trips first (flagship), then
   place × theme series, then rituals/arcs.
6. **Discover page / Memory Lane** — the rails per the deep design
   above (Stories rail fed by the Memory Builder), the hero
   resurfacing engine (anniversaries → trips → strong days, with the
   sensitivity guardrails and ResurfaceState), Story view, the
   recent-only Unwritten memories rail, the insights strip, and the
   Pinned/Hidden/Rename management layer.
7. *(Optional)* **Embedding layer** — MobileCLIP/contextual embeddings;
   only with evidence that taxonomy-planned search is still missing
   things Steen looks for.

## Open questions for Steen (answer when we build, not now)

- Tab/page name: Discover, Memories, or Lane? (The design above uses
  "Memory Lane" as the page title whichever tab label wins.)
- Photo-only days: **decided in principle** (Steen, 2026-10-21) — the
  Unwritten memories rail covers recent gaps only (default trailing
  21 days, journaling activity nearby or a just-ended trip), prompts
  expire silently, and older photo days surface only through
  Places/Themes. Remaining knob: is 21 days the right default window
  (7 / 14 / 30)?
- Is "People" worth doing via *names in text* (entries mentioning Malia)
  as pseudo-collections, given face identity is off-limits?
- Taxonomy governance: fixed at ~100 concepts curated by us, or should
  the app notice recurring unclassified themes and *propose* a new
  concept for one-tap approval (never silently adding it)?
- Trial-and-error surface: is a small "Concept Lab" worth building —
  recent entries with their assigned concepts + confidences, one-tap
  add/remove, and a saved test-query list — or is reviewing corrections
  through normal entry editing enough?
