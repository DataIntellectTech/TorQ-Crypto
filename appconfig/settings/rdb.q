// Bespoke RDB config for TorQ Crypto

\d .rdb
hdbdir:hsym`$getenv[`KDBHDB]    // the location of the hdb directory
reloadenabled:1b                // if true, the RDB will not save when .u.end is called but
                                // will clear it's data using reload function (called by the WDB)
tickerplanttypes:`tickerplant   // connect to a standard tickerplant (not segemented)
hdbtypes:()                     // connection to HDB not needed

\d .servers
CONNECTIONS:enlist `tickerplant // connect to tickerplant only
