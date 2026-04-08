# Data Storage

## Persisted Tables

These tables are written to the HDB at end-of-day by the WDB process and are queryable across all historical dates.

| Table | Key columns | Schema summary | Retention |
|-------|------------|----------------|-----------|
| `trade` | `time`, `sym`, `venue` | Raw trades from all venues: `time`, `sym`, `venue`, `price`, `size`, `side`, `venue_sym`, `seq` | All dates; partitioned by date, `p#` on `sym` |
| `quote` | `time`, `sym`, `venue` | Top-of-book snapshots: `time`, `sym`, `venue`, `bid`, `ask`, `bsize`, `asize`, `venue_sym` | All dates; partitioned by date, `p#` on `sym` |

Both tables are append-only streams published from the Python feed handlers through the tickerplant. The WDB accumulates intraday rows in temporary storage (`$KDBWDB`), sorts by `time` and applies `p#sym` at EOD, then moves the partition to the HDB (`$KDBHDB`).

## Intraday-Only Tables

These tables are **not** written to the HDB. They exist only in the RDB and are rebuilt from live data each day. They appear in the tickerplant schema so that processes can subscribe to them, but they are excluded from the WDB and RDB writedown via `ignorelist`.

| Table | Description | Why not persisted |
|-------|-------------|-------------------|
| `lastprice` | Per-venue consolidated snapshot: last known `bid`, `ask`, `mid`, and `price` for each `sym`+`venue` pair. Keyed on `(sym;venue)`. | Represents current state only; historical snapshots have no query value and would grow unboundedly if saved |
| `consolidatedmid` | Cross-venue aggregated mid price timeseries: `mid`, `n_venues`, `spread_dispersion`, `outlier_flag` per `sym` per publish interval. | Published at high frequency by the `cryptoagg` process; storing the full timeseries is a deliberate future decision — excluded for now to keep HDB footprint minimal |

### Configuration

The ignorelist is set in both the RDB and WDB config so neither process attempts to save these tables:

```q
// appconfig/settings/rdb.q and appconfig/settings/wdb.q
ignorelist:`heartbeat`logmsg`lastprice`consolidatedmid
```
