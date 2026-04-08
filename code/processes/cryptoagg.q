// code/processes/cryptoagg.q — Consolidated mid-price aggregation process.
//
// Subscribes to tickerplant for trade+quote, maintains per-venue last-book
// and last-trade state, computes consolidated mid prices, and publishes
// aggregated snapshots to the tickerplant at a fixed interval.
//
// Start via deploy or:
//   q torq.q -load code/processes/cryptoagg.q -proctype cryptoagg -procname cryptoagg1 -debug

\d .cryptoagg

// ---------------------------------------------------------------------------
// Config (guard pattern — all overridable from config files or command line)
// ---------------------------------------------------------------------------

// Ignore lastbook entries older than this when consolidating
stalenesswindow:@[value;`stalenesswindow;0D00:00:30]

// Spread dispersion threshold in bps; sets outlier_flag if exceeded
outlierthreshold:@[value;`outlierthreshold;50]

// How often (period) to publish consolidatedmid + lastprice to TP
aggfreq:@[value;`aggfreq;0D00:00:05]

// Call .Q.gc[] in maintenance timer
gc:@[value;`gc;0b]

// Path to the tickerplant schema file — loaded at startup so subscribed table
// definitions are available for log-replay normalization.
// Defaults to ${TORQAPPHOME}/database (same file the tickerplant loads).
schemafile:@[value;`schemafile;hsym`$getenv[`TORQAPPHOME],"/database.q"]

// ---------------------------------------------------------------------------
// Internal state tables (private — not directly published as schemas)
// ---------------------------------------------------------------------------

// Last trade price per sym+venue
lasttrade:([sym:`symbol$(); venue:`symbol$()] time:`timestamp$(); price:`float$())

// Last top-of-book quote per sym+venue
lastbook:([sym:`symbol$(); venue:`symbol$()] time:`timestamp$(); bid:`float$(); ask:`float$())

// Per-venue consolidated snapshot — published to TP as lastprice
// Schema matches appconfig/schemas/tables.q:lastprice
lastprice:([sym:`symbol$(); venue:`symbol$()] time:`timestamp$(); price:`float$(); bid:`float$(); ask:`float$(); mid:`float$())

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// Return last trade price for a sym+venue pair; 0n if not yet seen
pricefor:{[s;v]
  r:.cryptoagg.lasttrade (s;v);
  $[99h=type r; r`price; 0nf]
  }

// Build a single consolidatedmid dict for sym s at time now.
// Returns () if fewer than 2 fresh venues are available.
// spread_dispersion: (max_mid - min_mid) / median_mid * 10000 (bps)
// outlier_flag: 1b when spread_dispersion > outlierthreshold
buildmidrow:{[s;now]
  fresh:0! select from .cryptoagg.lastbook where sym=s,
    time > now - .cryptoagg.stalenesswindow;
  if[2 > count fresh; :()];
  mids:(fresh[`bid] + fresh[`ask]) % 2f;
  med_mid:med mids;
  disp:$[med_mid>0f; 10000f * (max[mids] - min[mids]) % med_mid; 0f];
  enlist `time`sym`mid`n_venues`spread_dispersion`outlier_flag!
    (now; s; med_mid; `int$count fresh; disp; disp > .cryptoagg.outlierthreshold)
  }

// ---------------------------------------------------------------------------
// consolidate — recompute per-venue snapshot for one sym
// ---------------------------------------------------------------------------
// Called on every quote upd for each distinct sym in the batch.
// Silently skips if fewer than 2 venues have fresh data.

consolidate:{[s]
  now:.proc.cp[];
  fresh:0! select from .cryptoagg.lastbook where sym=s,
    time > now - .cryptoagg.stalenesswindow;
  if[2 > count fresh; :()];
  fresh:update mid:(bid+ask)%2f from fresh;
  fresh:update price:.cryptoagg.pricefor[s;] each venue from fresh;
  `.cryptoagg.lastprice upsert
    ([sym:fresh`sym; venue:fresh`venue]
     time:fresh`time; price:fresh`price; bid:fresh`bid; ask:fresh`ask; mid:fresh`mid)
  }

// ---------------------------------------------------------------------------
// upd handlers (called from root upd below)
// ---------------------------------------------------------------------------

// x is always a table by the time these are called (normalized in upd below)
updtrade:{[x]
  `.cryptoagg.lasttrade upsert ([sym:x`sym; venue:x`venue] time:x`time; price:x`price)
  }

updquote:{[x]
  `.cryptoagg.lastbook upsert ([sym:x`sym; venue:x`venue] time:x`time; bid:x`bid; ask:x`ask);
  .cryptoagg.consolidate each distinct x`sym
  }

// ---------------------------------------------------------------------------
// aggpublish — timer: build and publish consolidatedmid + lastprice snapshot
// ---------------------------------------------------------------------------

aggpublish:{[]
  h:neg .servers.gethandlebytype[`tickerplant;`any];
  if[0Ni~neg h;
    .lg.w[`cryptoagg;"no tickerplant handle — skipping publish"];
    :()];
  now:.proc.cp[];
  allsyms:distinct exec sym from .cryptoagg.lastbook;
  // Build one row per sym; filter syms with fewer than 2 fresh venues
  rowlist:.cryptoagg.buildmidrow[;now] each allsyms;
  rowlist:rowlist where {not ()~x} each rowlist;
  if[count rowlist;
    rows:raze rowlist;
    h(`.u.upd;`consolidatedmid;
      (rows`time; rows`sym; rows`mid; rows`n_venues; rows`spread_dispersion; rows`outlier_flag))
    ];
  // Publish current lastprice snapshot (upsert-style via keyed table insert)
  lp:0! .cryptoagg.lastprice;
  if[count lp;
    h(`.u.upd;`lastprice;
      (lp`sym; lp`venue; lp`time; lp`price; lp`bid; lp`ask; lp`mid))]
  }

// ---------------------------------------------------------------------------
// maintain — timer: log stats, purge stale data, optional gc
// ---------------------------------------------------------------------------

maintain:{[]
  nsym:count distinct exec sym from .cryptoagg.lastbook;
  .lg.o[`cryptoagg;"consolidated sym count: ",string nsym];
  // Purge lastbook entries more than 10x stalenesswindow old
  cutoff:.proc.cp[] - 10 * .cryptoagg.stalenesswindow;
  delete from `.cryptoagg.lastbook where time < cutoff;
  if[.cryptoagg.gc; .Q.gc[]]
  }

\d .

// ---------------------------------------------------------------------------
// Load TP schema file — defines trade/quote in memory so upd can normalize
// log-replay data (column vectors) using the same schema as the tickerplant.
// ---------------------------------------------------------------------------

@[.proc.loadf; 1_string .cryptoagg.schemafile;
  {.lg.e[`cryptoagg;"failed to load schemafile ",string .cryptoagg.schemafile,": ",x]}]

// ---------------------------------------------------------------------------
// upd — root namespace (called by tickerplant subscription)
// ---------------------------------------------------------------------------
// Rule S3: upd must be at root so the tickerplant can call it.
//
// During live subscription x arrives as a table (type 98h).
// During log replay x arrives as a list of column vectors.
// Normalize to a table here so the handlers always see the same format.
// Tables not defined in the loaded schema are silently ignored.

upd:{[t;x]
  if[not 98h=type @[value;t;0]; :()];
  if[98h<>type x; x:flip (cols value t)!x];
  $[t=`trade; .cryptoagg.updtrade x;
    t=`quote; .cryptoagg.updquote x;
    ()]
  }

// ---------------------------------------------------------------------------
// Query functions (public API)
// ---------------------------------------------------------------------------

.cryptoagg.getconsolidated:{[syms]
  lp:0! .cryptoagg.lastprice;
  if[not `~syms; lp:select from lp where sym in syms];
  lp
  }

.cryptoagg.getlastprices:{[syms]
  lt:0! .cryptoagg.lasttrade;
  if[not `~syms; lt:select from lt where sym in syms];
  lt
  }

.cryptoagg.getlastbook:{[syms]
  lb:0! .cryptoagg.lastbook;
  if[not `~syms; lb:select from lb where sym in syms];
  lb
  }

// ---------------------------------------------------------------------------
// Timers
// ---------------------------------------------------------------------------

.timer.repeat[.proc.cp[];0Wp;.cryptoagg.aggfreq;(`.cryptoagg.aggpublish;`);
  "cryptoagg: publish consolidatedmid and lastprice snapshot"]
.timer.repeat[.proc.cp[];0Wp;0D00:01;(`.cryptoagg.maintain;`);
  "cryptoagg: maintenance — log stats, purge stale entries"]

// ---------------------------------------------------------------------------
// API documentation (Rule A1 / N4)
// ---------------------------------------------------------------------------

.api.add[`.cryptoagg.getconsolidated;1b;
  "Return current per-venue consolidated snapshot; pass ` for all syms";
  "syms(symbol|`)";
  "table"]

.api.add[`.cryptoagg.getlastprices;1b;
  "Return last trade price per sym+venue; pass ` for all syms";
  "syms(symbol|`)";
  "table"]

.api.add[`.cryptoagg.getlastbook;1b;
  "Return last top-of-book quote per sym+venue; pass ` for all syms";
  "syms(symbol|`)";
  "table"]

// ---------------------------------------------------------------------------
// Connection management (Rule M1)
// ---------------------------------------------------------------------------

.servers.CONNECTIONS:distinct .servers.CONNECTIONS,enlist `tickerplant

// ---------------------------------------------------------------------------
// Startup (Rule M1: startup[] must be called explicitly)
// ---------------------------------------------------------------------------

.servers.startup[]

// Subscribe to trade and quote with log replay (Rule P1).
// .sub.subscribe 5th arg is a proc dict (procname,proctype,w) — not a raw handle.
// Use .sub.getsubscriptionhandles to resolve the live tickerplant connection.
s:.sub.getsubscriptionhandles[`tickerplant;();()!()];
if[count s; .sub.subscribe[`trade`quote;`;0b;1b;first s]];

.lg.o[`cryptoagg;"cryptoagg process initialised"]
