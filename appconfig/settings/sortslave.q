// Settings for sortslave processes
// Sortslaves run wdb.q as sort workers.  mode:`sort keeps them on the sort
// code path so they never call subscribe[] or touch replay variables.

\d .wdb
mode:`sort                              // run as a sort worker, not a subscriber
savedir:hsym `$getenv[`KDBWDB]         // location of wdb data to sort
hdbdir:hsym `$getenv[`KDBHDB]          // hdb to reload after sort completes
tickerplanttypes:()                     // sortslave does not connect to tickerplant
numrows:100000                          // default row threshold (required by wdb internals)
numtab:`quote`trade!10000 50000         // per-table row thresholds
replaynumrows:numrows                   // rows per chunk during tp log replay
replaynumtab:numtab                     // per-table rows per chunk during tp log replay

\d .servers
CONNECTIONS:`sort`wdb
