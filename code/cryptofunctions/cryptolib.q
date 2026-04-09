// code/cryptofunctions/cryptolib.q — Crypto query library
//
// Loaded on RDB and HDB via -parentproctype cryptofunctions (process.csv).
// All functions live in the .crypto namespace.
//
// Tables referenced:
//   trade  — time sym venue price size side venue_sym seq
//   quote  — time sym venue bid ask bsize asize venue_sym
//   lastprice (RDB only)     — [sym venue] time price bid ask mid
//   consolidatedmid (RDB only) — time sym mid n_venues spread_dispersion outlier_flag

\d .crypto

// ---------------------------------------------------------------------------
// Utility functions
// ---------------------------------------------------------------------------

errfunc:{.lg.e[x;"Crypto User Error: ",y];'y};

// Return column names from table matching a glob pattern
getcols:{[table;word] col where (col:cols table) like word};

// Merge default dict with user dict, keeping user values where present
setdefaults:{[def;dict] def,(where not all each null dict)#dict};

// Validate types and required keys of a user-supplied dictionary
typecheck:{[typedict;requiredkeylist;dict]
  if[not 99=type dict; errfunc[`typecheck;"The argument must be a dictionary."]];
  if[not all keyresult:key[dict] in key typedict;
    errfunc[`typecheck;"Incorrect keys: ",(", " sv string key[dict] where 0=keyresult),
      ". Allowed: ",", " sv string key typedict]];
  requiredkeys:(key typedict) where requiredkeylist;
  if[not all requiredkeys in key dict;
    errfunc[`requiredkeys;"Required key(s) missing: ",", " sv string requiredkeys]];
  typematch:typedict[key dict]=abs type each dict;
  if[not all typematch;
    errfunc[`typematch;"Wrong type(s) for key(s): ",", " sv string key[dict] where not typematch]]
  };

// ---------------------------------------------------------------------------
// ohlc — OHLC of trade price by date+sym, optionally broken down by venue
//
// Runs on RDB (intraday) or HDB (historical).
//
// Argument dictionary keys:
//   sym       (required) — symbol atom or list,  e.g. `BTC-USD
//   date      (optional) — date atom or list;    default: today
//   venues    (optional) — venue symbol list;    default: all
//   byvenue   (optional) — 1b = break down by venue; default: 0b
//
// Returns: table with columns date sym [venue] open high low close vwap volume
// ---------------------------------------------------------------------------

ohlc:{[dict]
  allkeys:`date`sym`venues`byvenue;
  typecheck[allkeys!14 11 11 1h;0100b;dict];

  // Default date: today on RDB (via .proc.cd[]), last HDB date otherwise
  defaultdate:$[`rdb~.proc.proctype; enlist .proc.cd[]; enlist last date];
  d:setdefaults[allkeys!(defaultdate;`;`;0b);dict];

  // On RDB the partition key is a virtual time.date; on HDB it is the date column
  c:$[`rdb~.proc.proctype; `time.date; `date];

  wherecl:`date`sym`venues!(
    (in;c;enlist d`date);
    (in;`sym;enlist d`sym);
    (in;`venue;enlist d`venues));
  wherecl@:where[not all each null d] except `byvenue;

  bycl:(`date`sym!c,`sym),$[d`byvenue;(enlist`venue)!(enlist`venue);()!()];

  coldict:`open`high`low`close`vwap`volume!(
    (first;`price);
    (max;`price);
    (min;`price);
    (last;`price);
    (wavg;`size;`price);
    (sum;`size));

  // `trade resolves in root namespace regardless of calling namespace
  0!?[`trade;wherecl;bycl;coldict]
  };

// ---------------------------------------------------------------------------
// topofbook — per-venue top-of-book snapshots bucketed over a time range
//
// Runs on RDB (intraday) or HDB (historical).
//
// Argument dictionary keys:
//   sym       (required) — symbol atom,   e.g. `BTC-USD
//   starttime (optional) — timestamp;     default: start of today (RDB) or yesterday (HDB)
//   endtime   (optional) — timestamp;     default: now (RDB) or end of yesterday (HDB)
//   venues    (optional) — venue list;    default: all
//   bucket    (optional) — second span;   default: 5s
//
// Returns: table keyed by time with columns {venue}Bid {venue}Ask {venue}BidSize {venue}AskSize
// ---------------------------------------------------------------------------

topofbook:{[dict]
  allkeys:`starttime`endtime`sym`venues`bucket;
  typecheck[allkeys!12 12 11 11 18h;00100b;dict];
  if[any 1 0<(count;sum)@\: null dict[`sym]; errfunc[`topofbook;"Please enter one non-null sym."]];

  // Defaults depend on proctype
  defaulttimes:$[`rdb~.proc.proctype;
    "p"$(.proc.cd[];.proc.cp[]);
    0 -1 + "p"$0 1 + last date];
  d:setdefaults[allkeys!raze(defaulttimes;`;`;0D00:00:05);dict];
  d:@[d;`starttime`endtime`bucket;first];
  d[`bucket]:`long$d`bucket;

  // Add date partition key for HDB where clause
  if[`hdb~.proc.proctype;
    d:`date xcols update date:distinct "d"$d`starttime`endtime from d];

  if[any (all .proc.cp[]<;>/)@\:d`starttime`endtime;
    errfunc[`topofbook;"Invalid start and end times."]];

  wherecl:$[`hdb~.proc.proctype;
    (enlist`date)!enlist(within;`date;enlist,"d"$d`starttime`endtime);
    ()!()];
  wherecl[`starttime]:(within;`time;enlist,d`starttime`endtime);
  wherecl[`sym]:(in;`sym;enlist d`sym);
  wherecl[`venues]:(in;`venue;enlist d`venues);
  wherecl@:where not all each null `endtime`bucket _d;

  // `quote resolves in root namespace regardless of calling namespace
  t:?[`quote;wherecl;0b;cls!cls:`time`venue`bid`ask`bsize`asize];

  venues:exec distinct venue from t;

  // Empty result — return correctly-named empty table
  if[0=count t;
    r:{(`time,`$string[x],/:("Bid";"Ask";"BidSize";"AskSize"))xcol y}[;t] each d`venues;
    :`$[98h~type r;r;(,'/)r]];

  // Pivot per venue, bucket by time
  exchangebook:{[vn;data;bkt]
    (`time,`$string[vn],/:("Bid";"Ask";"BidSize";"AskSize")) xcol
      select bid:last bid, ask:last ask, bidSize:last bsize, askSize:last asize
        by time:(`date$time)+bkt+bkt xbar time.second
        from data where venue=vn
    }[;t;d`bucket] each venues;

  0!`time xasc (,'/) exchangebook
  };

// ---------------------------------------------------------------------------
// arbitrage — top-of-book with cross-venue profit and arbitrage indicator
//
// Wrapper around topofbook; accepts the same dictionary.
// Adds columns: profit (float), arbitrage (boolean)
// ---------------------------------------------------------------------------

arbitrage:{[d]
  arbtable:topofbook[d];
  if[(0=count arbtable) or (5=count cols arbtable);
    :update profit:0f,arbitrage:0b from arbtable];

  calprofit:{[b;bs;a;as]
    enlist({[b;bs;a;as]
      b:max@'l:(,'/)b;
      bs:@'[flip bs;where'[b=l]];
      a:min@'l:(,'/)a;
      as:@'[flip as;where'[a=l]];
      p:min'[(bs,'as)]*b-a;
      ?[0>p;0f;p]};
    enlist,b;enlist,bs;enlist,a;enlist,as)
    };

  cc:calprofit . .crypto.getcols[arbtable;] each ("*Bid";"*BidSize";"*Ask";"*AskSize");
  update arbitrage:profit>0f from ![arbtable;();0b;enlist[`profit]!cc]
  };

// ---------------------------------------------------------------------------
// getconsolidated — unkeyed lastprice snapshot (RDB only)
//
// syms: ` for all, or a symbol list
// Returns columns: sym venue time price bid ask mid
// ---------------------------------------------------------------------------

if[`rdb~.proc.proctype;
  getconsolidated:{[syms]
    lp:0!value`lastprice;   // value`x resolves in root regardless of calling namespace
    if[not `~syms; lp:select from lp where sym in syms];
    lp
    }
  ];

// ---------------------------------------------------------------------------
// gethistory — consolidatedmid timeseries look-back (RDB only)
//
// s:    symbol atom (e.g. `BTC-USD)
// mins: integer — look-back window in minutes
// Returns columns: time mid
// ---------------------------------------------------------------------------

if[`rdb~.proc.proctype;
  gethistory:{[s;nmin]
    // functional select: `consolidatedmid resolves in root namespace
    // use (in;`sym;enlist s): bare symbol treated as column ref in kdb+5
    // parameter named nmin not mins: mins is a kdb+ built-in
    ?[`consolidatedmid;
      ((in;`sym;enlist s);(>=;`time;.proc.cp[]-nmin*0D00:01));
      0b;
      `time`mid!`time`mid]
    }
  ];

\d .
