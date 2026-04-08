// tests/test_cryptoagg.q
// Unit tests for cryptoagg.q — standalone, no running stack required.
//
// Run: q tests/test_cryptoagg.q
//
// Exit codes: 0 = all tests passed, 1 = one or more failed

// ---------------------------------------------------------------------------
// Stub TorQ infrastructure so cryptoagg.q loads without a running stack
// ---------------------------------------------------------------------------

// Capture absolute repo root before any nested \l calls change the CWD.
// cryptoagg.q loads the schema file via .proc.loadf which uses system "l <path>".
// If the path is relative, q resolves it against the CWD at load time — which
// temporarily becomes code/processes/ during nested \l.  Use an absolute path.
.cryptoagg.schemafile:hsym`$(getenv`PWD),"/database.q"

.proc.cp:{.z.p}
.proc.loadf:{[f] system "l ",f}   // minimal stub: just load the file
.lg.o:{[l;m]}
.lg.w:{[l;m]}
.lg.e:{[l;m]}
.servers.CONNECTIONS:`symbol$()
.servers.startup:{[]}
.servers.gethandlebytype:{[t;m] 0Ni}
.sub.getsubscriptionhandles:{[t;n;a] 0#([]procname:`symbol$();proctype:`symbol$();w:`int$())}
.sub.subscribe:{[t;s;sc;r;p]}
.timer.repeat:{[s;e;p;f;d]}
.api.add:{[f;p;d;a;r]}

// ---------------------------------------------------------------------------
// Load the process under test
// ---------------------------------------------------------------------------

\l code/processes/cryptoagg.q

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

errors:0;
pass:{-1 "PASS: ",x;};
fail:{errors+::1; -1 "FAIL: ",x;};
check:{[name;cond] $[cond; pass name; fail name]};

// ---------------------------------------------------------------------------
// Helper: build a 1-row quote table (matches appconfig/schemas/tables.q)
// ---------------------------------------------------------------------------

mkquote:{[ts;sym;venue;bid;ask]
  ([]time:enlist ts; sym:enlist sym; venue:enlist venue;
   bid:enlist bid; ask:enlist ask; bsize:enlist 0f; asize:enlist 0f;
   venue_sym:enlist `)
  }

// ---------------------------------------------------------------------------
// Test 1: 3 fresh venues — consolidated row created, mid in expected range
//
// Venue mids: binance=(50000+50100)/2=50050, kraken=(50020+50120)/2=50070,
//             okx=(49980+50080)/2=50030.
// Consolidated median mid = med(50030;50050;50070) = 50050.
// ---------------------------------------------------------------------------

now1:.z.p;
upd[`quote; mkquote[now1; `BTCUSD; `binance; 50000f; 50100f]];
upd[`quote; mkquote[now1; `BTCUSD; `kraken;  50020f; 50120f]];
upd[`quote; mkquote[now1; `BTCUSD; `okx;     49980f; 50080f]];

check["test1: 3 venues in lastbook";   3 = count select from .cryptoagg.lastbook where sym=`BTCUSD];
check["test1: lastprice populated";    0 < count .cryptoagg.getconsolidated[`BTCUSD]];

row1:.cryptoagg.buildmidrow[`BTCUSD; .z.p];
check["test1: buildmidrow returns 1 row"; 1 = count row1];
check["test1: n_venues is 3";             3i = first row1`n_venues];

all_mids:50030 50050 50070f;
check["test1: consolidated mid within venue mid range";
  (first row1`mid) within (min all_mids; max all_mids)];

// No outlier — spread ~8 bps, well below 50 bps threshold
check["test1: outlier_flag is 0b"; 0b = first row1`outlier_flag];

// ---------------------------------------------------------------------------
// Test 2: stale quote excluded from consolidation
//
// 2 fresh venues + 1 stale venue for ETHUSD.  stale_ts is 1 minute old
// (> 30 s stalenesswindow), so only 2 fresh entries survive the filter.
// ---------------------------------------------------------------------------

`.cryptoagg.lastbook  set 0#.cryptoagg.lastbook;
`.cryptoagg.lastprice set 0#.cryptoagg.lastprice;

fresh2:.z.p;
stale2:fresh2 - 0D00:01;

upd[`quote; mkquote[fresh2; `ETHUSD; `binance; 3000f; 3010f]];
upd[`quote; mkquote[fresh2; `ETHUSD; `kraken;  3002f; 3012f]];
upd[`quote; mkquote[stale2; `ETHUSD; `okx;     2000f; 2010f]];

row2:.cryptoagg.buildmidrow[`ETHUSD; .z.p];
check["test2: row still built (2 fresh venues survive)"; 1 = count row2];
check["test2: n_venues is 2 not 3";                      2i = first row2`n_venues];
// Stale okx mid (~2005) would drag the result far down if included
check["test2: stale venue excluded from mid";            (first row2`mid) > 2500f];

// ---------------------------------------------------------------------------
// Test 3: outlier_flag triggered when spread > outlierthreshold (50 bps)
//
// binance mid=50000, kraken mid=50010, okx mid=50500.
// spread_dispersion = (50500-50000)/med(50000;50010;50500)*10000 ≈ 99.98 bps
// ---------------------------------------------------------------------------

`.cryptoagg.lastbook  set 0#.cryptoagg.lastbook;
`.cryptoagg.lastprice set 0#.cryptoagg.lastprice;

now3:.z.p;
upd[`quote; mkquote[now3; `SOLUSD; `binance; 49950f; 50050f]];
upd[`quote; mkquote[now3; `SOLUSD; `kraken;  49960f; 50060f]];
upd[`quote; mkquote[now3; `SOLUSD; `okx;     50450f; 50550f]];

row3:.cryptoagg.buildmidrow[`SOLUSD; .z.p];
check["test3: outlier_flag is 1b";       1b = first row3`outlier_flag];
check["test3: spread_dispersion > 50 bps"; (first row3`spread_dispersion) > 50f];

// ---------------------------------------------------------------------------
// Test 4: single venue — consolidate produces no output (needs >= 2 venues)
// ---------------------------------------------------------------------------

`.cryptoagg.lastbook  set 0#.cryptoagg.lastbook;
`.cryptoagg.lastprice set 0#.cryptoagg.lastprice;

upd[`quote; mkquote[.z.p; `XRPUSD; `binance; 0.5f; 0.51f]];

check["test4: single venue — no consolidated output"; 0 = count .cryptoagg.getconsolidated[`XRPUSD]];
check["test4: buildmidrow returns () for 1 venue";    ()~.cryptoagg.buildmidrow[`XRPUSD; .z.p]];

// ---------------------------------------------------------------------------
// Test 5: log replay format — upd receives lists of column vectors, not a table
//
// During TP log replay x is a list of column vectors (type 0h), not a table
// (type 98h).  The normalization in upd must flip it into a table so the
// handlers work identically to the live-subscription path.
// ---------------------------------------------------------------------------

`.cryptoagg.lastbook  set 0#.cryptoagg.lastbook;
`.cryptoagg.lastprice set 0#.cryptoagg.lastprice;

now5:.z.p;
// Simulate replay format: list of column vectors in quote column order
// time sym venue bid ask bsize asize venue_sym
replayquote:(enlist now5; enlist `BTCUSD; enlist `binance; enlist 60000f;
             enlist 60100f; enlist 0f; enlist 0f; enlist `BTCUSDT);
check["test5: replay data is not a table (sanity)"; 98h<>type replayquote];

upd[`quote; replayquote];
check["test5: replay quote inserted into lastbook"; 1=count select from .cryptoagg.lastbook where sym=`BTCUSD];
check["test5: replay bid stored correctly"; 60000f=first exec bid from .cryptoagg.lastbook where sym=`BTCUSD];

// ---------------------------------------------------------------------------
// Test 6: upd with unknown table — no crash, no state change
// ---------------------------------------------------------------------------

`.cryptoagg.lastbook set 0#.cryptoagg.lastbook;

upd[`heartbeat; ([]time:enlist .z.p; sym:enlist `)];
check["test6: upd heartbeat does not crash";       1b];
check["test6: lastbook unchanged after heartbeat"; 0 = count .cryptoagg.lastbook];

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

-1 "";
$[0=errors;
  [-1 "All cryptoagg unit tests PASSED"; exit 0];
  [-1 (string errors)," test(s) FAILED"; exit 1]
  ]
