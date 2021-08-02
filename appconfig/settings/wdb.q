// Bespoke WDB config for TorQ Crypto

\d .wdb
savedir:hsym `$getenv[`KDBWDB]          // location to save wdb data
hdbdir:hsym`$getenv[`KDBHDB]            // move wdb database to different location
sortslavetypes:()                       // WDB doesn't need to connect to sortslaves
tickerplanttypes:`tickerplant           // connect to a standard tickerplant (not segemented)

\d .servers
CONNECTIONS:`tickerplant`sort`gateway`rdb`hdb
