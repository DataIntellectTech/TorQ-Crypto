// cryptoagg.q — Real-time aggregation process
// Subscribes to tickerplant, maintains consolidated order book per instrument,
// and serves getconsolidated / getlastbook / getlastprices queries.

\d .cryptoagg

// Configuration — all overridable in appconfig/settings/cryptoagg.q
stalenesswindow:@[value;`stalenesswindow;0D00:00:30]
outlierthreshold:@[value;`outlierthreshold;50f]
loglevel:@[value;`loglevel;`info]
gc:@[value;`gc;0b]
tpconnsleepintv:@[value;`tpconnsleepintv;10]   // seconds between TP connection attempts
tpcheckcycles:@[value;`tpcheckcycles;0W]        // max retry cycles (0W = retry indefinitely)

// In-memory state tables — keyed for fast upsert by sym+exchange

// Last trade per sym per exchange
lasttrade:`sym`exchange xkey ([]
  sym:`symbol$();
  exchange:`symbol$();
  time:`timestamp$();
  price:`float$();
  size:`float$()
  )

// Last top-of-book per sym per exchange
lastbook:`sym`exchange xkey ([]
  sym:`symbol$();
  exchange:`symbol$();
  time:`timestamp$();
  bid:`float$();
  bidSize:`float$();
  ask:`float$();
  askSize:`float$()
  )

// Consolidated order book per sym — best bid/ask across contributing venues
consolidated:`sym xkey ([]
  sym:`symbol$();
  update_time:`timestamp$();
  consolidated_bid:`float$();
  consolidated_ask:`float$();
  consolidated_mid:`float$();
  venue_count:`long$();
  spread_dispersion:`float$();
  outlier_flag:`boolean$();
  venue_bids:();
  venue_asks:();
  venue_names:()
  )

// consolidate — recompute the consolidated row for a single sym.
// Ignores book entries older than stalenesswindow.
consolidate:{[s]
  cutoff:.proc.cp[]-stalenesswindow;
  rows:0!select from lastbook where sym=s,time>=cutoff;
  if[0=count rows; :()];
  mids:avg each flip(rows`bid;rows`ask);
  cbid:max rows`bid;
  cask:min rows`ask;
  cmid:(cbid+cask)%2;
  disp:?[0f<min mids;10000*(max[mids]-min[mids])%min mids;0f];
  `.cryptoagg.consolidated upsert
    (s;.proc.cp[];cbid;cask;cmid;count rows;disp;disp>outlierthreshold;rows`bid;rows`ask;rows`exchange)
 };

// updtrade — upsert last trade per sym/exchange
updtrade:{[x]
  `.cryptoagg.lasttrade upsert select sym,exchange,time,price,size from x
 };

// updbook — upsert last book per sym/exchange then recompute consolidated
updbook:{[x]
  `.cryptoagg.lastbook upsert select sym,exchange,time,bid,bidSize,ask,askSize from x;
  // Error handler is a projection: s is bound per-sym, e receives the error string
  {[s] @[consolidate;s;{[s;e].lg.w[`cryptoagg;"consolidate failed for sym ",(string s),": ",e]}[s;]]} each exec distinct sym from x
 };

// upd — root-level handler called by the tickerplant on each published batch
upd:{[t;x]
  $[t=`exchange_top; .cryptoagg.updbook[x];
    t=`trade;        .cryptoagg.updtrade[x];
                     .lg.o[`cryptoagg;"ignoring table: ",string t]]
 };

// getconsolidated — return consolidated book for requested syms.
// syms: ` (all), single symbol, or list of symbols.
// Returns simple table (98h) — not keyed.
getconsolidated:{[syms]
  r:$[syms~`;
    consolidated;
    select from consolidated where sym in syms];
  0!r
 };

// getlastbook — return per-venue last book entries for requested syms.
// Returns simple table (98h).
getlastbook:{[syms]
  r:$[syms~`;
    lastbook;
    select from lastbook where sym in syms];
  0!r
 };

// getlastprices — return last trade price per sym per exchange.
// Returns simple table (98h).
getlastprices:{[syms]
  r:$[syms~`;
    lasttrade;
    select from lasttrade where sym in syms];
  0!r
 };

// purgeold — timer callback: log consolidated row count and remove stale entries
purgeold:{[]
  @[{[]
    cutoff:.proc.cp[]-(stalenesswindow*10);
    stale_b:exec sym from lastbook where time<cutoff;
    stale_t:exec sym from lasttrade where time<cutoff;
    delete from `.cryptoagg.lastbook where time<cutoff;
    delete from `.cryptoagg.lasttrade where time<cutoff;
    n:count 0!consolidated;
    .lg.o[`cryptoagg;"consolidated rows: ",string[n],
      " | purged book: ",string[count stale_b],
      " trade: ",string[count stale_t]];
    if[gc;.gc.run[]]
   };`;{.lg.w[`cryptoagg;"purgeold failed: ",x]}]
 };

// subscribe — modelled on rdb.q: get first available TP handle and subscribe.
// replaylog:0b — cryptoagg builds state from live ticks only.
subscribe:{[]
  s:.sub.getsubscriptionhandles[`tickerplant;`;()!()];
  if[not count s;
    .lg.w[`cryptoagg;"subscribe: no tickerplant handle available"];
    :()];
  .lg.o[`cryptoagg;"found tickerplant, subscribing to trade and exchange_top"];
  .[.sub.subscribe;(`trade`exchange_top;`;0b;0b;first s);
    {.lg.w[`cryptoagg;"subscription failed: ",x]}]
 };

\d .

// Root-level upd — the tickerplant calls upd[t;x] at root scope, not .cryptoagg.upd.
// This assignment must be after \d . so it lands in the root namespace.
upd:.cryptoagg.upd

// API registration
.api.add[`.cryptoagg.getconsolidated;1b;"Get consolidated order book for given syms (` for all)";"` or `BTC-USD or `BTC-USD`ETH-USD";"simple table"];
.api.add[`.cryptoagg.getlastbook;1b;"Get last per-venue book entries for given syms";"` or `BTC-USD";"simple table"];
.api.add[`.cryptoagg.getlastprices;1b;"Get last trade price per sym per exchange";"` or `BTC-USD";"simple table"];

// Startup — modelled on rdb.q.
// Ensure tickerplant is in CONNECTIONS, then block via startupdepcycles until it
// connects (startupdepcycles calls .servers.startup[] internally and retries on a
// sleep interval). Once connected, subscribe and register the purge timer.
.servers.CONNECTIONS:distinct .servers.CONNECTIONS,`tickerplant;
.servers.startupdepcycles[`tickerplant;.cryptoagg.tpconnsleepintv;.cryptoagg.tpcheckcycles];
.cryptoagg.subscribe[];
.timer.repeat[.proc.cp[];0Wp;0D00:01;(`.cryptoagg.purgeold;`);"cryptoagg: purge stale entries"];
.lg.o[`cryptoagg;"cryptoagg initialised"];
