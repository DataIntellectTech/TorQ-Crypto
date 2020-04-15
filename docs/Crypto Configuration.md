# TorQ-Crpyto Configuration

### Feeds  
Available feeds with this pack include the following:    
 - OKEX (okex) API: https://www.okex.com/docs/en/ 
 - DigiFinex (finex) API: https://docs.digifinex.vip/en-ww/v3/ 
 - Huobi (huobi) API: https://huobiapi.github.io/docs/spot/v1/en/#introduction 
 - ZB (zb) API: https://www.zb.com/api
 - Blue Helix (bhex) API: https://github.com/bhexopen/BHEX-OpenApi

    THINGS TO POSSIBLY ADD: How to add a new feed?

### Sym Configuration  
The default available syms are Bitcoin/Tether (BTCUSDT) and Ethereum/Tether (ETHUSDT).Syms may
be switched on, or new syms added by navigating to `appconfig/symconfig.csv` and editing the 
table to turn on specific syms for specific exchanges.

    sym,finexsym,huobisym,okexsym,zbsym,bhexsym
    BTCUSDT,1,1,1,1,1
    ETHUSDT,1,1,1,1,1
    LTCUSDT,0,0,0,0,0
    XRPUSDT,1,1,1,1,1    // <--- Change from 0 to 1 to switch on sym in individual exchanges or all
    EOSUSDT,0,0,0,0,0
    ..
    
Each exchange may have a different way of identifiying a sym, therefore syms 
must be mapped to one common identifier. If a new exchange is to be added or 
an existing sym needs to be changed, this can be configured in `appconfig/symmap.csv`
and `appconfig/symconfig.csv`.

    sym,finexsym,huobisym,okexsym,zbsym,bhexsym
    Bitcoin-USDT,BTC_USDT,btcusdt,BTC-USDT,btcusdt,BTCUSDT    // <---- edit the sym column to change the common identifier
    ETHUSDT,ETH_USDT,ethusdt,ETH-USDT,ethusdt,ETHUSDT
    LTCUSDT,LTC_USDT,ltcusdt,LTC-USDT,ltcusdt,LTCUSDT
    XRPUSDT,XRP_USDT,xrpusdt,XRP-USDT,xrpusdt,XRPUSDT
    ..

To add a new sym, edit `appconfig/symmap.csv` by adding the new sym and the identifires for each excahnge.
If an exchange does not have the specific sym, leave it blank. Then edit `appconfig/symconfig.csv`, add 
the new sym and enable the sym on only the excahnges where it is available.
    
    // Add line to appconfig/symmap.csv
    ZECUSDT,ZEC_USDT,zecusdt,ZEC-USDT,,ZECUSDT
    // Add line to appconfig/symconfig.csv
    ZECUSDT,1,1,1,0,1

### Frequency of querying feed APIs and limit of depth of market  
The frequency is the time at which a query is sent to the cryptocurrencies API's
for the data to be retreived. Frequency of querying is defaulted to every 30 seconds.  

The limit of depth is the number of records to be retreived from the API. When 
querying for data from the cryptocurrencies APIs, the default for limit of depth
of market returned is 10 records. This means we're limited to 10 bid records and 
10 ask records per query.  

Both these defaults may be adjusted for all or specific exchanges in `appconfig/settings/default.q`.

For example, frequency of querying can be changed to every 2 minutes and the limit
of depth can be changed to 20 records:

    \d .crypto

    //Defaults for frequency of querying API
    deffreq : 0D00:02:00.000

    //Defaults for limit of depth of market returned
    deflimit: "20"


If exchange-specific limit of depth and frequency is required, the user may edit the individual feed scripts.
For example, for the exchange HUOBI, we require a bigger capture of data but can query less frequently.
In the file `appconfig/settings/huobifeed.q`, navigate to where .huobi.limit and .huobi.freq is set (line 15 and 16)
and set these to the required values.  
    
    \d .huobi
    
    limit: "20"          // Query for 20 records, type must be string
    freq:0D00:00:45.000  // Query every 45 seconds, type must be timespan
