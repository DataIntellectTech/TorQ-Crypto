// Bespoke WDB config for TorQ Crypto

\d .wdb
savedir:hsym `$getenv[`KDBWDB]          // location to save wdb data
hdbdir:hsym`$getenv[`KDBHDB]            // move wdb database to different location
sortslavetypes:()                       // WDB doesn't need to connect to sortslaves
tickerplanttypes:`tickerplant           // connect to a standard tickerplant (not segemented)
mode:`saveandsort                       // subscribe, write to disk, sort+move to HDB at EOD
ignorelist:`heartbeat`logmsg`lastprice`consolidatedmid  // intraday-only tables: do not save
sortcsv:hsym`$getenv[`KDBAPPCONFIG],"/sort.csv"         // app-managed sort config

\d .servers
CONNECTIONS:`tickerplant`sort`gateway`rdb`hdb
