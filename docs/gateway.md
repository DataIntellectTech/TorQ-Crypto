### Gateway

We recommend using these functions for synchronous querying of the RDB/HDB via the gateway.

We recommend executing the previously discussed database functions through the gateway processes
to avail of query routing and load balancing. Full gateway functionality is discussed [here](http://aquaqanalytics.github.io/TorQ/Processes/#gateway).





- open a handle to the gateway with

    ``q)h:hopen `:localhost:port:user:pass ``

- use the following template
``
    h(`.gw.syncexec;"function[dictionary]";`serverstoquery)
``

The following are some example queries to the RDB and/or the HDB via the gateway.

    ``h(`.gw.syncexec;"orderbook[`sym`exchanges!(`SYMBOL;`zb)]";`rdb)``

    ``h(`.gw.syncexec;"orderbook[`timestamp`sym`exchanges`window!(2020.03.30D09:00:00.000000;`BTCUSDT;`okex`zb;02:00:00)]";`hdb)``


    ``h(`.gw.syncexec;"topofbook[`sym`exchanges`starttime`endtime!(`BTCUSDT;`huobi`finex;2020.03.29D00:00:00.0000000;2020.03.29D23:59:59.0000000)]";`hdb)``

### Custom queries
The above function are for users ease-of-use. Users may build their own queries for their requirements.

For example, to retrieve the best ask and best bid per hour from finex and zb exchanges on 29.03.2020:

    q)h(`.gw.syncexec;"select min ask, max bid by (`date$exchangeTime)+60+60 xbar exchangeTime.second, exchange from exchange_top where date=2020.03.29,  exchange in `finex`zb";`hdb)
    exchangeTime                  exchange| ask    bid
    --------------------------------------| --------------
    2020.03.29D00:01:00.000000000 finex   | 130.93 6249.7
    2020.03.29D00:01:00.000000000 zb      | 131.21 6253.13
    2020.03.29D00:02:00.000000000 finex   | 131.57 6260.95
    2020.03.29D00:02:00.000000000 zb      | 131.44 6262.12

