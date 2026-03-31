# TorQ-Crypto Gateway Functions

The following functions are loaded into rdb, hdb, and gateway processes via the
`cryptofunctions` parent process type.  Use `.gw.syncexec` to route queries
through the gateway.

---

### OHLC Function

Returns OHLC quote data for specified dates with the option to break down by exchange.

|   Key         | Mandatory |  Type      | Default           | Example              | Description |
|:------------- |:---------:|:---------- |:----------------- |:-------------------- |:----------- |
| `sym`         | **yes**   | -11 11h    | —                 | `` `BTC-USD ``       | Symbol(s) |
| `date`        | no        | -14 14h    | Most recent date  | `2024.01.01`         | Date(s) |
| `exchanges`   | no        | -11 11h    | All               | `` `kraken`coinbase ``| Exchange(s) |
| `quote`       | no        | -11 11h    | bid & ask         | `` `bid ``           | Quote side(s) |
| `byexchange`  | no        | -1h        | `0b`              | `1b`                 | Breakdown by exchange |
| `usetrade`    | no        | -1h        | `0b`              | `1b`                 | Query `trade` table instead of `exchange_top` |

When `usetrade=1b`, the function queries the `trade` table and returns
`openPrice`, `closePrice`, `highPrice`, `lowPrice` columns instead of bid/ask
OHLC.  This is useful for chart-style data.

###### Example — bid OHLC from exchange_top:

    q).gw.syncexec["ohlc";`sym`exchanges`quote!(`BTC-USD;`kraken`coinbase;`bid);`rdb`hdb]

###### Example — trade OHLC (new):

    q).gw.syncexec["ohlc";`sym`usetrade!(`BTC-USD;1b);`rdb]

---

### Orderbook Function

Returns level 2 orderbook at a specific point in time.

|   Key        | Mandatory |  Type   | Default                    | Example |
|:------------ |:---------:|:------- |:-------------------------- |:------- |
| `sym`        | **yes**   | -11h    | —                          | `` `BTC-USD `` |
| `exchanges`  | no        | -11 11h | All                        | `` `kraken `` |
| `timestamp`  | no        | -12h    | Last available             | `2024.01.01D15:00` |
| `window`     | no        | -18h    | 60 seconds                 | `00:01:00` |

---

### Topofbook Function

Returns top of book bucketed by time interval.

|   Key        | Mandatory |  Type   | Default              | Example |
|:------------ |:---------:|:------- |:-------------------- |:------- |
| `sym`        | **yes**   | -11h    | —                    | `` `BTC-USD `` |
| `exchanges`  | no        | -11 11h | All                  | `` `kraken `` |
| `starttime`  | no        | -12h    | Start of last date   | `2024.01.01D09:00` |
| `endtime`    | no        | -12h    | End of last date     | `2024.01.01D17:00` |
| `bucket`     | no        | -18h    | 60 seconds           | `00:05:00` |

---

### Arbitrage Function

Returns topofbook with additional `profit` and `arbitrage` columns.

Same parameters as `topofbook`.  Profit reflects the maximum theoretical
cross-venue arbitrage opportunity; it does **not** account for exchange fees,
transaction costs, or request latency.

---

### getconsolidated Function (new)

Returns the consolidated order book from the `cryptoagg1` process.
Always returns a simple table (type 98h) — never a keyed table.

|   Argument | Type                        | Description |
|:---------- |:--------------------------- |:----------- |
| `syms`     | `` ` ``, symbol, or list    | `` ` `` for all; `` `BTC-USD `` for one; `` `BTC-USD`ETH-USD `` for many |

Returns columns: `sym`, `update_time`, `consolidated_bid`, `consolidated_ask`,
`consolidated_mid`, `venue_count`, `spread_dispersion`, `outlier_flag`,
`venue_bids` (list), `venue_asks` (list), `venue_names` (list).

###### Example — all symbols:

    q)h:.servers.gethandlebytype[`gateway;`any]
    q)h(`.gw.syncexec;"getconsolidated";enlist `;`cryptoagg)

###### Example — single symbol:

    q)h(`.gw.syncexec;"getconsolidated";`BTC-USD;`cryptoagg)

The function can also be called directly from any process that has `cryptolib.q`
loaded:

    q)getconsolidated[`]
    q)getconsolidated[`BTC-USD]
    q)getconsolidated[`BTC-USD`ETH-USD]

`outlier_flag=1b` indicates that the spread dispersion across venues exceeds
the configured `outlierthreshold` (default 50 bps).

---

### Additional Notes

- All functions are loaded on rdb, hdb, and gateway processes via the `cryptofunctions` parent type
- `getconsolidated` routes its query to `cryptoagg1` via server discovery
- The UI calls `getconsolidated[` \`]` every 2 seconds for live price grid updates
