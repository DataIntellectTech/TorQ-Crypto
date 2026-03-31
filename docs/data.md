# Data Capture

### Feed Handlers

Three Python WebSocket feed processes collect real-time cryptocurrency data:

- **Binance** — `{sym}@trade` and `{sym}@depth5@100ms` streams
- **Kraken** — `trade` and `book` (depth 10) subscriptions
- **Coinbase** — `market_trades` and `level2` subscriptions (requires API credentials)

All feeds connect via WebSocket, publish normalised rows to kdb+ via IPC (pykx),
and reconnect with exponential backoff on failure.  Gaps are filled from each
exchange's REST API on reconnect.

### Tables

#### exchange (preserved — L2 order book, all exchanges)

    c           | t f a
    ------------| -----
    time        | p
    sym         | s   g
    exchangeTime| p
    exchange    | s
    bid         | F
    bidSize     | F
    ask         | F
    askSize     | F

#### exchange_top (preserved — top-of-book per exchange)

    c           | t f a
    ------------| -----
    time        | p
    sym         | s   g
    exchangeTime| p
    exchange    | s
    bid         | f
    bidSize     | f
    ask         | f
    askSize     | f

#### trade (new — append-only trade stream, time-partitioned in HDB)

    c         | t f a
    ----------| -----
    time      | p
    sym       | s   g
    exchange  | s
    price     | f
    size      | f
    side      | s
    venue_sym | s

`side` is `buy` or `sell`.  `venue_sym` is the original exchange symbol (e.g. `btcusdt`).

#### symboldiscovery (runtime, in-memory only — not persisted to HDB)

Populated at startup by the Python feed manager discovery process.

    c                | t
    -----------------| -
    canonical_symbol | s
    venue            | s
    venue_symbol     | s
    base             | s
    quote            | s
    instrument_type  | s
    tick_size        | f
    mapping_verified | b

`mapping_verified=false` rows indicate the instrument's quote currency could not
be reliably determined.  The original venue symbol is used as the canonical symbol
for these rows and is displayed in the UI with a visual indicator.

#### cryptoagg in-memory tables

The `cryptoagg1` process maintains three keyed in-memory tables that are NOT
persisted to the HDB.  They are queried via gateway functions.

**lasttrade** — keyed by `sym`, `exchange`

    sym      | s
    exchange | s
    time     | p
    price    | f
    size     | f

**lastbook** — keyed by `sym`, `exchange`

    sym      | s
    exchange | s
    time     | p
    bid      | f
    bidSize  | f
    ask      | f
    askSize  | f

**consolidated** — keyed by `sym`

    sym                | s
    update_time        | p
    consolidated_bid   | f   (max bid across venues)
    consolidated_ask   | f   (min ask across venues)
    consolidated_mid   | f   (midpoint of above)
    venue_count        | j   (number of contributing venues)
    spread_dispersion  | f   (bps: (max_mid - min_mid) / min_mid * 10000)
    outlier_flag       | b   (true if spread_dispersion > outlierthreshold)
    venue_bids         | f   (list, one per contributing venue)
    venue_asks         | f   (list, one per contributing venue)
    venue_names        | s   (list, exchange names matching venue_bids/asks)

### Recovery

- **TP log replay**: `cryptoagg1` subscribes with log replay enabled, so it
  rebuilds in-memory state automatically on restart.
- **REST backfill**: each Python feed queries kdb+ for the most recent trade
  timestamp on reconnect and backfills any gap via the exchange REST API.
