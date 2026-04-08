// Bespoke Sort config for TorQ Crypto

\d .wdb
savedir:hsym `$getenv[`KDBWDB]          // location to save wdb data
hdbdir:hsym`$getenv[`KDBHDB]            // move wdb database to different location
tickerplanttypes:sorttypes:()           // sort doesn't need these connections
sortcsv:hsym`$getenv[`KDBAPPCONFIG],"/sort.csv"  // app-managed sort config (trade, quote)

\d .servers
CONNECTIONS:`hdb`rdb`gateway`sortslave  // list of connections to make at start up

