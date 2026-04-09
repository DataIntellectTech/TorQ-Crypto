// Bespoke Gateway config — TorQ Crypto

\d .gw
synccallsallowed:1b

// ---------------------------------------------------------------------------
// Connections — gateway needs handles to rdb and hdb to route queries
// ---------------------------------------------------------------------------

\d .servers
CONNECTIONS:`rdb`hdb

// ---------------------------------------------------------------------------
// .crypto.* — public query API, callable by external clients (e.g. UI server)
//
// Each function routes synchronously to the appropriate backend process.
// The analytical functions (ohlc, topofbook, arbitrage) call .crypto.* on the
// backend, which is defined in code/cryptofunctions/cryptolib.q and loaded
// on rdb/hdb via -parentproctype cryptofunctions.
//
// Routing:
//   getconsolidated / gethistory — always rdb (intraday-only tables)
//   ohlc / topofbook / arbitrage — rdb by default; pass target:`hdb in the
//                                   dict for historical queries
// ---------------------------------------------------------------------------

\d .crypto

// Live consolidated price snapshot.
// syms: ` for all instruments, or a symbol list e.g. `BTC-USD`ETH-USD
getconsolidated:{[syms]
  h:.servers.gethandlebytype[`rdb;`any];
  if[null h; '"no rdb available"];
  h(`.crypto.getconsolidated;syms)
  };

// Consolidated mid price history from the RDB (last N minutes).
// sym:  symbol atom e.g. `BTC-USD
// nmin: integer look-back window in minutes e.g. 30
gethistory:{[sym;nmin]
  h:.servers.gethandlebytype[`rdb;`any];
  if[null h; '"no rdb available"];
  h(`.crypto.gethistory;sym;nmin)
  };

// OHLC of trade prices by date+sym, optionally by venue.
// Dict keys: sym (required), date, venues, byvenue, target (`rdb or `hdb)
ohlc:{[d]
  target:$[`target in key d;d`target;`rdb];
  h:.servers.gethandlebytype[target;`any];
  if[null h; '"no ",string[target]," available"];
  h(`.crypto.ohlc;d)
  };

// Per-venue top-of-book snapshots bucketed over a time range.
// Dict keys: sym (required), starttime, endtime, venues, bucket, target
topofbook:{[d]
  target:$[`target in key d;d`target;`rdb];
  h:.servers.gethandlebytype[target;`any];
  if[null h; '"no ",string[target]," available"];
  h(`.crypto.topofbook;d)
  };

// Top-of-book with cross-venue profit and arbitrage indicator.
// Dict keys: same as topofbook
arbitrage:{[d]
  target:$[`target in key d;d`target;`rdb];
  h:.servers.gethandlebytype[target;`any];
  if[null h; '"no ",string[target]," available"];
  h(`.crypto.arbitrage;d)
  };

// Last N trades for a given sym (time, venue, price, size, side).
gettrades:{[sym;n]
  h:.servers.gethandlebytype[`rdb;`any];
  if[null h; '"no rdb available"];
  h({[s;n] select[neg n] time,venue,price,size,side from `trade where sym=s};sym;n)
  };

\d .
