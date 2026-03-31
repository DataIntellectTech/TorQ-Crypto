// test_pythonfeed.q — Unit tests for code/processes/pythonfeed.q
//
// Run from repo root:
//   q tests/test_pythonfeed.q -noprocess
//
// Does NOT require a live TorQ stack.  All TorQ dependencies are mocked inline.

// ---------------------------------------------------------------------------
// Mock TorQ framework dependencies
// ---------------------------------------------------------------------------
.lg.o:{[ctx;msg] -1 "[INFO] ",(string ctx),": ",msg;}
.lg.e:{[ctx;msg] -1 "[ERROR] ",(string ctx),": ",msg;}
.lg.w:{[ctx;msg] -1 "[WARN] ",(string ctx),": ",msg;}

.proc.proctype:`pythonfeed
.proc.procname:`pythonfeed1
.proc.cp:{.z.p}
.proc.cd:{`date$.z.p}
.proc.getconfigfile:{[f] enlist hsym`$getenv[`KDBAPPCONFIG],"/",f}

.servers.CONNECTIONS:enlist `tickerplant
.servers.gethandlebytype:{[t;algo] 0Ni}

.dotz.set:{[handler;fn] @[`.;handler;:;fn]}

.api.add:{[name;pub;desc;param;ret] :()}

// Mock .u.upd — records calls for inspection
.u.upd.calls:()
.u.upd:{[t;x] `.u.upd.calls upsert (enlist`table`rows)!(enlist t;enlist x)}

// Mock trade table (what pythonfeed.maxtime queries)
trade:([]
  time:`timestamp$();
  sym:`symbol$();
  exchange:`symbol$();
  price:`float$();
  size:`float$();
  side:`symbol$();
  venue_sym:`symbol$()
  )

// Seed with one trade row for maxtime tests
trade upsert
  (2024.01.01D12:00:00.000000000;`$"BTC-USDT";`binance;50000f;0.1f;`buy;`btcusdt)

// Mock .crypto.symmap
.crypto.symmap:([]
  canonical_symbol:`symbol$();
  venue:`symbol$();
  venue_symbol:`symbol$()
  )

// ---------------------------------------------------------------------------
// Load the file under test
// ---------------------------------------------------------------------------
\l code/processes/pythonfeed.q

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------
passed:0
failed:0

assert:{[desc;result]
  $[result;
    [passed+:1; -1 "[PASS] ",desc];
    [failed+:1; -1 "[FAIL] ",desc]]
 }

// ---------------------------------------------------------------------------
// Tests: maxtime
// ---------------------------------------------------------------------------

// maxtime returns a timestamp when data exists
mt:.pythonfeed.maxtime[`$"BTC-USDT";`binance]
assert["maxtime returns timestamp type for known sym/exchange";-12h=type mt]
assert["maxtime returns 2024.01.01D12 for seeded row";mt=2024.01.01D12:00:00.000000000]

// maxtime returns 0Np for unknown sym
mt2:.pythonfeed.maxtime[`UNKNOWN;`binance]
assert["maxtime returns null timestamp for unknown sym";null mt2]

// maxtime returns 0Np for unknown exchange
mt3:.pythonfeed.maxtime[`$"BTC-USDT";`unknown]
assert["maxtime returns null timestamp for unknown exchange";null mt3]

// ---------------------------------------------------------------------------
// Tests: upd — trade rows forwarded to .u.upd
// ---------------------------------------------------------------------------

// Reset call log
`.u.upd.calls set ()

// Construct a trade row
traderow:([]
  time:enlist .z.p;
  sym:enlist `$"BTC-USDT";
  exchange:enlist `binance;
  price:enlist 50000f;
  size:enlist 0.1f;
  side:enlist `buy;
  venue_sym:enlist `btcusdt
  )

.pythonfeed.upd[`trade;traderow]
assert["upd forwards trade to .u.upd";0<count .u.upd.calls]
assert["upd passes correct table name";`trade~first .u.upd.calls`table]

// ---------------------------------------------------------------------------
// Tests: upd — symboldiscovery rows update .crypto.symmap, NOT forwarded to TP
// ---------------------------------------------------------------------------

// Reset call log
`.u.upd.calls set ()

// Reset symmap
`.crypto.symmap set ([]
  canonical_symbol:`symbol$();
  venue:`symbol$();
  venue_symbol:`symbol$()
  )

discrow:([]
  canonical_symbol:enlist `$"BTC-USD";
  venue:enlist `kraken;
  venue_symbol:enlist `XBT/USD
  )

.pythonfeed.upd[`symboldiscovery;discrow]
assert["upd[symboldiscovery] does NOT forward to tickerplant";0=count .u.upd.calls]
assert["upd[symboldiscovery] upserts into .crypto.symmap";0<count .crypto.symmap]
assert["upd[symboldiscovery] correct canonical_symbol in symmap";(`$"BTC-USD") in .crypto.symmap`canonical_symbol]

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
-1 "\n--- pythonfeed test results ---";
-1 "Passed: ",string passed;
-1 "Failed: ",string failed;
if[failed>0; exit 1];
exit 0
