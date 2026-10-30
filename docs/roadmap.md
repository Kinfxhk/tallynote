# What the changelogs say we should build

Read: Soulver 3 → 4 changelog and "what's new in 3"
([documentation.soulver.app](https://documentation.soulver.app/changelog),
[whats-new](https://documentation.soulver.app/whats-new)), Numi 3.18 → 3.32
([changelog](https://github.com/nikolaeu/numi/blob/master/changelog.md)), plus
the Soulver CLI help output on this machine.

## What they actually spent their releases on

| Where the effort went | Evidence | Read-through |
|---|---|---|
| **Organising many notes** | Soulver 3's headline work: sidebar sheet manager, folders, trash, sort by date/title, Spotlight search | A mature calculator competes on *finding and keeping notes*, not on arithmetic |
| **Typing speed** | Scrubbable numbers (shift-hover), auto thousands separators while typing, QuickOperators (`1p1` → `1 + 1`), variable autocomplete, ⌘L reference insertion, drag lines by the answer column | ~15 of the "80+ features" are input ergonomics |
| **Smarter totals** | "Smarter total will ignore variable declarations & referenced lines automatically"; subtotal = lines above up to the next subtotal/heading | Validates our leaf-only grand total; they also made subtotals a *first-class line* |
| **Quick capture** | QuickSoulver: global hotkey, menu bar, Spotlight-like window, ⌘S to save into a sheet | Their single biggest daily-use feature |
| **Locales & formats** | v3 fixed "1.003.020 misread as a date"; v3.14.1 fixed space-separated thousands after sync; v4.0.2 fixed fractional tax rates (9.875%); per-sheet money formatting | Number/locale handling is where these apps actually bleed |
| **Unit answer quality** | "3 min × 15 mph now returns 0.75 mi rather than 1,207 m"; better imperial/time formatting | Users judge the engine by whether the answer *looks* natural |
| **Integrations** | CLI, macOS text services, Shortcuts, URL schemes, Alfred workflow | The agent/workflow surface (we shipped the CLI) |
| **Niche calculators** | Workdays (`Aug 14 + 3 workdays`), timecode (`01:02:03 + 01:09:54`), Unix time, PPI/DPI, loan & ROI functions, crypto | Cheap add-ons that win specific users |
| **Not features at all** | Numi 3.19 → 3.32 is almost entirely fixes/compat (Mojave→Ventura, Arm64, crash fixes) | Once the feature set saturates, a solo app spends years on maintenance |

Two contrasting strategies: Soulver keeps expanding (v4 added live data, agent CLI,
"Soulver Studio"), Numi froze and maintains. Tallynote's differentiators —
free, offline, five platforms, scriptable — are strategy, not features. Don't
out-feature Soulver on live data; out-ship it on the surfaces it refuses.

## Inferences

1. **The maths surface is already saturated.** Both apps' recent work is UI,
   locale correctness and input speed. New operators add little; ergonomics add a lot.
2. **Totals are a trust feature.** Soulver explicitly had to make totals ignore
   variables and references — the same trap we already avoid. Adding an explicit
   `subtotal` line is the missing half.
3. **Locale is the number-one silent-wrong-answer source.** Measured today:
   `1.003.020` fails to parse (safe), but `9,875` is always read as nine thousand
   eight hundred seventy-five — in a comma-decimal locale that is 9.875. Soulver
   had the mirror-image bug and spent years patching it.
4. **Answer phrasing sells the engine.** `0.75 mi` vs `1,207 m` decides whether the
   app feels smart. Measured today: `3 min * 15 mph` answers `45 min·mph` — a unit
   nobody asked for. Soulver shipped a fix for exactly this shape.
5. **Quick capture beats any new syntax.** Everything else is a feature you use
   once; a global hotkey is used hourly.
6. **Note management is the long game.** Thousands of short notes need search,
   folders and deletion-with-undo, not more operators.

## Shipped since this list was written

Number-format settings (US/EU), unit "ideal form" (`3 min × 15 mph` → 0.75 mi),
search + folders, export Markdown/CSV/text, print to PDF, open / save-a-copy
files, English + 繁體 + 简体, whole-app zoom, workdays and spoken durations
(`today + 3 workdays`, `2h 30m + 45m`), and an installable offline web app.
Still open below: tap-to-insert reference, autocomplete, scrubbing, quick
capture, subtotal as a first-class line.

## Backlog, ranked by evidence

### P0 — small, and every competitor needed it

| Feature | Why now | Effort |
|---|---|---|
| Tap an answer → insert its reference (`line 4`) | Soulver's ⌘L reference mode; our `line N` exists but nothing inserts it | S |
| `subtotal` line keyword | Soulver's subtotal semantics; we have `sum` per section but no run-on subtotal | S |
| Number format settings (decimal separator, thousands, ¥ = JPY/CNY, money dp) | The exact class of bug both apps kept fixing | M |
| Unit "ideal form": multiply rates → the natural unit (`3 min × 15 mph` currently answers `45 min·mph`) | Soulver shipped a fix for exactly this | M |
| Variable autocomplete (typing `ren` suggests `rent`) | Soulver's escape-to-complete; our variables are invisible to the user otherwise | M |

### P1 — the ones that change daily use

| Feature | Why | Effort |
|---|---|---|
| Quick capture: global hotkey on desktop, Android share-target / text-selection intent | QuickSoulver is Soulver's most-used feature | M |
| Sheet search + folders + delete-with-undo | Soulver 3's headline work; we have neither search nor folders | M |
| Scrubbable numbers (drag a number to see answers move) | Signature Soulver interaction, no engine work | M |
| Workdays (`today + 3 workdays`) and timecode (`01:02:03 + 01:09:54`) | Cheap, concrete, already half-supported | S |
| Export Markdown / CSV / print | Soulver exports PDF/HTML; ours is a text tool that cannot leave the app | M |

### P2 — worth having, not urgent

- Custom units (`1 watermelon = 20 lb`) and a per-sheet definition block
- Financial functions: loan payment, ROI, `$900 at $30/hour`
- Cryptocurrency rates (needs network → optional, cached like fiat)
- PPI/DPI conversions (designer niche; Soulver 3.16)
- MCP server wrapping the CLI (see [agents.md](agents.md))

### Explicitly not doing

- Cloud sync / accounts (breaks the offline promise; Soulver's own sync generates support load)
- Wolfram|Alpha, stocks, weather (network features that make answers non-deterministic)
- Spotlight / Touch Bar / Shortcuts / Alfred (single-platform integrations; our win is being everywhere)
- More operators for their own sake

## The one-line verdict

Copy their **ergonomics and locale correctness**, copy their **subtotal
semantics**, skip their **live data and platform lock-in**, and keep the
offline + CLI angle they cannot follow.
