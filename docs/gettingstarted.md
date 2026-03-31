# Getting Started

### Requirements

- kdb+ 4.1 (free 32-bit or licensed)
- Python 3.11+ with packages listed in `code/processes/feedhandler/requirements.txt`
- `nc` (netcat) — used by `start_all.sh` to poll discovery readiness

### Installation

1.  Download and install kdb+ 4.1 from [Kx Systems](http://kx.com)

2.  Download the main TorQ codebase from
    [here](https://github.com/DataIntellectTech/TorQ)

3.  Download TorQ Crypto from
    [here](https://github.com/DataIntellectTech/TorQ-Crypto)

4.  Place the Crypto package over the top of the main TorQ package

###### Example Linux installation:

    ~/crypto:$ git clone https://github.com/DataIntellectTech/TorQ.git
    ~/crypto:$ git clone https://github.com/DataIntellectTech/TorQ-Crypto.git
    ~/crypto:$ mkdir deploy
    ~/crypto:$ cp -r TorQ/* deploy/
    ~/crypto:$ cp -r TorQ-Crypto/* deploy/

5.  Install Python dependencies:

    cd deploy/code/processes/feedhandler
    python -m venv ../../../.venv
    source ../../../.venv/bin/activate
    pip install -r requirements.txt

### Python feed configuration

Before starting, edit `setenv.sh` and set the following environment variables:

| Variable | Description |
|---|---|
| `COINBASE_API_KEY` | Coinbase Advanced Trade API key (required) |
| `COINBASE_API_SECRET` | Coinbase Advanced Trade API secret (required) |
| `BINANCE_SYMBOLS` | Canonical symbols for Binance, e.g. `BTC-USDT,ETH-USDT` |
| `KRAKEN_SYMBOLS` | Canonical symbols for Kraken, e.g. `BTC-USD,ETH-USD` |
| `COINBASE_SYMBOLS` | Canonical symbols for Coinbase, e.g. `BTC-USD,ETH-USD` |

Obtain Coinbase credentials from your Coinbase Advanced Trade dashboard.
**Never commit real credentials to source control.**

### Instrument mapping

BTC-USD (FIAT USD) and BTC-USDT (Tether stablecoin) are **different instruments**
and must not be conflated.  The canonical symbol scheme used throughout the system is:

- Venues quoting against genuine FIAT USD → canonical uses `-USD` suffix (e.g. `BTC-USD`)
- Venues quoting against USDT (Tether) → canonical uses `-USDT` suffix (e.g. `BTC-USDT`)

Consequently:
- Binance `BTCUSDT` → canonical `BTC-USDT`  (Tether)
- Kraken `XBT/USD` → canonical `BTC-USD`    (FIAT)
- Coinbase `BTC-USD` → canonical `BTC-USD`  (FIAT)

The consolidated order book keeps `BTC-USD` (Kraken + Coinbase) and `BTC-USDT`
(Binance) as **separate rows**.

Instruments whose quote currency cannot be reliably determined are passed through
with `mapping_verified=false`.  The original venue symbol is preserved and displayed
in the UI in a muted colour with a tooltip.

### Starting the system

The easiest way to start everything is:

    cd deploy
    bash start_all.sh

This will:
1. Start the full TorQ kdb+ stack
2. Wait for the discovery process to be ready (up to 60 s)
3. Start the Python feed manager in the background

To start the kdb+ stack and Python feeds separately:

    # kdb+ only
    . setenv.sh && . torq.sh start all

    # Python feeds only (after kdb+ is running)
    bash start_feeds.sh

### Accessing the UI

Once the system is running, open:

    http://localhost:8888

The UI shows a live price grid (Binance / Kraken / Coinbase per row) and a
30-minute consolidated mid-price chart.  Data updates every 2 seconds via WebSocket.

### Process list

| Process | Port | Description |
|---|---|---|
| discovery1 | KDBBASEPORT+1 | Service discovery |
| tickerplant1 | KDBBASEPORT | Real-time data bus |
| rdb1 | KDBBASEPORT+2 | Real-time in-memory database |
| hdb1, hdb2 | KDBBASEPORT+3,4 | Historical database |
| wdb1 | KDBBASEPORT+5 | Write-down buffer |
| sort1 | KDBBASEPORT+6 | EOD sort process |
| gateway1 | KDBBASEPORT+7 | Query gateway |
| monitor1 | KDBBASEPORT+9 | Process monitor |
| housekeeping1 | KDBBASEPORT+10 | Log housekeeping |
| reporter1 | KDBBASEPORT+11 | Scheduled reports |
| chainedtp1 | KDBBASEPORT+12 | Chained tickerplant |
| sortslave1,2 | KDBBASEPORT+13,14 | Sort slaves |
| **pythonfeed1** | **KDBBASEPORT+15** | **kdb+ receiver for Python feeds** |
| **cryptoagg1** | **KDBBASEPORT+20** | **Real-time aggregation process** |

### TorQ Debug Mode

    . torq.sh stop rdb1
    . torq.sh debug rdb1
    q)tables[]!count each `. tables[]
    exchange    | 50
    exchange_top| 50
    trade       | 200

### File structure

    |-- start_all.sh          <- start entire system
    |-- start_feeds.sh        <- start Python feeds only
    |-- setenv.sh             <- environment variables (edit before starting)
    |-- database.q            <- table schema definitions
    |-- appconfig/
    |   |-- process.csv
    |   |-- symconfig.csv     <- canonical symbol enable/disable per venue
    |   |-- symmap.csv        <- canonical <-> venue symbol mapping
    |   |-- dependency.csv
    |   `-- settings/
    |       |-- pythonfeed.q
    |       |-- cryptoagg.q
    |       `-- gateway.q
    |-- code/
    |   |-- cryptofeed/
    |   |   `-- cryptofeed.q  <- CSV loader for symbol tables
    |   |-- cryptofunctions/
    |   |   `-- cryptolib.q   <- OHLC, orderbook, arbitrage, getconsolidated
    |   |-- processes/
    |   |   |-- pythonfeed.q  <- kdb+ receiver process
    |   |   `-- cryptoagg.q   <- real-time aggregation process
    |   |-- processes/feedhandler/
    |   |   |-- feed_manager.py
    |   |   |-- discovery.py
    |   |   |-- symmap.py
    |   |   |-- binance_feed.py
    |   |   |-- kraken_feed.py
    |   |   |-- coinbase_feed.py
    |   |   `-- requirements.txt
    |   `-- ui/
    |       |-- server.py
    |       `-- static/index.html
    `-- docs/
