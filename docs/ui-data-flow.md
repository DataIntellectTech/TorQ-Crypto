# UI Data Flow — kdb+ Functions

This document traces how data flows from the kdb+ backend to the browser UI.

## Architecture Overview

```
Browser
  │  WebSocket /ws  (every 2 s)
  │  GET /api/history
  ▼
UI Server (server.py, port 8888)
  │  pykx IPC
  ▼
Gateway (port KDBBASEPORT+7)
  │  .gw.syncexec → forwards to cryptoagg or rdb
  ├──▶ cryptoagg  ─── getconsolidated[]
  └──▶ rdb        ─── ohlc[]
```

---

## 1. Live Order Book (WebSocket)

**Trigger:** Every 2 seconds, `server.py` calls the gateway directly.

**Python call (`server.py`):**
```python
conn("getconsolidated", kx.SymbolAtom("`"))
```

**Gateway function (`code/cryptofunctions/cryptolib.q`):**
```q
getconsolidated:{[syms]
  h:.servers.gethandlebytype[`cryptoagg;`any];
  .[h;(`.cryptoagg.getconsolidated;syms);{...}]
 }
```
- Resolves a handle to the `cryptoagg` process via TorQ server discovery.
- Forwards the call synchronously to `.cryptoagg.getconsolidated`.

**Aggregation function (`code/processes/cryptoagg.q`):**
```q
getconsolidated:{[syms]
  r:$[syms~`; consolidated;
      select from consolidated where sym in ...];
  0!r
 }
```
- Returns the in-memory `consolidated` keyed table (unkeyed via `0!`).
- `syms:`` returns all symbols; a symbol list filters to those symbols.

**`consolidated` table schema:**

| Column | Type | Description |
|---|---|---|
| `sym` | symbol | Canonical symbol (e.g. `` `BTC-USD ``) |
| `update_time` | timestamp | Time of last consolidation |
| `consolidated_bid` | float | Best bid across all venues |
| `consolidated_ask` | float | Best ask across all venues |
| `consolidated_mid` | float | `(consolidated_bid + consolidated_ask) / 2` |
| `venue_count` | long | Number of contributing venues |
| `spread_dispersion` | float | Mid price spread across venues (bps) |
| `outlier_flag` | boolean | True if `spread_dispersion > outlierthreshold` |
| `venue_bids` | float list | Per-venue best bids |
| `venue_asks` | float list | Per-venue best asks |
| `venue_names` | symbol list | Venue names matching the bid/ask lists |

**How `consolidated` is maintained (`cryptoagg.q`):**
```q
consolidate:{[s]
  cutoff:.proc.cp[]-stalenesswindow;          // default: 30 seconds
  rows:select from lastbook where sym=s, time>=cutoff;
  cbid:max rows`bid;
  cask:min rows`ask;
  cmid:(cbid+cask)%2;
  disp:10000*(max[mids]-min[mids])%min[mids]; // bps dispersion
  `.cryptoagg.consolidated upsert (s;...outlier_flag:disp>outlierthreshold...)
 }
```
- Called on every `exchange_top` tick received from the tickerplant.
- Entries older than `stalenesswindow` (default 30 s) are excluded.
- `outlier_flag` is set when dispersion exceeds `outlierthreshold` (default 50 bps).

---

## 2. Price History Chart (REST)

**Trigger:** On page load and on symbol change, the browser calls `GET /api/history?sym=BTC-USD&mins=30`.

**Python call (`server.py`):**
```python
conn(".gw.syncexec", "ohlc",
     kx.toq({"sym": kx.SymbolAtom(sym), "usetrade": kx.BooleanAtom(True)}),
     kx.SymbolAtom("rdb"))
```
- Uses `.gw.syncexec` to route the `ohlc` function call to the `rdb` process.

**`ohlc` function (`code/cryptofunctions/cryptolib.q`):**
```q
ohlc:{[dict]
  // dict keys: sym (required), date, exchanges, quote, byexchange, usetrade
  // usetrade:1b → query the trade table on price column
  if[d`usetrade;
    :select openPrice:first price, closePrice:last price,
             highPrice:max price,  lowPrice:min price
     by date, sym
     from trade where date in d`date, sym in d`sym
  ];
  // usetrade:0b → query exchange_top on bid/ask columns
  ...
 }
```

**Returns (when `usetrade:1b`):**

| Column | Type | Description |
|---|---|---|
| `date` | date | Trade date |
| `sym` | symbol | Symbol |
| `openPrice` | float | First trade price in period |
| `closePrice` | float | Last trade price in period |
| `highPrice` | float | Maximum trade price |
| `lowPrice` | float | Minimum trade price |

The UI uses `closePrice` to plot the mid price chart.

---

## Configuration

| Variable | Default | Description |
|---|---|---|
| `.cryptoagg.stalenesswindow` | `0D00:00:30` | Max age of book entries used in consolidation |
| `.cryptoagg.outlierthreshold` | `50f` | Dispersion (bps) above which `outlier_flag` is set |
| `UI_PORT` | `8888` | HTTP and WebSocket server port |
| `KDB_GATEWAY_HOST` | `localhost` | Gateway hostname |
| `KDB_GATEWAY_PORT` | `KDBBASEPORT+7` | Gateway port |
