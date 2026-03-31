// test_cryptoagg.q — Unit tests for code/processes/cryptoagg.q
//
// Run from repo root:
//   q tests/test_cryptoagg.q -noprocess
//
// Does NOT require a live TorQ stack.

// ---------------------------------------------------------------------------
// Mock TorQ framework dependencies
// ---------------------------------------------------------------------------
.lg.o:{[ctx;msg] -1 "[INFO] ",(string ctx),": ",msg;}
.lg.e:{[ctx;msg] -1 "[ERROR] ",(string ctx),": ",msg;}
.lg.w:{[ctx;msg] -1 "[WARN] ",(string ctx),": ",msg;}

.proc.proctype:`cryptoagg
.proc.procname:`cryptoagg1
.proc.cp:{.z.p}
.proc.cd:{`date$.z.p}

.servers.CONNECTIONS:enlist `tickerplant
.servers.gethandlebytype:{[t;algo] 0Ni}

.dotz.set:{[handler;fn] @[`.;handler;:;fn]}

.api.add:{[name;pub;desc;param;ret] :()}

// Mock .sub.subscribe — no-op
.sub.subscribe:{[tables;syms;schema;replay;handle] :()}

// Mock .timer.repeat — no-op
.timer.repeat:{[start;end;period;fn;desc] :()}

// Mock .gc.run — no-op
.gc.run:{[]}

// ---------------------------------------------------------------------------
// Load the file under test
// ---------------------------------------------------------------------------
\l code/processes/cryptoagg.q

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
// Tests: updtrade
// ---------------------------------------------------------------------------

// Insert two trade rows for different exchanges
traderows:([]
  time:.proc.cp[] .proc.cp[];
  sym:`$("BTC-USD";"BTC-USD");
  exchange:`kraken`coinbase;
  price:50000 50010f;
  size:0.1 0.2f;
  side:`buy`sell;
  venue_sym:`$("XBT/USD";"BTC-USD")
  )

.cryptoagg.updtrade[traderows]
assert["updtrade: lasttrade populated";0<count 0!.cryptoagg.lasttrade]
assert["updtrade: kraken row present";`kraken in exec exchange from 0!.cryptoagg.lasttrade]
assert["updtrade: coinbase row present";`coinbase in exec exchange from 0!.cryptoagg.lasttrade]
assert["updtrade: kraken price correct";50000f=first exec price from 0!.cryptoagg.lasttrade where exchange=`kraken]

// ---------------------------------------------------------------------------
// Tests: updbook and consolidate
// ---------------------------------------------------------------------------

// Insert book rows for BTC-USD on two venues
bookrows:([]
  time:(.proc.cp[];.proc.cp[]);
  sym:`$("BTC-USD";"BTC-USD");
  exchange:`kraken`coinbase;
  bid:50000 50005f;
  bidSize:1f 0.5f;
  ask:50010 50008f;
  askSize:0.8f 1f
  )

.cryptoagg.updbook[bookrows]

// Check lastbook populated
assert["updbook: lastbook populated";0<count 0!.cryptoagg.lastbook]
assert["updbook: kraken in lastbook";`kraken in exec exchange from 0!.cryptoagg.lastbook]
assert["updbook: coinbase in lastbook";`coinbase in exec exchange from 0!.cryptoagg.lastbook]

// Check consolidated populated for BTC-USD
assert["consolidate: consolidated table populated";(`$"BTC-USD") in exec sym from 0!.cryptoagg.consolidated]

// Verify consolidated values:
//   max bid = max(50000,50005) = 50005
//   min ask = min(50010,50008) = 50008
//   mid     = (50005+50008)/2  = 50006.5
consrow:first select from 0!.cryptoagg.consolidated where sym=`$"BTC-USD"
assert["consolidate: consolidated_bid = max of venue bids";50005f=consrow`consolidated_bid]
assert["consolidate: consolidated_ask = min of venue asks";50008f=consrow`consolidated_ask]
assert["consolidate: consolidated_mid correct";50006.5f=consrow`consolidated_mid]
assert["consolidate: venue_count = 2";2=consrow`venue_count]
assert["consolidate: outlier_flag is boolean";-1h=type consrow`outlier_flag]
assert["consolidate: venue_bids is a float list";9h=type consrow`venue_bids]
assert["consolidate: venue_names is a symbol list";11h=type consrow`venue_names]

// ---------------------------------------------------------------------------
// Tests: getconsolidated — always returns simple table (98h)
// ---------------------------------------------------------------------------

// All syms
r:.cryptoagg.getconsolidated[`]
assert["getconsolidated[`] returns simple table";98h=type r]
assert["getconsolidated[`] has consolidated_bid column";`consolidated_bid in cols r]

// Single sym
r2:.cryptoagg.getconsolidated[`$"BTC-USD"]
assert["getconsolidated single sym returns simple table";98h=type r2]
assert["getconsolidated single sym: one row";1=count r2]
assert["getconsolidated single sym: correct sym";(`$"BTC-USD")=first r2`sym]

// Unknown sym returns empty simple table
r3:.cryptoagg.getconsolidated[`$"UNKNOWN-SYM"]
assert["getconsolidated unknown sym returns empty simple table";98h=type r3]
assert["getconsolidated unknown sym: 0 rows";0=count r3]

// List of syms
r4:.cryptoagg.getconsolidated[`$("BTC-USD";"ETH-USD")]
assert["getconsolidated list of syms returns simple table";98h=type r4]

// ---------------------------------------------------------------------------
// Tests: getlastbook — always returns simple table (98h)
// ---------------------------------------------------------------------------

lb:.cryptoagg.getlastbook[`]
assert["getlastbook[`] returns simple table";98h=type lb]
assert["getlastbook[`] has bid column";`bid in cols lb]

lb2:.cryptoagg.getlastbook[`$"BTC-USD"]
assert["getlastbook single sym returns simple table";98h=type lb2]
assert["getlastbook single sym has correct rows";0<count lb2]

// ---------------------------------------------------------------------------
// Tests: getlastprices — always returns simple table (98h)
// ---------------------------------------------------------------------------

lp:.cryptoagg.getlastprices[`]
assert["getlastprices[`] returns simple table";98h=type lp]
assert["getlastprices[`] has price column";`price in cols lp]

// ---------------------------------------------------------------------------
// Tests: upd dispatch
// ---------------------------------------------------------------------------

// Inject a book update via the upd handler — should call updbook
prevcount:count 0!.cryptoagg.consolidated
newbook:([]
  time:enlist .proc.cp[];
  sym:enlist `$"ETH-USD";
  exchange:enlist `kraken;
  bid:enlist 3000f;
  bidSize:enlist 5f;
  ask:enlist 3005f;
  askSize:enlist 3f
  )
upd[`exchange_top;newbook]
assert["upd[exchange_top] triggers updbook";(`$"ETH-USD") in exec sym from 0!.cryptoagg.consolidated]

// Trade dispatch
prevtcount:count 0!.cryptoagg.lasttrade
newtrade:([]
  time:enlist .proc.cp[];
  sym:enlist `$"ETH-USD";
  exchange:enlist `coinbase;
  price:enlist 3001f;
  size:enlist 0.5f;
  side:enlist `buy;
  venue_sym:enlist `$"ETH-USD"
  )
upd[`trade;newtrade]
assert["upd[trade] triggers updtrade";`coinbase in exec exchange from select from 0!.cryptoagg.lasttrade where sym=`$"ETH-USD"]

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
-1 "\n--- cryptoagg test results ---";
-1 "Passed: ",string passed;
-1 "Failed: ",string failed;
if[failed>0; exit 1];
exit 0
