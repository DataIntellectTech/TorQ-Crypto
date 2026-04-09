// tests/test_cryptolib.q — Unit tests for code/cryptofunctions/cryptolib.q
//
// Validates that all .crypto.* functions work correctly against synthetic
// trade, quote, lastprice and consolidatedmid data matching the canonical
// table schemas in appconfig/schemas/tables.q.
//
// Run from repo root:
//   q tests/test_cryptolib.q
//
// Exit codes: 0 = all tests passed, 1 = one or more failed

// ---------------------------------------------------------------------------
// Minimal TorQ stubs required by cryptolib.q
// ---------------------------------------------------------------------------

.proc.proctype:`rdb;
.proc.cp:{.z.p};
.proc.cd:{.z.d};
.lg.e:{[x;y]show "[ERROR] [",string[x],"] ",y;};

// ---------------------------------------------------------------------------
// Synthetic data — schema matches appconfig/schemas/tables.q
// ---------------------------------------------------------------------------

now:.z.p;

// 10 trades: 5 from binance, 5 from kraken, all for BTCUSD today
trade:([]
  time:now+0D00:00:01*til 10;
  sym:10#`BTCUSD;
  venue:raze 5#/:`binance`kraken;
  price:50000f+til 10;
  size:0.1+0.01*til 10;
  side:10#`buy;
  venue_sym:10#`BTCUSDT;
  seq:`long$til 10);

// 10 quotes: 5 from each venue
quote:([]
  time:now+0D00:00:01*til 10;
  sym:10#`BTCUSD;
  venue:raze 5#/:`binance`kraken;
  bid:49990f+til 10;
  ask:50010f+til 10;
  bsize:1f+0.1*til 10;
  asize:1f+0.1*til 10;
  venue_sym:10#`BTCUSDT);

// lastprice keyed table — one entry per sym+venue (single line: kdb+5 multi-line keyed table literals are fragile)
lastprice:([sym:`BTCUSD`BTCUSD;venue:`binance`kraken] time:2#now;price:50004 50009f;bid:49994 50004f;ask:50014 50014f;mid:50004 50009f);

// consolidatedmid timeseries — two recent rows
consolidatedmid:([] time:now,now-0D00:01;sym:2#`BTCUSD;mid:50006 50002f;n_venues:2 2i;spread_dispersion:20 18f;outlier_flag:00b);

// ---------------------------------------------------------------------------
// Load library under test
// ---------------------------------------------------------------------------

\l code/cryptofunctions/cryptolib.q

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

errors:0;
pass:{-1 "PASS: ",x;};
fail:{errors+::1; -1 "FAIL: ",x;};
check:{[name;cond] $[cond; pass name; fail name]};

// ---------------------------------------------------------------------------
// ohlc tests
// ---------------------------------------------------------------------------

r:.crypto.ohlc[`sym`date!(`BTCUSD;enlist .z.d)];
check["ohlc: returns a table";            98h=type r];
check["ohlc: has open column";            `open in cols r];
check["ohlc: has high column";            `high in cols r];
check["ohlc: has low column";             `low in cols r];
check["ohlc: has close column";           `close in cols r];
check["ohlc: has vwap column";            `vwap in cols r];
check["ohlc: has volume column";          `volume in cols r];
check["ohlc: BTCUSD row present";        `BTCUSD in exec sym from r];
check["ohlc: high >= open";              all (exec high from r)>=(exec open from r)];
check["ohlc: low <= open";               all (exec low from r)<=(exec open from r)];

// byvenue=1b should return one row per sym+venue
rv:.crypto.ohlc[`sym`date`byvenue!(`BTCUSD;enlist .z.d;1b)];
check["ohlc byvenue: has venue column";   `venue in cols rv];
check["ohlc byvenue: two rows (2 venues)";2=count rv];

// ---------------------------------------------------------------------------
// topofbook tests
// ---------------------------------------------------------------------------

rt:.crypto.topofbook[`sym`starttime`endtime!(`BTCUSD;now-0D00:01;now+0D00:01)];
check["topofbook: returns a table";       98h=type rt];
check["topofbook: has time column";       `time in cols rt];
check["topofbook: has binanceBid column"; `binanceBid in cols rt];
check["topofbook: has krakenBid column";  `krakenBid in cols rt];
check["topofbook: has binanceBidSize";    `binanceBidSize in cols rt];
check["topofbook: has krakenAskSize";     `krakenAskSize in cols rt];

// ---------------------------------------------------------------------------
// arbitrage tests
// ---------------------------------------------------------------------------

ra:.crypto.arbitrage[`sym`starttime`endtime!(`BTCUSD;now-0D00:01;now+0D00:01)];
check["arbitrage: returns a table";       98h=type ra];
check["arbitrage: has profit column";     `profit in cols ra];
check["arbitrage: has arbitrage column";  `arbitrage in cols ra];
check["arbitrage: profit is float";       9h=type ra`profit];
check["arbitrage: arbitrage is boolean";  1h=type ra`arbitrage];

// ---------------------------------------------------------------------------
// getconsolidated tests
// ---------------------------------------------------------------------------

rc:.crypto.getconsolidated[`];
check["getconsolidated: returns 2 rows";  2=count rc];
check["getconsolidated: has sym column";  `sym in cols rc];
check["getconsolidated: has venue column";`venue in cols rc];
check["getconsolidated: has mid column";  `mid in cols rc];
check["getconsolidated: has price column";`price in cols rc];
check["getconsolidated: unkeyed (type 98)";98h=type rc];

// Filter by sym
rcf:.crypto.getconsolidated[enlist`BTCUSD];
check["getconsolidated filtered: 2 rows"; 2=count rcf];

// ---------------------------------------------------------------------------
// gethistory tests
// ---------------------------------------------------------------------------

rh:.crypto.gethistory[`BTCUSD;60j];
check["gethistory: returns rows";         0<count rh];
check["gethistory: has time column";      `time in cols rh];
check["gethistory: has mid column";       `mid in cols rh];
check["gethistory: only 2 columns";       2=count cols rh];
check["gethistory: mid is float";         9h=type rh`mid];

// Window filter — 0 minutes should return nothing
rh0:.crypto.gethistory[`BTCUSD;0j];
check["gethistory 0min: empty result";    0=count rh0];

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

-1 "";
$[0=errors;
  [-1 "All cryptolib unit tests PASSED"; exit 0];
  [-1 (string errors)," test(s) FAILED"; exit 1]
  ]
