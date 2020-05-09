# TorQ-Crypto Gateway Functions

We have created four functions that will help analyse data collected by the feeds. These functions
are loaded into the RDB and HDB processes. 

### OHLC Function
Returns the OHLC quote data for specified dates with the option to break down by exchange.

|      Keys       |  Mandatory  |    Types     |     Defaults      |     Example      |    Description    |
| :-------------  | :---------: | :----------  | :---------------  | :--------------  |  :--------------  |
| sym             | 1b          |-12 12h       | All syms          | \`BTCUSDT`ETHUSDT| Symbol(s) of interest |
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


### Orderbook Function
Returns level 2 orderbook at a specific point in time considering only quotes within the lookback window.

|      Keys       |  Mandatory  |    Types     |     Defaults      |     Example      |  Description    |
| :-------------  | :---------: | :----------  | :---------------  | :--------------  |:--------------  |
| sym             | 1b          | -11h         | N/A               | \`BTCUSDT        | Symbol of interest|
| exchanges       | 0b          |-11 11h       | All exchanges     | \`finex`okex     | Exchange(s) of interest|
| timestamp       | 0b          | -12h         | Last available time| 2020.04.16D09:40:00.0000000 | Time of orderbook|
| window          | 0b          | -18h         | 2*.crypto.deffreq | 00:00:30         | Lookback window|
    
###### Example usage:  

Get BTCUSDT orderbook with a lookback window of 1 minute:     

    q)orderbook[`sym`timestamp`exchanges`window!(`BTCUSDT;2020.03.29D15:00:00.000000000;`finex`okex`zb;00:01:00)]
    
    exchange_b bidSize    bid     ask     askSize    exchange_a
    -----------------------------------------------------------
    okex       0.3764075  6146.5  6143.51 0.0002     zb
    okex       0.30097    6146.4  6144.19 0.0004     zb
    okex       0.19998    6146.2  6145.05 0.002      finex
    okex       0.07       6146.1  6145.1  0.0008     zb
    okex       0.39996    6146    6145.3  0.002      finex
    okex       0.001      6145.8  6145.6  0.0246     zb
    okex       1.5        6145.7  6146.51 0.096      zb
    okex       0.0011     6145.6  6146.6  0.001      okex
    okex       0.00433655 6145.5  6147.5  0.001      okex
    okex       0.59994    6145.4  6147.6  0.00607957 okex
    zb         0.188      6141.1  6147.67 0.133      zb
    zb         0.043      6140.62 6147.9  0.00650741 okex
    zb         0.047      6140.61 6147.92 0.1605     finex
    zb         0.037      6140.48 6148    0.07928215 okex
    finex      1.8368     6139.74 6148.1  0.1022373  okex
    zb         0.033      6138.37 6148.2  0.2075531  okex
    finex      0.1532     6138.24 6148.3  0.504      okex
    zb         1          6137.53 6148.4  0.5139502  okex



### Topofbook Function  
Returns top of book data on a per exchange basis at set buckets between two timestamps. 

|     Keys        | Mandatory  |    Types     |     Defaults      |     Example      |  Description      |
| :-------------  | :--------: | :----------  | :---------------  | :--------------  | :---------------  |
| sym             | 1b         | -11h         | N/A               | \`BTCUSDT        | Symbol of interest |
| exchanges       | 0b         | -11 11h      | All exchanges     | \`finex          | Exchange(s) of interest|
| starttime       | 0b         | -12h         | Last available date | 2020.04.16D09:40:00.000000 | Query start time |
| endtime         | 0b         | -12h         | Last available date | 2020.04.16D12:00:00.000000 | Query end time |
| bucket          | 0b         | -18h         | 2*.crypto.deffreq | 00:02:00         | Bucket intervals |
  

###### Example usage:

Top of book data for ETHUSDT across zb and huobi exchanges: 

    q)topofbook[`sym`exchanges`starttime`endtime!(`ETHUSDT;`zb`huobi;2020.03.29D15:00:00.000000000;2020.03.29D15:05:00.000000000)]
    
    exchangeTime                  zbBid  zbAsk  zbBidSize zbAskSize huobiBid huobiAsk huobiBidSize huobiAskSize
    -----------------------------------------------------------------------------------------------------------
    2020.03.29D15:01:00.000000000 129.37 129.42 1.43      0.002     129.3    129.4    30.6389      294.2774
    2020.03.29D15:02:00.000000000 129.28 129.33 2.31      0.001     129.2    129.3    0.6546       714.6843
    2020.03.29D15:03:00.000000000 129.25 129.34 1.77      0.024     129.1    129.2    127.2271     74.5471
    2020.03.29D15:04:00.000000000 129.26 129.31 1.38      0.001     129.1    129.2    328.819      1
    2020.03.29D15:05:00.000000000 129.16 129.22 2.13      0.001     129.1    129.2    25.2141      1081.714


### Arbitrage Function  
Returns top of book with additional profit and arbitrage columns. Note that profit here is reflective 
of the exchanges with the greates difference between bid/ask. When sizes are also taken into account it
may be possible to find a more profitable opportunity.

|      Keys       | Mandatory  |    Types     |     Defaults      |     Example      |  Description      |
| :-------------  | :--------: | :----------  | :---------------  | :--------------  | :---------------  |
| sym             | 1b         | -11h         | N/A               | \`BTCUSDT        | Symbol of interest |
| exchanges       | 0b         | -11 11h      | All exchanges     | \`finex          | Exchange(s) of interest|
| starttime       | 0b         | -12h         | Last available date | 2020.04.16D09:40:00.000000 | Query start time |
| endtime         | 0b         | -12h         | Last available date | 2020.04.16D12:00:00.000000 | Query end time |
| bucket          | 0b         | -18h         | 2*.crypto.deffreq | 00:02:00         | Bucket intervals |


###### Example usage:  

Top of book with arbitrage indicator for ETHUSDT across zb and huobi exchanges:  
 
    q)arbitrage[`sym`exchanges`starttime`endtime!(`ETHUSDT;`zb`huobi;2020.03.29D15:00:00.000000000;2020.03.29D15:05:00.000000000)]
    
    exchangeTime                  zbBid  zbAsk  zbBidSize zbAskSize huobiBid huobiAsk huobiBidSize huobiAskSize profit arbitrage
    ----------------------------------------------------------------------------------------------------------------------------
    2020.03.29D15:01:00.000000000 129.37 129.42 1.43      0.002     129.3    129.4    30.6389      294.2774     0      0
    2020.03.29D15:02:00.000000000 129.28 129.33 2.31      0.001     129.2    129.3    0.6546       714.6843     0      0
    2020.03.29D15:03:00.000000000 129.25 129.34 1.77      0.024     129.1    129.2    127.2271     74.5471      0.0885 1
    2020.03.29D15:04:00.000000000 129.26 129.31 1.38      0.001     129.1    129.2    328.819      1            0.06   1
    2020.03.29D15:05:00.000000000 129.16 129.22 2.13      0.001     129.1    129.2    25.2141      1081.714     0      0

##### Additional Information:

It is important to note that these functions do not account for:

-    Exchange fees
-    Transaction costs
-    Request latency


