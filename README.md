# Tallynote

**The notepad that adds up.** Every line you type is a calculation; the answer sits on the right, aligned by its decimal point. Notes, drafts and totals live in the same page.

Offline first: nothing is computed in the cloud, and the page works with the network unplugged.

**[Open the web app](https://kinfxhk.github.io/tallynote/)** · **[Download the Android APK](https://github.com/Kinfxhk/tallynote/releases/latest)**

<img src="docs/android-formatting.png" width="300" alt="Tallynote on Android: a draft line, a bold line, and answers aligned on the decimal point">

```
rent = 2500                    →  2,500
food = 400                     →  400
rent + food                    →  2,900

# Trip to Tokyo
flights = 4,280                →  4,280
hotel 3 nights × 850           →  2,550
total of #trip                 →  6,830

100 USD in HKD                 →  HK$780.00
5 kg + 3 lb                    →  6.36077711 kg
25% off 159.99 + 10% tax       →  131.99175
9 is to 16 as 27 is to what    →  48
today + 2 weeks                →  13 November 2026
3pm HKT in New York            →  3:00 AM
6+3x30                         →  96
30乘3                          →  90
```

## What it does

**Calculating**
- Line-by-line answers; a broken line never breaks the page
- Variables (`rent = 2500`), references (`prev`, `line 3`), `sum` / `average` / `count` per section
- Percentages in plain words: `15% of 300`, `25% off 159.99`, `20 is what % of 80`, `5% of what is 150`
- Units (length, mass, area, volume, speed, time, data, angle, temperature); mixed units convert on the fly
- Currency with daily ECB rates, cached for offline use
- Dates, durations and time zones; `if … then … else`; rule of three; compound interest
- Functions in any shape people type them: `sin 30 deg`, `sin30deg`, `max(1, 9, 4)`, `round 3.14159 2`, `pi`

**Totals that suit a balance sheet**

```
# Assets
cash 500,000                 →  500,000
stocks 300,000               →  300,000
sum                          →  800,000

# Liabilities
mortgage -500,000            →  -500,000
cards -20,000                →  -20,000
sum                          →  -520,000

合共                          →  280,000
```

`grand total` / `合共` / `總共` adds every individual line above it — never the subtotals — and groups by unit when dimensions differ. Lines labelled *Total* / *Net* / *合計* are treated as summaries, so nothing is counted twice.

**Reading real-world notes**
- `Topstep: −$10,408.52` — the label stays out of the maths, the unicode minus keeps its sign, money keeps its cents
- `// any line` becomes a draft: greyed, not calculated
- `**bold**`, `_italic_`, `~~strike~~`, `__underline__`, `{red}colour{/}` — select text and use the small format bar; markers are plain text, so the file stays portable and the maths still works

**Workspace**
- Folders in the sidebar, with an unfiled group for everything else
- Search across titles and note bodies
- Long-press a sheet to move it or delete it; long-press a folder to rename or delete it (deleting a folder keeps its sheets)

**Answers you can trust**
- Press the chevron beside a complex answer to see every step:

```
(2.5+7.5)*1.11/10-15^2
    2.5 + 7.5 = 10
    10 * 1.11 = 11.1
    11.1 / 10 = 1.11
    15 ^ 2 = 225
    1.11 - 225 = -223.89
```

- When a line is ambiguous the app shows nothing rather than a guess (an uppercase `X` is not a times sign)

## How it compares

Honest notes: Soulver has integrations this project deliberately does not (Wolfram|Alpha, stocks, weather); Numi's prose parsing is far more mature. Tallynote's edge is being free, open source, offline, and on five surfaces at once.

| | **Tallynote** | Soulver 4 | Numi 3 | Notepad Calculator |
|---|---|---|---|---|
| Platforms | macOS, Windows, Linux, Android, Web | macOS, iPad, iPhone | macOS, Windows | Web |
| Price | Free (MIT) | $59 one-time | Freemium, ~$20–30 | Free |
| Open source | ✅ MIT | ❌ | ✅ source on GitHub | ✅ |
| Works offline | ✅ built-in rates + cache | ✅ except live data | ✅ | ⚠️ needs a server |
| Natural-language maths | ✅ plus Chinese operators (乘/除/加/減) | ✅ best in class | ✅ | ✅ |
| Units & currency | ✅ ~150 units, daily ECB rates | ✅ 180+ units, live prices | ✅ | ✅ basic |
| Variables & line references | ✅ | ✅ | ✅ | ✅ |
| Dates & time zones | ✅ | ✅ | ✅ | ⚠️ limited |
| Section subtotals & tags | ✅ `sum`, `total of #tag` | ✅ | ⚠️ `sum` only | ❌ |
| Whole-sheet grand total | ✅ unit-aware | ✅ | ⚠️ | ❌ |
| Step-by-step breakdown | ✅ | ❌ | ❌ | ❌ |
| Inline bold / italic / colour | ✅ markers | ✅ rich text | ⚠️ limited | ❌ |
| CLI / scripting | ❌ | ✅ | ✅ numi-cli | ❌ |
| Wolfram, stocks, weather | ❌ by design | ✅ | ⚠️ | ❌ |

## From the command line

The engine is pure Dart, so it also compiles to a single binary — handy for
scripts and agents:

```bash
dart compile exe bin/tallynote.dart -o build/tallynote
./build/tallynote "5 kg + 3 lb"
./build/tallynote -f budget.txt --json --total --strict
```

`--json` returns `value` (typed) alongside `display`; `--strict` turns off the
human-friendly guessing so a broken line is an error. See
[docs/agents.md](docs/agents.md) for the agent/MCP plan.

## Design principles

1. **Offline is correct.** No network call can change an answer. The only optional fetch is the daily rate refresh, and it can be switched off in Settings.
2. **One meaning, one trigger.** A word belongs to exactly one feature; the precedence ladder and a machine-checked trigger registry keep new features from colliding.
3. **No answer beats a wrong answer.**

Everything that is not typing lives behind the settings sheet: answers column, dark mode, step chevrons, rate refresh. The header keeps two buttons.

## Build

```bash
flutter pub get
flutter test
flutter run -d android     # or linux, windows, chrome
flutter build apk --release
flutter build web --release --base-href /tallynote/ --no-web-resources-cdn
```

Windows needs the **Desktop development with C++** workload:

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --silent `
  --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
flutter build windows --release
```

`--no-web-resources-cdn` matters: CanvasKit is served from the bundle, so opening the page touches no CDN. CI builds Android, Linux, Windows and Web on every push; the Windows
`tallynote.exe` in the release was built and run natively on Windows 11.

## License

MIT. The notepad-calculator idea belongs to [Soulver](https://soulver.app) and [Numi](https://numi.app); Tallynote is an independent implementation that borrows the idea, not the code.
