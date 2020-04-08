# TorQ-Crpyto Configuration

### Feeds  
Available feeds with this pack include the following:    
 - OKEX (okex) API: [https://www.okex.com/docs/en/ ]
 - DigiFinex (finex) API: [https://docs.digifinex.vip/en-ww/v3/ ]
 - Huobi (huobi) API: [https://huobiapi.github.io/docs/spot/v1/en/#introduction ]
 - ZB (zb) API: [https://www.zb.com/api]
 - Blue Helix (bhex) API: [https://github.com/bhexopen/BHEX-OpenApi ]  

    THINGS TO POSSIBLY ADD: How to add a new feed?

### Sym Configuration  
Each exchange may have a different way of identifiying a sym, therefore syms must be mapped
to one common identifier. If a new exchange is to be added or an existing sym needs to be
changed, this can be configured in `appconfig/symmap.csv`.   

The default available syms are Bitcoin/Tether (BTCUSDT) and Ethereum/Tether (ETHUSDT).Syms may
be switched on, or new syms added by navigating to `appconfig/symconfig.csv` and editing the 
table to turn on specific syms for specific exchanges.

    // Edit appconfig/symconfig.csv
    sym,finexsym,huobisym,okexsym,zbsym,bhexsym
    BTCUSDT,1,1,1,1,1
    ETHUSDT,1,1,1,1,1
    LTCUSDT,0,0,0,0,0
    XRPUSDT,1,1,1,1,1    // <--- Change from 0 to 1 to switch on sym in individual exchanges or all
    EOSUSDT,0,0,0,0,0
    ..
Note: You must restart processes after making this change for it to take effect.
                       // can user just restart RDB with this change?

    // In the RDB process
    q)exec distinct sym from exchange_top
    `u#`BTCUSDT`ETHUSDT`XRPUSDT

### Frequency of querying feed APIs and limit of depth of market  
When querying for data from the cryptocurrencies APIs, the default for limit of depth of market returned is 10 records.
This means we're limited to 10 bid records and 10 ask records.  
The frequency of querying is defaulted to every 30 seconds. Both these defaults may be adjusted for all excahnges in `appconfig/settings/default.q`.

If exchange-specific limit of depth and frequency is required, the user may edit the individual feed scripts.
For example, for the exchange HUOBI, we require a bigger capture of data but can query less frequently.
In the file `appconfig/settings/huobifeed.q`, navigate to where .huobi.limit and .huobi.freq is set (line 15 and 16)
and set these to the required values.  

    limit: "20"          // Query for 20 records, type must be string
    freq:0D00:00:45.000  // Query every 45 seconds, type must be timespan
Note: Remember to restart processes (can use `. torq.sh restart all`)
