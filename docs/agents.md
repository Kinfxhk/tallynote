# Using Tallynote from an agent

**Short answer: ship the CLI first, add MCP as a thin wrapper on the same
engine, skip the TUI.**

A TUI is for humans; agents already have a shell. An MCP server is a protocol
wrapper around a function call — worth adding once the function itself is
stable and structured. The CLI is the smallest thing that works everywhere
(Hermes, Claude Code, Codex, Cursor, cron, a bash script) and needs no server,
no port, no handshake.

## 1. CLI (built)

The engine is pure Dart, so it compiles to a single binary with no runtime:

```bash
dart compile exe bin/tallynote.dart -o build/tallynote
./build/tallynote "5 kg + 3 lb"          # 5 kg + 3 lb → 6.36077711 kg
./build/tallynote "2000+3000" --json     # one JSON object per line
./build/tallynote -f budget.txt --json --total
echo "100 USD in HKD" | ./build/tallynote --json
```

| Flag | Meaning |
|---|---|
| `-e, --eval <text>` | evaluate one expression |
| `-f, --file <path>` | evaluate a note file (`-` for stdin) |
| `-j, --json` | structured output |
| `-s, --steps` | include the breakdown |
| `--total` | append a grand total of all lines |
| `--dp <n>` | decimal places for plain numbers |
| `--strict` | no forgiveness: a line that cannot be parsed is an error, exit 1 |

### Why `--json` matters

An agent should never parse a formatted string. Each line comes back as:

```json
{"line":1,"input":"5 kg + 3 lb","display":"6.36077711 kg","error":null,
 "value":{"type":"number","value":6.36077711,"unit":"kg"}}
```

Types: `number`, `money` (with `currency`), `percent`, `date`, `bool`, `list`.
`display` is for humans, `value` is for the agent.

### Why `--strict` matters

In the app, a half-typed line shows the number it can find — pleasant for a
human mid-sentence, dangerous for an agent. `--strict` turns that off:

```bash
$ ./build/tallynote "(1+" --strict --json
{"line":1,"input":"(1+","display":null,"error":"unexpected end of line","value":null}
$ echo $?
1
```

## 2. MCP (next)

Only worth it once agents need discovery rather than a shell. The server is a
~100-line stdio wrapper over the same `SheetEngine`:

```
tools:
  calc(expression, steps?)            -> {display, value, steps}
  eval_sheet(text, total?)            -> [{line, input, display, error, value}]
  convert(value, from, to)            -> {value, unit}
  explain(expression)                 -> [step, ...]
resources:
  tallynote://sheet/{id}              -> the note as plain text
```

Rules that keep it honest:
- **No network** in the server: rates come from the cached table.
- **Same engine**: MCP must not re-implement parsing, or the two answers drift.
- **Deterministic**: same input, same output, no model in the loop.
- Publish it as `tallynote mcp` in the same binary, not a separate package.

## 3. TUI — skip

An interactive full-screen UI helps a human browse sheets. An agent calling
`exec` cannot see it, and a TUI that also accepts commands is a worse CLI.
If a human wants to browse, the app already exists.

## What agents should be told

Paste this into a system prompt or skill:

> Tallynote is a notepad calculator. Call `tallynote --json --strict "<expr>"`
> for a single value, or pipe a whole note with `-f`. Read `value`, never the
> `display` string. Money is `{type:"money", value, currency}`. Sections sum
> with `sum`; whole-note totals use `grand total` / `合共`.
