// test_cryptolib.q — Unit tests for code/cryptofunctions/cryptolib.q
//
// Tests the updated ohlc function (usetrade parameter) and getconsolidated.
// Existing function signatures are verified for compatibility.
//
// Run from repo root:
//   q tests/test_cryptolib.q -noprocess

// ---------------------------------------------------------------------------
// Mock TorQ framework dependencies
// ---------------------------------------------------------------------------
.lg.o:{[ctx;msg] -1 "[INFO] ",(string ctx),": ",msg;}
.lg.e:{[ctx;msg] -1 "[ERROR] ",(string ctx),": ",msg;}
.lg.w:{[ctx;msg] -1 "[WARN] ",(string ctx),": ",msg;}

.proc.proctype:`rdb
.proc.procname:`rdb1
.proc.cp:{.z.p}
.proc.cd:{`date$.z.p}

.servers.CONNECTIONS:enlist `gateway
.servers.gethandlebytype:{[t;algo] 0Ni}  // no cryptoagg — will test error path

.api.add:{[name;pub;desc;param;ret] :()}

// Minimal .crypto namespace used by orderbook/topofbook defaults
.crypto.deffreq:0D00:00:30.000

// ---------------------------------------------------------------------------
// Seed in-memory tables that cryptolib.q functions query
// ---------------------------------------------------------------------------

// exchange_top — used by ohlc (usetrade=0b), topofbook, arbitrage
exchange_top:([]
  time:`timestamp$();
  sym:`g#`symbol$();
  exchangeTime:`timestamp$();
  exchange:`symbol$();
  bid:`float$();
  bidSize:`float$();
  ask:`float$();
  askSize:`float$()
  )

// exchange — used by orderbook
exchange:([]
  time:`timestamp$();
  sym:`g#`symbol$();
  exchangeTime:`timestamp$();
  exchange:`symbol$();
  bid:();
  bidSize:();
  ask:();
  askSize:()
  )

// trade — used by ohlc (usetrade=1b)
trade:([]
  time:`timestamp$();
  sym:`g#`symbol$();
  exchange:`symbol$();
  price:`float$();
  size:`float$();
  side:`symbol$();
  venue_sym:`symbol$()
  )

// Insert test data into exchange_top
today:.proc.cd[]
insert[`exchange_top;
  (today+09:00 09:05 09:10t; `$("BTC-USD";"BTC-USD";"BTC-USD"); today+09:00 09:05 09:10t;
   `kraken`kraken`coinbase; 50000 50100 50050f; 1 0.5 2f; 50010 50110 50060f; 1 0.5 2f)]

// Insert test data into trade
insert[`trade;
  (today+09:00 09:05 09:10t; `$("BTC-USD";"BTC-USD";"BTC-USD"); `kraken`kraken`coinbase;
   50000 50100 50050f; 1 0.5 2f; `buy`sell`buy; `$("XBT/USD";"XBT/USD";"BTC-USD"))]

// ---------------------------------------------------------------------------
// Load cryptolib.q
// ---------------------------------------------------------------------------
\l code/cryptofunctions/cryptolib.q

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
// Tests: ohlc — original behaviour preserved (usetrade=0b)
// ---------------------------------------------------------------------------

// Verify function accepts dictionary argument
r:@[ohlc;enlist[`sym]!enlist `$"BTC-USD";{x}]
assert["ohlc with sym only: no error";not `error~type r]
assert["ohlc with sym only: returns table or keyed table";(98h=type r) or (99h=type r)]

// Verify original keys are preserved in output
r2:ohlc[`sym`byexchange!(`$"BTC-USD";0b)]
assert["ohlc byexchange=0b: has openBid or openPrice column";any (`openBid`openPrice) in cols r2]

// Verify byexchange=1b produces exchange column in result
r3:ohlc[`sym`byexchange!(`$"BTC-USD";1b)]
assert["ohlc byexchange=1b: exchange column present";`exchange in cols r3]

// ---------------------------------------------------------------------------
// Tests: ohlc — usetrade=1b (new behaviour)
// ---------------------------------------------------------------------------

rt:ohlc[`sym`usetrade!(`$"BTC-USD";1b)]
assert["ohlc usetrade=1b: returns table";(98h=type rt) or (99h=type rt)]
assert["ohlc usetrade=1b: has openPrice column";`openPrice in cols rt]
assert["ohlc usetrade=1b: has closePrice column";`closePrice in cols rt]
assert["ohlc usetrade=1b: has highPrice column";`highPrice in cols rt]
assert["ohlc usetrade=1b: has lowPrice column";`lowPrice in cols rt]
// Should NOT have bid-based columns when using trade table
assert["ohlc usetrade=1b: no openBid column";not `openBid in cols rt]

// Verify correct OHLC values
// Prices inserted: 50000, 50100, 50050 — high=50100, low=50000
assert["ohlc usetrade=1b: highPrice=50100";50100f=max exec highPrice from rt]
assert["ohlc usetrade=1b: lowPrice=50000";50000f=min exec lowPrice from rt]

// usetrade=1b with byexchange=1b
rt2:ohlc[`sym`usetrade`byexchange!(`$"BTC-USD";1b;1b)]
assert["ohlc usetrade=1b byexchange=1b: has exchange grouping";`exchange in cols rt2]

// ---------------------------------------------------------------------------
// Tests: ohlc — invalid key rejected
// ---------------------------------------------------------------------------

err:@[ohlc;`sym`badkey!(`$"BTC-USD";1b);{x}]
assert["ohlc rejects unknown key";`string~type err]  // errfunc signals a string error

// ---------------------------------------------------------------------------
// Tests: getconsolidated — error path (no cryptoagg handle available)
// ---------------------------------------------------------------------------
// .servers.gethandlebytype returns 0Ni (no connection), so getconsolidated
// should return an empty table (98h), not crash.

gc:.cryptoagg.getconsolidated  // not available; test the cryptolib version instead
r_gc:getconsolidated[`]
assert["getconsolidated returns table when no cryptoagg";(98h=type r_gc) or (99h=type r_gc) or (0=count r_gc)]

// ---------------------------------------------------------------------------
// Tests: existing functions have correct parameter behaviour
// ---------------------------------------------------------------------------

// typecheck rejects non-dict
err2:@[ohlc;`$"BTC-USD";{x}]
assert["ohlc rejects non-dict argument";`string~type err2]

// setdefaults fills in missing keys
defdict:`a`b`c!(1;2;3)
partial:`a`c!(10;30)
filled:setdefaults[defdict;partial]
assert["setdefaults fills missing key b";filled[`b]=2]
assert["setdefaults preserves supplied key a";filled[`a]=10]
assert["setdefaults preserves supplied key c";filled[`c]=30]

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------
-1 "\n--- cryptolib test results ---";
-1 "Passed: ",string passed;
-1 "Failed: ",string failed;
if[failed>0; exit 1];
exit 0
