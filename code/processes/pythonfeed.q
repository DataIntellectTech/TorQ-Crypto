// pythonfeed.q — TorQ IPC bridge for Python WebSocket feed handlers.
//
// Python feeds connect to this process and call .u.upd directly.
// This process forwards each call to the tickerplant and maintains
// local metadata (max trade time per sym+venue) for backfill queries.
//
// Start via torq.sh or:
//   q torq.q -load code/processes/pythonfeed.q -proctype pythonfeed -procname pythonfeed1 -debug

\d .pythonfeed

// ---------------------------------------------------------------------------
// Config (guard pattern — all overridable from command line or config files)
// ---------------------------------------------------------------------------

tptypes:@[value;`tptypes;`tickerplant]

// ---------------------------------------------------------------------------
// In-memory metadata tables
// ---------------------------------------------------------------------------

// Max trade timestamp per sym+venue — used by Python feeds for backfill.
// Keyed table: key=(sym,venue), value=maxtime.
maxtimes:([sym:`symbol$(); venue:`symbol$()] maxtime:`timestamp$())

// Running row counts per table — reset and logged every 60 seconds.
rowcounts:(`symbol$())!(`long$())

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// Update maxtimes from a trade upd call.
// x is a list of column vectors: x[0]=time, x[1]=sym, x[2]=venue, ...
// Computes per-sym-venue batch max and upserts. Feeds send rows in time
// order so this is correct in practice; rare out-of-order arrivals would
// only cause extra backfill overlap, not data loss.
updmaxtimes:{[x]
  if[0=count x 0; :()];
  // Compute per-sym-venue max for this batch, then only upsert where it
  // exceeds the running max (protects against out-of-order arrivals).
  latest:0! `sym`venue xkey select maxtime:max time by sym,venue from
    ([] time:x 0; sym:x 1; venue:x 2);
  {[row]
    k:(row`sym; row`venue);
    curr:.pythonfeed.maxtimes k;
    if[(null curr`maxtime) or row[`maxtime]>curr`maxtime;
      `.pythonfeed.maxtimes upsert
        ([sym:enlist row`sym; venue:enlist row`venue] maxtime:enlist row`maxtime)]
  } each latest
  }

// Increment the row counter for a table name.
incrcount:{[t;x]
  rowcounts[t]+:count x 0
  }

// ---------------------------------------------------------------------------
// Log and reset row counts — fired by 60s timer
// ---------------------------------------------------------------------------

logcounts:{[]
  active:rowcounts where rowcounts>0;
  if[count active;
    .lg.o[`pythonfeed;"row counts (last 60s): ",.Q.s1 active]];
  rowcounts::.pythonfeed.rowcounts!0*rowcounts
  }

// ---------------------------------------------------------------------------
// Timer: log row counts every 60 seconds
// ---------------------------------------------------------------------------

.timer.repeat[.proc.cp[];0Wp;0D00:01;(`.pythonfeed.logcounts;`);"pythonfeed row count log"]

// ---------------------------------------------------------------------------
// Disconnect logging
// ---------------------------------------------------------------------------

.dotz.set[`.z.pc;{[h]
  .lg.o[`pythonfeed;"feed handler disconnected: handle ",string h]}]

\d .

// ---------------------------------------------------------------------------
// .pythonfeed.maxtime — exposed query function for Python backfill
// ---------------------------------------------------------------------------
// Returns the max trade timestamp seen for (sym; venue).
// Returns 0Np if no data has been received for that pair yet.

.pythonfeed.maxtime:{[sym;venue]
  row:.pythonfeed.maxtimes (sym;venue);
  $[99h=type row; row`maxtime; 0Np]
  }

// ---------------------------------------------------------------------------
// upd — ROOT namespace.
// Receives .u.upd[table; coldata] calls from Python feed handlers via pykx.
// Forwards to tickerplant, then updates local metadata.
// ---------------------------------------------------------------------------

upd:{[t;x]
  h:neg .servers.gethandlebytype[.pythonfeed.tptypes;`any];
  if[0Ni~neg h;
    .lg.w[`pythonfeed;"no tickerplant handle — dropping ",
      (string count x 0)," rows for ",string t];
    .pythonfeed.incrcount[t;x];
    :()
    ];
  h(`.u.upd;t;x);
  if[t=`trade; .pythonfeed.updmaxtimes[x]];
  .pythonfeed.incrcount[t;x]
  }

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

.api.add[`.pythonfeed.maxtime;1b;
  "Return max trade timestamp for sym+venue — used by feed handlers for backfill";
  "sym(symbol) venue(symbol)";
  "timestamp"]

.lg.o[`pythonfeed;"pythonfeed process initialised"]
