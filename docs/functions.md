# TorQ-Crypto Gateway Functions


## Summary table of Functions

      |                 Function                 |               Description                |
      | :--------------------------------------: | :--------------------------------------: |
      |    **orderbook**[\`sym\`exchanges\`timestamp\`window!(symbol;symbol;timestamp;second)]    | Returns level 2 orderbook data at a specific point in time. |
      |    **ohlc**[\`date\`sym\`exchanges\`quote\`byexchange!(date;symbol;symbol;symbol;boolean)] | Returns open, high, low and close data for bid and/or ask data. |
      |    **topofbook**[\`sym\`exchanges\`starttime\`endtime\`bucket!(symbol;symbol;timestamp;timestamp;second)] | Returns level top of book data across exchanges. |
      |    **arbitrage**[\`sym\`exchanges\`starttime\`endtime\`bucket!(symbol;symbol;timestamp;timestamp;second)] | Returns topofbook with an arbitrage indicator. |

Here we discuss the use and give examples of pre-made functions available with the TorQ-Crypto package.
All the examples within this section are executed from within the RDB/HDB process.

## Summary table of Functions

FORMAT:1A

<center>

|                 Function                 |               Description                |
| :--------------------------------------: | :--------------------------------------: |
|    **ohlc**                              | Returns open, high, low and close quote data. |
|    **orderbook**                         | Returns level 2 orderbook data at a specific point in time. |
|    **topofbook**                         | Returns top of book data within a given time range. |
|    **arbitrage**                         | Topofbook with additional arbitrage and profit columns. |

</center>

#### OHLC Function
Returns the OHLC data for bid and/or ask data and takes a dictionary parameter as an argument.

|      Keys       |  Mandatory  |    Types     |     Defaults      |     Example      |    Description    |
| :-------------: | :---------: | :----------: | :---------------: | :--------------: |  :--------------: |
| sym             | 1b          |-12 12h       | All symbols       | \`BTCUSDT        | Symbol(s) of interest |
| date            | 0b          |-14 14h       | Most recent date  | 2020.03.29       | Date(s) to query |
| exchanges       | 0b          |-14 14h       | All exchanges     | \`finex`zb       | Exchange(s) of interest |
| quote           | 0b          | -12 12h      | Bid & Ask         | \`bid            | Quote of interest |
| byexchange      | 0b          | -1h          | 0b                | 1b               | Breakdown by exchange |

###### Example usage:

Get BTCUSDT data broken down by exchange:

    q)ohlc[`date`sym`exchanges`quote`byexchange!(2020.03.29 2020.03.30;`BTCUSDT;`finex`okex`zb;`bid;1b)]
    date       sym     exchange| openBid closeBid bidHigh bidLow
    ---------------------------| --------------------------------
    2020.03.29 BTCUSDT finex   | 6238.21 5893.46  6263.52 5870
    2020.03.29 BTCUSDT okex    | 6250.9  5883.4   6263.3  5871.5
    2020.03.29 BTCUSDT zb      | 6241.94 5881.93  6262.12 5879.52
    2020.03.30 BTCUSDT finex   | 5879.75 6388.6   6571.28 5864.36
    2020.03.30 BTCUSDT okex    | 5888.7  6393.9   6583.9  5860.5
    2020.03.30 BTCUSDT zb      | 5885.56 6387.76  6570.58 5861.52


#### Orderbook Function
Returns level 2 orderbook and takes a dictionary parameter as an argument.

| Dictionary Keys |  Mandatory  |    Types     |     Defaults      |     Example      |  Description    |
| :-------------: | :---------: | :----------: | :---------------: | :--------------: |:--------------: |
| sym             | &#x2611;    | -11h         | All syms          | \`BTCUSDT        | The symbol of interest |
| exchanges       | &#x2612;    |-11h, 11h     | All exchanges     | \`finex          | The exchanges to be queried |
| timestamp       | &#x2612;    | -12h         | If proctype is rdb, default time is the last time data is received. If proctype is hdb, default time is the last time data was received for the previous day| 2020.04.16D09:40:00.0000000 | The time to subtract the window from |
| window          | &#x2612;    | -18h         | 2*.crypto.deffreq | 00:00:30         | The amount of time from the timestamp to look at |
    
If a null parameter is passed in the dictionary argument, this will remove the relevant key from the where clause of the query.
This function may be run on the RDB and/or HDB and will adjust defaults for queries accordingly.   

###### Example usage:  
Get latest BTCUSDT data from exchange table:      

    q)orderbook[(enlist `sym)!enlist (`BTCUSDT)]
    exchange_b  bidSize    bid     ask      askSize    exchange_a 
    -------------------------------------------------------------
    okex        2.076665   6951.4  6949.5   0.511969   huobi
    okex        0.001      6950.7  6949.9   0.001      huobi
    okex        0.0064022  6950.6  6950.42  7.082231   bhex 
    okex        0.3        6950.5  6950.49  0.2        bhex 
    ..  

Get BTCUSDT data from finex and bhex within a window of 2 hours from the timestamp provided:     

    q)orderbook[`sym`timestamp`exchanges`window!(`BTCUSDT;.proc.cp[];`finex`bhex;02:00:00)]
    exchange_b  bidSize                 bid                 ask                 askSize               exchange_a 
    ------------------------------------------------------------------------------------------------------------
    bhex        0.064843999999999999    7295.9899999999998  7296.7799999999997  0.18113599999999999   bhex
    bhex        0.1767                  7295.8999999999996  7296.79             0.110959              bhex
    bhex        0.10000000000000001     7295.8800000000001  7297.04             0.96191800000000005   bhex
    bhex        0.037999999999999999    7295.8699999999999  7297.2200000000003  0.251                 bhex
    ..


#### OHLC Function
Returns the OHLC data for bid and/or ask data and takes a dictionary parameter as an argument.  

| Dictionary Keys |  Mandatory  |    Types     |     Defaults      |     Example      |    Description    |
| :-------------: | :---------: | :----------: | :---------------: | :--------------: |  :--------------: |
| sym             | &#x2611;    |-12h          | All syms          | \`BTCUSDT        | The symbol of interest |
| date            | &#x2612;    |-14h          | All exchanges     | \`finex          | The date to retreive data for |
| quote           | &#x2612;    | -12h, 12h    | All bid and ask columns | \`bid      | The bid and/or ask columns required by the user |
| byexchange      | &#x2612;    | -1h          | 0b                | 1b               |Allows user to filter ohlc data at individual exchange level |

###### Example usage:
Get latest OHLC data for BTCUSDT:  

    q)ohlc[enlist[`sym]!enlist `BTCUSDT]
    date       sym    | openBid closeBid bidHigh bidLow  openAsk closeAsk askHigh askLow
    ------------------| -----------------------------------------------------------------
    2020.04.08 BTCUSDT| 7354.4  7309.2   7369.9  7241.15 7355.1  7309.5   7370.37 7241.72


Get only bid data by exchange for BTCUSDT:  

    q)ohlc[`date`sym`exchanges`quote`byexchange!(.z.d;`BTCUSDT;`finex`okex;`bid;1b)]
    date       sym     exchange| openBid closeBid bidHigh bidLow
    ---------------------------| --------------------------------
    2020.04.09 BTCUSDT finex   | 7354.33 7296.42  7366.43 7245.03
    2020.04.09 BTCUSDT okex    | 7348.2  7297.8   7369.9  7242


#### Topofbook Function  
Creates a table showing top of the book for each exchange (Level 1) at specified intervals between two timestamps.

| Dictionary Keys | Mandatory  |    Types     |     Defaults      |     Example      |  Description      |
| :-------------: | :--------: | :----------: | :---------------: | :--------------: | :---------------: |
| sym             | &#x2611;   | -11h         | All syms          | \`BTCUSDT        | The symbol of interest |
| exchanges       | &#x2612;   | -11h, 11h    | All exchanges     | \`finex          | The date to retreive data for chosen exchanges|
| starttime       | &#x2612;   | -12h         | If proctype is rdb, the start of day is used. If proctype is hdb, start of previous day is used | 2020.04.16D09:40:00.000000 | The time at which to begin looking at data |
| endtime         | &#x2612;   | -12h         | If proctype is rdb, the query time is used. If proctype is hdb, the end of previos day is used.  | 2020.04.16D12:00:00.000000 |The time at which to stop looking at data |
| bucket          | &#x2612;   | -18h         | 00:01:00          | 00:02:00          | What bucket of time to group data by |
  
If a null parameter value is passed in, this will remove the pertinent where clause from the query.  
This function can be run on the RDB and/or HDB and will adjust queries accordingly.  

###### Example usage:
Get level 1 data for BTCUSDT from all exchanges:  

    q)topofbook[(enlist `sym)!enlist `BTCUSDT]
    exchangeTime                  okexBid            okexAsk            okexBidSize            okexAskSize           huobiBid           huobiAsk           huobiBidSize           huobiAskSize ..
    -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------..
    2020.04.15D00:01:00.000000000 6856               6856.1000000000004 0.17378205999999999    0.019619279999999999  6859.1000000000004 6859.1999999999998 0.082798999999999998   0.118543     ..
    2020.04.15D00:02:00.000000000 6853.6000000000004 6853.6999999999998 0.24825765999999999    0.0040000000000000001 6851.6000000000004 6851.8000000000002 0.037240000000000002   2.27919200000..
    2020.04.15D00:03:00.000000000 6815.5             6815.6000000000004 0.14455156999999999    0.0039345500000000002 6813.5             6813.6999999999998 0.170738               0.25659300000..
    2020.04.15D00:04:00.000000000 6827.8999999999996 6828               2.6327339599999999     0.0040000000000000001 6828.3000000000002 6829.8999999999996 0.206536               0.12814600000..
    2020.04.15D00:05:00.000000000 6831.8999999999996 6832               0.61994375000000002    0.001                 6830.3000000000002 6830.6000000000004 0.002                  1.69569799999..
    2020.04.15D00:06:00.000000000 6827.8000000000002 6827.8999999999996 0.58100854000000002    0.002                 6830.8000000000002 6831.3000000000002 2.1928580000000002     0.12042799999..
    2020.04.15D00:07:00.000000000 6833.6000000000004 6833.6999999999998 0.20866628000000001    0.001                 6832.6999999999998 6832.8000000000002 0.10000000000000001    2.10644400000..
    2020.04.15D00:08:00.000000000 6836.3000000000002 6836.3999999999996 0.021672509999999999   0.0050000000000000001 6833.1000000000004 6834.6999999999998 0.10000000000000001    0.012423     ..
    2020.04.15D00:09:00.000000000 6837.1999999999998 6837.3000000000002 0.055465779999999999   0.001                 6835.1999999999998 6836.6000000000004 0.0074260000000000003  1.99113199999..
    2020.04.15D00:10:00.000000000 6829               6829.1000000000004 0.089577180000000006   0.0015053             6831.8000000000002 6832.3000000000002 0.050000000000000003   0.00077399999..
    ..

Get level 1 data in the last 2 hours in buckets of 5 mins for BTCUSDT:  

    q)topofbook[`sym`exchanges`starttime`endtime`bucket!(`BTCUSDT;`;.proc.cp[]-02:00:00;.proc.cp[];00:05:00)]
    exchangeTime                  finexBid           finexAsk           finexBidSize         finexAskSize           huobiBid           huobiAsk           huobiBidSize         huobiAskSize    ..
    -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------..
    2020.04.15D14:15:00.000000000 6728.4399999999996 6738.6499999999996 0.1011               0.0014                 6735.6000000000004 6735.6999999999998 0.24300099999999999  0.32364700000000..
    2020.04.15D14:20:00.000000000 6727.29            6729.5             0.32600000000000001  0.00059999999999999995 6733.6999999999998 6733.8000000000002 0.46999999999999997  0.43773800000000..
    2020.04.15D14:25:00.000000000 6733.9499999999998 6735               0.039600000000000003 0.0040000000000000001  6736.5             6736.6000000000004 0.37073800000000001  0.07424899999999..
    2020.04.15D14:30:00.000000000 6745.5200000000004 6746.0699999999997 0.0235               0.0088000000000000005  6741.1000000000004 6741.8000000000002 5.5815239999999999   0.07503700000000..
    2020.04.15D14:35:00.000000000 6757.5200000000004 6761.3000000000002 3.4832000000000001   0.010500000000000001   6761.3999999999996 6762.8000000000002 0.1144               0.08823499999999..
    2020.04.15D14:40:00.000000000 6744.46            6754.6199999999999 0.69850000000000001  0.0079000000000000008  6750               6750.8000000000002 1.0366550000000001   0.00512699999999..
    2020.04.15D14:45:00.000000000 6737.9799999999996 6737.9899999999998 0.25                 0.0016999999999999999  6739.6000000000004 6739.6999999999998 0.24845300000000001  0.150533        ..
    2020.04.15D14:50:00.000000000 6740.0299999999997 6741.1000000000004 0.5                  0.0011000000000000001  6739.8999999999996 6740               0.068198999999999996 1.17723159104302..
    2020.04.15D14:55:00.000000000 6733.3299999999999 6733.3999999999996 0.79620000000000002  0.56079999999999997    6729.6999999999998 6730               0.41671999999999998  0.03428599999999..
    2020.04.15D15:00:00.000000000 6721.0299999999997 6721.1599999999999 0.2089               0.0061999999999999998  6719.1000000000004 6720.1000000000004 0.25274099999999999  0.001639        ..
    ..  

#### Arbitrage Function  
This function will look for opportunities of arbitrage by considering the best bid/ask across exchanges 
(therefore only looks at top of book data) and indicates the profitability of any arbitrage opportunities.
Exchange fees are not accounted for, so the actual profit will be lower than shown.

| Dictionary Keys |     Mandatory    |    Types     |     Defaults      |     Example      | Description      |
| :-------------: | :--------------: | :----------: | :---------------: | :--------------: | :--------------: |
| sym             | &#x2611;         |-12h          | All syms          | \`BTCUSDT |The symbol of interest |
| exchanges       | &#x2612;         |-11h, 11h     | All exchanges     | \`finex |The date to retreive data for chosen exchanges |
| starttime       | &#x2612;         |-12h          | If proctype is rdb, the start of day is used. If proctype is hdb, start of previous day is used | 2020.04.16D09:40:00.000000 |The time at which to begin looking at data |
| endtime         | &#x2612;         |-12h          | If proctype is rdb, the query time is used. If proctype is hdb, the end of previos day is used.  | 2020.04.16D12:00:00.000000 |The time at which to stop looking at data |
| bucket          | &#x2612;         |-18h          | 00:01:00          | 00:02:00          |  What bucket of time to group data by |

The Arbitrage function calls the topofbook function and adds columns saying if there is a chance 
of risk free profit and what that potential profit is.  

###### Example usage:  
Get arbitrage data for BTCUSDT from all exchanges:  

    q)arbitrage[(enlist `sym)!enlist `BTCUSDT]
    exchangeTime                  huobiBid huobiAsk huobiBidSize huobiAskSize bhexBid bhexAsk bhexBid..
    -------------------------------------------------------------------------------------------------..
    2020.04.09D00:01:00.000000000 7341.7   7343.6   0.048634     0.012121     7351.66 7351.74 0.19005..
    2020.04.09D00:02:00.000000000 7324.1   7325.9   2.271624     0.295234     7326.57 7326.65 0.13200..
    2020.04.09D00:03:00.000000000 7336.7   7336.8   0.1          0.406        7333.9  7335.44 0.07484..
    2020.04.09D00:04:00.000000000 7332.7   7334.2   2.15104      2.089884     7334.47 7335.32 1.93197..
    ..

Get arbitrage data for the last 2 hours in buckets of 5 mins for BTCUSDT on finex and zb exchanges:  
 
    q)arbitrage[`sym`exchanges`starttime`endtime`bucket!(`BTCUSDT;`finex`zb;.proc.cp[]-02:00:00;.proc.cp[];00:05:00)]
    exchangeTime                  finexBid finexAsk finexBidSize finexAskSize zbBid   zbAsk   zbBidSi..
    -------------------------------------------------------------------------------------------------..
    2020.04.09D09:10:00.000000000 7314.05  7314.15  0.0005       0.0029                              ..
    2020.04.09D09:15:00.000000000 7317.09  7317.1   0.0812       0.0021       7316.1  7319.28 1.6    ..
    2020.04.09D09:20:00.000000000 7317.96  7318.57  0.1625       0.0069       7311.13 7314.58 0.039  ..
    2020.04.09D09:25:00.000000000 7312.85  7315.02  0.0005       0.0006       7313.97 7316.47 0.273  ..
    ..


### Using Functions via Gateway  
We recommend using these functions for synchronous querying of the RDB/HDB via the gateway.  
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
    ..
