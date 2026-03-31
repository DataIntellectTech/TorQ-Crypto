// pythonfeed.q — kdb+ receiver process for Python WebSocket feed manager
// Accepts IPC connections from Python feeds, forwards data to tickerplant,
// and serves backfill queries for reconnecting feeds.

// Runtime symbol map — updated via symboldiscovery IPC messages from Python.
// Not a TP-routed table; kept in-process only.
.crypto.symmap:([]
  canonical_symbol:`symbol$();
  venue:`symbol$();
  venue_symbol:`symbol$();
  base:`symbol$();
  quote:`symbol$();
  instrument_type:`symbol$();
  tick_size:`float$();
  mapping_verified:`boolean$()
  )

\d .pythonfeed

// Configuration — all overridable in appconfig/settings/pythonfeed.q
tablelist:@[value;`tablelist;`trade`exchange_top`symboldiscovery]
loglevel:@[value;`loglevel;`info]

// upd — receives rows from Python feed manager and forwards to tickerplant.
// symboldiscovery updates are handled in-process (not forwarded to TP).
// Data is forwarded async via neg handle, same pattern as bhexfeed/okexfeed.
upd:{[t;x]
  if[t=`symboldiscovery;
    .crypto.symmap upsert x;
    .lg.o[`pythonfeed;"symboldiscovery updated: ",string[count x]," rows"];
    :()];
  h:neg .servers.gethandlebytype[`tickerplant;`any];
  if[null h; .lg.e[`pythonfeed;"no tickerplant handle, dropping ",string[t]," update"]; :()];
  // Log exactly what is being forwarded to the tickerplant
  .lg.o[`pythonfeed;"TP upd table=",string[t]," col_count=",string[count x]," row_count=",string[count first x]];
  .lg.o[`pythonfeed;"TP upd types=",","sv string type each x];
  .lg.o[`pythonfeed;"TP upd first_vals=",","sv {$[0>type x;string x;","sv string x]} each x];
  // x arrives from Python as a kx.List of typed column vectors — pass through directly
  h(`.u.upd;t;x)
 };

// upd_discovery — explicit entry point called by Python on startup discovery.
// Updates the in-memory runtime symbol map in .crypto.symmap.
upd_discovery:{[t;x]
  upd[t;x]
 };

// maxtime — returns the most recent timestamp for a given canonical sym
// and exchange in the trade table.  Called by Python feeds on reconnect to
// determine the start of any backfill window.
// Queries the RDB via IPC since trade is not stored in pythonfeed.
// Returns 0Np (null timestamp) if no data exists or on error.
maxtime:{[sym;exch]
  h:.servers.gethandlebytype[`rdb;`any];
  if[null h; .lg.w[`pythonfeed;"maxtime: no rdb handle, returning null"]; :0Np];
  @[h;({[x;y] exec max time from `trade where sym=x,exchange=y};sym;exch);
    {[s;e;err] .lg.e[`pythonfeed;"maxtime query failed sym=",(string s)," exch=",(string e),": ",err]; 0Np}[sym;exch]]
 };

// initconn — register server connections (called at process start)
init:{[]
  // CONNECTIONS (tickerplant, rdb) are set in appconfig/settings/pythonfeed.q before startup
  .lg.o[`pythonfeed;"pythonfeed initialised, awaiting Python feed connections"]
 };

\d .

// Expose upd at root — Python feeds call conn("upd",...) per TorQ convention
upd:.pythonfeed.upd

// Handler registrations — use .dotz.set so other TorQ handlers are preserved
.dotz.set[`.z.po;{[w]
  .lg.o[`pythonfeed;"Python feed connected, handle: ",string[w]]
 }];

.dotz.set[`.z.pc;{[w]
  .lg.o[`pythonfeed;"Python feed disconnected, handle: ",string[w]]
 }];

// API registration
.api.add[`.pythonfeed.upd;0b;"Receive data rows from Python feed and forward to tickerplant";"upd[`trade;rows]";"::"];
.api.add[`.pythonfeed.upd_discovery;0b;"Receive symbol discovery rows and update runtime symmap";"upd_discovery[`symboldiscovery;rows]";"::"];
.api.add[`.pythonfeed.maxtime;1b;"Return max time for sym+exchange in trade table (used for backfill)";"`BTC-USDT`binance";"timestamp"];

.pythonfeed.init[];
