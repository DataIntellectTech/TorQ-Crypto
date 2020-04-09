# TorQ-Crypto Gateway Functions

## Summary table of Functions

|                 Function                 |               Description                |
| :--------------------------------------: | :--------------------------------------: |
|    **orderbook**[\`sym\`exchanges\`timestamp\`window!(symbol;symbol;timestamp;second)]    | Returns level 2 orderbook. |
|    **ohlc**[\`date\`sym\`exchanges\`quote\`byexchange!(date;symbol;symbol;symbol;boolean)] | Returns open, high, low and close data for bid and/or ask data. |
|    **topofbook**[\`sym\`exchanges\`starttime\`endtime\`bucket!(symbol;symbol;timestamp;timestamp;second)] | Returns the level 1 orderbook. |
|    **arbitrage**[\`sym\`exchanges\`starttime\`endtime\`bucket!(symbol;symbol;timestamp;timestamp;second)] | Returns topofbook table with how much profit can be made with arbitrage opportunities. |

Here we discuss the use and give examples of pre-made functions available with the TorQ-Crypto package.
All the examples within this section are executed from within the RDB/HDB process.

#### Orderbook Function
Returns level 2 orderbook and takes a dictionary parameter as an argument.   
Available keys include: sym, exchanges, timestamp and window.   
Sym is the only mandatory key that user must pass in, others may revert to defaults.   
If a null parameter is passed in the dictionary argument, this will remove the relevant key from the where clause of the query.
This function may be run on the RDB and/or HDB and will adjust defaults for queries accordingly.   

###### Example usage:  
Get latest BTCUSDT data from exchange table:      

    q)// Example output
    
    q)orderbook[(enlist `sym)!enlist (`BTCUSDT)]
    exchange_b  bidSize    bid     ask      askSize    exchange_a 
    -------------------------------------------------------------
    okex        2.076665   6951.4  6949.5   0.511969   huobi
    okex        0.001      6950.7  6949.9   0.001      huobi
    okex        0.0064022  6950.6  6950.42  7.082231   bhex 
    okex        0.3        6950.5  6950.49  0.2        bhex 
    ..  

Get BTCUSDT data from finex and bhex for last 2 hours:     

    q)// Example output
    
    q)orderbook[`sym`timestamp`exchanges`window!(`BTCUSDT;.proc.cp[];`finex`bhex;02:00:00)]
    exchange_b  bidSize                 bid                 ask                 askSize               exchange_a 
    ------------------------------------------------------------------------------------------------------------
    bhex        0.064843999999999999    7295.9899999999998  7296.7799999999997  0.18113599999999999   bhex
    bhex        0.1767                  7295.8999999999996  7296.79             0.110959              bhex
    bhex        0.10000000000000001     7295.8800000000001  7297.04             0.96191800000000005   bhex
    bhex        0.037999999999999999    7295.8699999999999  7297.2200000000003  0.251                 bhex
    ..


#### OHLC Function
Returns the OHLC data for bid and/or ask data and tales a dictionary parameter as an argument.  
Available keys include: date, sym, quote, byexchange.
The only parameter that must be passed in is sym, the others will revert to defaults.  

###### Example usage:
Get latest OHLC data for BTCUSDT:  

    q)// Example output
    
    q)ohlc[enlist[`sym]!enlist `BTCUSDT]
    date       sym    | openBid closeBid bidHigh bidLow  openAsk closeAsk askHigh askLow
    ------------------| -----------------------------------------------------------------
    2020.04.08 BTCUSDT| 7354.4  7309.2   7369.9  7241.15 7355.1  7309.5   7370.37 7241.72


Get only bid data by exchange for BTCUSDT:  

    q)// Example output
    
    q)ohlc[`date`sym`exchanges`quote`byexchange!(.z.d;`BTCUSDT;`finex`okex;`bid;1b)]
    date       sym     exchange| openBid closeBid bidHigh bidLow
    ---------------------------| --------------------------------
    2020.04.09 BTCUSDT finex   | 7354.33 7296.42  7366.43 7245.03
    2020.04.09 BTCUSDT okex    | 7348.2  7297.8   7369.9  7242


#### Topofbook Function  
Creates a table showing top of the book for each exchange (Level 1) at a given time.  
Available keys include: sym, exchanges, starttime, endtime, bucket.
Sym is the only mandatory parameter that the use must pass in, the other will revert to defaults.  
If a null parameter value is passed in, this will remove the pertinent where clause from the query.  
This function can be run on the RDB and/or HDB and will adjust queries accordingly.  

###### Example usage:
Get level 1 data for BTCUSDT from all exchanges:  

    q)// Example output
    
    q)topofbook[(enlist `sym)!enlist `BTCUSDT]
    exchangeTime                  huobiBid huobiAsk huobiBidSize huobiAskSize bhexBid bhexAsk bhexBid..
    -------------------------------------------------------------------------------------------------..
    2020.04.09D00:01:00.000000000 7341.7   7343.6   0.048634     0.012121     7351.66 7351.74 0.19005..
    2020.04.09D00:02:00.000000000 7324.1   7325.9   2.271624     0.295234     7326.57 7326.65 0.13200..
    2020.04.09D00:03:00.000000000 7336.7   7336.8   0.1          0.406        7333.9  7335.44 0.07484..
    2020.04.09D00:04:00.000000000 7332.7   7334.2   2.15104      2.089884     7334.47 7335.32 1.93197..

Get level 1 data in the last 2 hours in buckets of 5 mins for BTCUSDT:  

    q)// Example output
    
    q)topofbook[`sym`exchanges`starttime`endtime`bucket!(`BTCUSDT;`;.proc.cp[]-02:00:00;.proc.cp[];00:05:00)]
    exchangeTime                  okexBid okexAsk okexBidSize okexAskSize zbBid   zbAsk   zbBidSize z..
    -------------------------------------------------------------------------------------------------..
    2020.04.09D09:05:00.000000000 7321.8  7321.9  0.1506324   0.001       7319.49 7322.47 0.272     0..
    2020.04.09D09:10:00.000000000 7317    7317.1  0.8687434   0.002       7319.08 7322.38 1.472     0..
    2020.04.09D09:15:00.000000000 7314.9  7315    3.531714    0.001       7316.1  7319.28 1.6       0..
    2020.04.09D09:20:00.000000000 7314.8  7314.9  0.4368178   0.00114608  7311.13 7314.58 0.039     0..
    ..  

#### Arbitrage Function  
Arbitrage is the simultaneous buying and selling of a financial insturment in different markets to 
take advantage of the difference in price. This function will look for opportunities of arbitrage 
and caluclate to potential profit to be made.  

The Arbitrage functtion calls the topofbook function and adds columns saying if there is a chance 
of risk free profit and what that profit is. Available keys include: sym, exchanges, starttime, 
endtime, bucket. Sym is the only required key, all other keys will revert to defaults. 

###### Example usage:  
Get arbitrage data for BTCUSDT from all exchanges:  

    q)// Example output
    
    q)arbitrage[(enlist `sym)!enlist `BTCUSDT]
    exchangeTime                  huobiBid huobiAsk huobiBidSize huobiAskSize bhexBid bhexAsk bhexBid..
    -------------------------------------------------------------------------------------------------..
    2020.04.09D00:01:00.000000000 7341.7   7343.6   0.048634     0.012121     7351.66 7351.74 0.19005..
    2020.04.09D00:02:00.000000000 7324.1   7325.9   2.271624     0.295234     7326.57 7326.65 0.13200..
    2020.04.09D00:03:00.000000000 7336.7   7336.8   0.1          0.406        7333.9  7335.44 0.07484..
    2020.04.09D00:04:00.000000000 7332.7   7334.2   2.15104      2.089884     7334.47 7335.32 1.93197..
    ..

Get arbitrage data for the last 2 hours in buckets of 5 mins for BTCUSDT on finex and zb exchanges:  
 
    // Example output
    
    q)arbitrage[`sym`exchanges`starttime`endtime`bucket!(`BTCUSDT;`finex`zb;.proc.cp[]-02:00:00;.proc.cp[];00:05:00)]
    exchangeTime                  finexBid finexAsk finexBidSize finexAskSize zbBid   zbAsk   zbBidSi..
    -------------------------------------------------------------------------------------------------..
    2020.04.09D09:10:00.000000000 7314.05  7314.15  0.0005       0.0029                              ..
    2020.04.09D09:15:00.000000000 7317.09  7317.1   0.0812       0.0021       7316.1  7319.28 1.6    ..
    2020.04.09D09:20:00.000000000 7317.96  7318.57  0.1625       0.0069       7311.13 7314.58 0.039  ..
    2020.04.09D09:25:00.000000000 7312.85  7315.02  0.0005       0.0006       7313.97 7316.47 0.273  ..
    ..


### Using Functions via Gateway  

To use these functions for synchronous querying of the RDB/HDB:  
- open a handle to the gateway with

    ``q)h:hopen `:localhost:xxxx:admin:admin``  
    ``// Where xxxx is the port number of the gateway`` 

- use the following template  
``
h(`.gw.syncexec;"function[dictionary arguments]";`serverstoquery)
``  
The following are some example queries to the RDB and/or the HDB via the gateway.  

Retrieve today's level 2 data for \`SYMBOL from the zb exchange:  

    h(`.gw.syncexec;"orderbook[`sym`exchanges!(`SYMBOL;`zb)]";`rdb) 

Retrieve level 2 data for BTCUSDT from okex and zb excahnges for 30.03.2020:  

    h(`.gw.syncexec;"orderbook[`timestamp`sym`exchanges`window!(2020.03.30D09:00:00.000000;`BTCUSDT;`okex`zb;02:00:00)]";`hdb)
    exchange_b bidSize   bid     ask     askSize    exchange_a
    ----------------------------------------------------------
    okex       0.2903761 6269.7  6269.12 0.0008     zb
    okex       0.001     6269.5  6269.8  0.00225353 okex
    okex       0.001     6269.2  6270.2  0.026      zb
    okex       0.016661  6269.1  6270.26 0.043      zb


Retreive level 1 data for a single non-null sym from the huobi and finex exchanges on 29.03.2020:
``
h(`.gw.syncexec;"topofbook[`sym`exchanges`starttime`endtime!(`BTCUSDT;`huobi`finex;2020.03.29D00:00:00.0000000;2020.03.29D23:59:59.0000000)]";`hdb)
``  
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
    ..
