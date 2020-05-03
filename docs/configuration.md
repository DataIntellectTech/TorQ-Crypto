# TorQ-Crpyto Configuration


### Symbol Configuration  

Symbol subscription is specified on a per exchange in appconfig/symconfig.csv. In this file we have included 15 symbols which are common across the 5 exchanges, but by default only Bitcoin and Ethereum are subscribed to.

![Sym Config](graphics/symconfig.png)

This symbol configuration has a dependency on appconfig/symap.csv which maps tickers across exchanges to one common identifier. Therefore if a new crypto currency is to be added both of these files must be taken into consideration. 

![Sym Config2](graphics/symconfig.png)

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
