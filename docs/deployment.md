# Deployment & Operations

Three scripts handle the full lifecycle of a TorQ-Crypto installation.

| Script | Purpose |
|---|---|
| `deploy.sh` | Build a self-contained deployment in `deploy/` |
| `bin/start.sh` | Start kdb+ processes, Python feeds, or both |
| `bin/stop.sh` | Stop kdb+ processes, Python feeds, or both |

---

### Prerequisites

- kdb+ installed and on `PATH`
- Python 3.9+ installed
- A TorQ framework clone (downloaded from [GitHub](https://github.com/AquaQAnalytics/TorQ/releases))

---

### deploy.sh

`deploy.sh` merges the TorQ framework with TorQ-Crypto into the `deploy/` directory and prepares it to run.  It is idempotent — re-running it overlays updated files without removing existing data.

**What it does:**

1. Copies the TorQ framework (`torq.q`, `torq.sh`, `code/`, `config/`, `html/`, `lib/`)
2. Overlays TorQ-Crypto application files (`appconfig/`, `code/`, `database.q`)
3. Creates all required data directories (`logs/`, `hdb/database/`, `wdbhdb/`, `certs/`)
4. Generates a self-contained `deploy/setenv.sh` with all paths set relative to `deploy/`
5. Copies `bin/start.sh` and `bin/stop.sh` into `deploy/bin/`
6. Creates a Python virtual environment at `deploy/.venv/` and installs dependencies

**Usage:**

    bash deploy.sh                           # auto-detects TorQ at ../TorQ
    bash deploy.sh --torq /path/to/TorQ      # explicit TorQ path
    bash deploy.sh --port 8000               # override base port (default: 9000)
    bash deploy.sh --clean                   # remove old framework files before rebuilding

The `--torq` flag is optional if TorQ is cloned alongside TorQ-Crypto:

    ~/crypto$ git clone https://github.com/AquaQAnalytics/TorQ.git
    ~/crypto$ git clone https://github.com/AquaQAnalytics/TorQ-Crypto.git
    ~/crypto$ cd TorQ-Crypto
    ~/crypto/TorQ-Crypto$ bash deploy.sh     # auto-detects ../TorQ

**Resulting layout:**

    deploy/
    ├── torq.q              ← TorQ framework entry point
    ├── torq.sh             ← TorQ process manager
    ├── setenv.sh           ← generated; sets all paths relative to deploy/
    ├── database.q          ← table schema for tickerplant
    ├── bin/
    │   ├── start.sh
    │   └── stop.sh
    ├── appconfig/          ← process.csv, symmap.csv, settings/
    ├── code/               ← TorQ framework + TorQ-Crypto code merged
    ├── config/             ← TorQ base config
    ├── logs/               ← kdb+ and feed manager logs written here
    ├── hdb/database/       ← historical database storage
    ├── wdbhdb/             ← write database scratch space
    └── .venv/              ← Python virtual environment

---

### bin/start.sh

Starts kdb+ processes, the Python feed manager, or both.  Can be run from either the repo root or from inside `deploy/`.

    bin/start.sh [kdb|feeds|all]    # default: all

| Argument | Behaviour |
|---|---|
| `kdb` | Calls `torq.sh start all` to start all `startwithall=1` processes from `process.csv` |
| `feeds` | Starts `feed_manager.py` (Binance, Kraken, OKX) as a background daemon |
| `all` | Starts kdb+, waits 10 s for processes to come up, then starts feeds |

The feed manager is daemonised with `nohup`.  Its PID and log are written to the `logs/` directory:

    logs/feed_manager.pid   ← process ID of the running feed manager
    logs/feed_manager.log   ← stdout/stderr from all three exchange feeds

**Example — full stack start from deploy/:**

    cd deploy/
    bash bin/start.sh all

**Example — start feeds only (kdb+ already running):**

    bash bin/start.sh feeds

---

### bin/stop.sh

Stops kdb+ processes, the Python feed manager, or both.

    bin/stop.sh [kdb|feeds|all]    # default: all

| Argument | Behaviour |
|---|---|
| `kdb` | Calls `torq.sh stop all` for a graceful shutdown of all kdb+ processes |
| `feeds` | Sends SIGTERM to the feed manager; escalates to SIGKILL after 10 s if needed |
| `all` | Stops feeds first, then kdb+ (prevents feeds retrying dead IPC connections) |

**Example — full stack stop:**

    bash bin/stop.sh all

---

### Changing the Base Port

Pass `--port` to `deploy.sh` to set a custom base port.  All process ports in `process.csv` are defined as offsets from `KDBBASEPORT`, so changing one value is sufficient:

    bash deploy.sh --port 8000

The generated `deploy/setenv.sh` also respects the environment variable, so the port can be overridden at start time without re-running the deploy:

    KDBBASEPORT=8000 bash bin/start.sh all

---

### Updating After Code Changes

Re-run `deploy.sh` to sync code changes into the deployment.  Data directories and the Python venv are left untouched:

    bash deploy.sh              # overlays updated files
    bash bin/stop.sh all
    bash bin/start.sh all

Use `--clean` if you also want to remove TorQ framework files and re-copy them (e.g. after a TorQ version upgrade):

    bash deploy.sh --clean --torq /path/to/new-TorQ
