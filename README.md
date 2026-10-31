# Tallynote

**The notepad that adds up.** Every line you type is a calculation; the answer sits on the right, aligned by its decimal point. Notes, drafts and totals live in the same page.

Offline first: nothing is computed in the cloud, and the page works with the network unplugged.

**[Open the web app](https://kinfxhk.github.io/tallynote/)** · **[All downloads](https://github.com/Kinfxhk/tallynote/releases/latest)**

The web app is installable: in Chrome or Edge, **Install Tallynote** puts it in the Dock and it
opens with the network unplugged. Notes are stored on the device, and closing the tab never loses
the last line — the status bar shows *editing…* until the write lands.

Support: **[Buy Me a Coffee](https://buymeacoffee.com/kinfxhk)**

| Platform | Download | Notes |
|---|---|---|
| Android | `app-release.apk` | signed with the release key |
| Windows | `Tallynote-<version>-setup.exe` | per-user install, Start-menu shortcut, uninstaller |
| Windows (portable) | `tallynote-windows.zip` | unzip and run `tallynote.exe` |
| Linux | `tallynote_<version>_amd64.deb` | installs to `/usr/lib/tallynote` with a desktop entry |
| Linux (portable) | `tallynote-linux.tar.gz` | unpack and run `bundle/tallynote` |
| Web | [kinfxhk.github.io/tallynote](https://kinfxhk.github.io/tallynote/) | deployed from `main` |
| macOS / iOS | not yet | needs a full Xcode install |

<img src="docs/android-formatting.png" width="300" alt="Tallynote on Android: a draft line, a bold line, and answers aligned on the decimal point">

```
rent = 2500                    →  2,500
food = 400                     →  400
rent + food                    →  2,900

# Trip to Tokyo
flights = 4,280 #trip           →  4,280
hotel 3 × 850 #trip             →  2,550
total of #trip                  →  6,830

100 USD in HKD                 →  HK$780.00
5 kg + 3 lb                    →  6.36077711 kg
25% off 159.99 + 10% tax       →  131.99175
9 is to 16 as 27 is to what    →  48
2026-10-30 + 2 weeks           →  13 November 2026
3pm HKT in New York            →  30 October 2026 at 3:00 AM
6+3x30                         →  96
30乘3                          →  90
```

## What it does

**Calculating**
- Line-by-line answers; a broken line never breaks the page. A blank line is spacing, not a section break: `total` still counts the lines above it
- Variables (`rent = 2500`), references (`prev`, `line 3`), `sum` / `average` / `count` per section
- Percentages in plain words: `15% of 300`, `25% off 159.99`, `20 is what % of 80`, `5% of what is 150`,
  and Chinese retail forms: `打八折 100` → 80, `八五折 200` → 170, `分帳 3 人 380` → 126.666666667
- Remainders: `7 % 2` or `10 mod 3` → 1 (a `%` with a number after it is never a percentage)
- Scale words: `1.5 million + 200 thousand` → 1,700,000; rates annualise: `$30/day is what per year` → $10,950.00
- Units (length, mass, area, volume, speed, time, data, angle, temperature); mixed units convert on the fly
- Currency with daily ECB rates, cached for offline use
- Dates, durations and time zones: `today + 3 workdays`, `30 days from today`, `2026-10-31 - 2026-01-01` → 303 days, `3pm HKT in New York`
- Spoken durations: `2h 30m + 45m` → 3 h 15 min, `3 hours 20 minutes in minutes` → 200 min
- `if … then … else`; rule of three; compound interest; scientific notation (`1e3`)
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

`total` / `sum` can be used inside an expression too (`total * 7.8 + 16000`), and money plus a plain number is read in that currency.

`grand total` / `合共` / `總共` adds every individual line above it — never the subtotals — and groups by unit when dimensions differ. Lines labelled *Total* / *Net* / *合計* are treated as summaries, so nothing is counted twice.

**Reading real-world notes**
- `Topstep: −$10,408.52` — the label stays out of the maths, the unicode minus keeps its sign, money keeps its cents
- `// any line` becomes a draft: greyed, not calculated
- `**bold**`, `_italic_`, `~~strike~~`, `__underline__`, `{red}colour{/}` — select text and use the small format bar; markers are plain text, so the file stays portable and the maths still works

**Looking things up**
- **Settings → Cheat sheet** (計算表) lists every word you can type — the symbols, the Chinese
  forms (`加` `減` `乘` `除`, `的`, `百分之幾`), totals, units, dates, durations — each with the
  answer it really gives. Every row on that page is checked against the engine by a test.

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

MIT. Tallynote is an independent implementation of the notepad-calculator idea, and is not affiliated with any commercial notepad calculator.
