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
Get latest \`SYMBOL data from table:   

``
q)orderbook[(enlist `sym)!enlist (`SYMBOL)]   
``  

// Example output
|exchange_b | bidSize | bid | ask | askSize | exchange_a |
| :-------: | :-------: |:-------:|:-------:|:-------:|:-------: |
| okex       | 2.076665   | 6951.4  | 6949.5  | 0.511969   | huobi |
| okex       | 0.001      | 6950.7  | 6949.9  | 0.001      | huobi |
| okex       | 0.0064022  | 6950.6  | 6950.42 | 7.082231   | bhex |
| okex       | 0.3        | 6950.5  | 6950.49 | 0.2        | bhex |
..  

Get \`SYMBOL data from finex and bhex for last 2 hours:  
``
orderbook[`sym`timestamp`exchanges`window!(`SYMBOL;.proc.cp[];`finex`bhex;02:00:00)]   
``   

// Example output
| exchange_b | bidSize | bid  | ask | askSize | exchange_a |
| :--------: | :-----: | :--: | :-: | :-----: | :--------: |
| bhex       | 0.064843999999999999   | 7295.9899999999998 | 7296.7799999999997 | 0.18113599999999999   | bhex |
| bhex       | 0.1767                 | 7295.8999999999996 | 7296.79            | 0.110959              | bhex |
| bhex       | 0.10000000000000001    | 7295.8800000000001 | 7297.04            | 0.96191800000000005   | bhex |
| bhex       | 0.037999999999999999   | 7295.8699999999999 | 7297.2200000000003 | 0.251                 | bhex |
| ..|


#### OHLC Function
Returns the OHLC data for bid and/or ask data and tales a dictionary parameter as an argument.  
Available keys include: date, sym, quote, byexchange.
The only parameter that must be passed in is sym, the others will revert to defaults.  

###### Example usage:
Get latest OHLC data for \`SYMBOL:  
``
q)ohlc[enlist[`sym]!enlist `SYMBOL]
``  
// Example output
|**date** |  **sym**  | openBid | closeBid | bidHigh | bidLow | openAsk | closeAsk | askHigh | askLow |
| :-: | :---: | :-----: | :------: | :-----: | :----: | :-----: | :------: | :-----: | :----: |
| **2020.04.03** | **BTCUSDT** | 6792.1800000000003 | 6956.3999999999996 | 7038.7399999999998 | 6724.1999999999998 | 6795.54 | 6956.46  | 7039.0100000000002 | 6725.8000000000002 |

Get only bid data by exchange for \`SYMBOL:  
``
q)ohlc[`date`sym`exchanges`quote`byexchange!(.z.d;`SYMBOL;`finex`okex;`bid;1b)]
``  

// Example output
| **date** |  **sym**  |  exchange | openBid | closeBid | bidHigh | bidLow |
| :------: | :-------: | :-------: | :-----: | :------: | :-----: | :----: |
| **2020.04.03** | **BTCUSDT** | finex   | 6783.7600000000002 | 6962.1599999999999 | 7033.3299999999999 | 6727.1800000000003|
| **2020.04.03** | **BTCUSDT** | okex    | 6784.5             | 6964               | 7026.6000000000004 | 6724.1999999999998|

#### Topofbook Function  
Creates a table showing top of the book for each exchange (Level 1) at a given time.  
Available keys include: sym, exchanges, starttime, endtime, bucket.
Sym is the only mandatory parameter that the use must pass in, the other will revert to defaults.  
If a null parameter value is passed in, this will remove the pertinent where clause from the query.  
This function can be run on the RDB and/or HDB and will adjust queries accordingly.  

###### Example usage:
Get level 1 data for \`SYMBOL from all exchanges  
``
q)topofbook[(enlist `sym)!enlist `BTCUSDT]
``  
// Example output
| exchangeTime | okexBid | okexAsk | okexBidSize | okexAskSize | huobiBid | huobiAsk | huobiBidSize | huobiAskSize | zbBid | .. |
| :----------: | :-----: | :-----: | :---------: | :---------: | :------: | :------: | :----------: | :----------: | :---: | :-: |
| 2020.04.03D12:24:00.000000000 | 7262 | 7262.1000000000004 | 0.032327000000000002 | 0.001 | 7258 | 7259.8000000000002 | 0.022180999999999999 | 0.45000000000000001   | 7260.479.. | .. |

Get level 1 data in the last 2 hours in buckets of 5 mins for \`SYMBOL:  
``
q)topofbook[`sym`exchanges`starttime`endtime`bucket!(`SYMBOL;`;.proc.cp[]-02:00:00;.proc.cp[];00:05:00)]
``  
// Example output
| exchangeTime | okexBid | okexAsk | okexBidSize | okexAskSize | zbBid | zbAsk | zbBidSize | .. |
| :--: | :-----: | :-----: | :---------: | :---------: | :---: | :---: | :-------: | :-: |
| 2020.04.03D12:20:00.000000000 | 6994 | 6994.1000000000004 | 0.090746789999999994 | 0.001 | 6991.9899999999998 | 6995.4700000000003 | 0.027.. | .. |
| 2020.04.03D12:25:00.000000000 | 7002.6000000000004 | 7002.6999999999998 | 0.51531985000000002 | 0.002 | 7000.6800000000003 | 7004.4799999999996 | 0.375.. | .. |
| 2020.04.03D12:30:00.000000000 | 6990.3999999999996 | 6990.5 | 2.5580082399999999 | 0.00048594000000000003 | 6988.3900000000003 | 6991.0200000000004 | 0.2384.. | .. |
| 2020.04.03D12:35:00.000000000 | 6984.3000000000002 | 6984.3999999999996 | 3.2902149299999999 | 0.001 | 6975.0299999999997 | 6977.6199999999999 | 0.2005.. | .. |
..  

#### Arbitrage Function  
Arbitrage is the simultaneous buying and selling of a financial insturment in different markets to 
take advantage of the difference in price. This function will look for opportunities of arbitrage 
and caluclate to potential profit to be made.  

The Arbitrage functtion calls the topofbook function and adds columns saying if there is a chance 
of risk free profit and what that profit is. Available keys include: sym, exchanges, starttime, 
endtime, bucket. Sym is the only required key, all other keys will revert to defaults. 

###### Example usage:  
Get arbitrage data for \`SYMBOL from exchanges: \`zb and \`okex:  
``
q)arbitrage[(enlist `sym)!enlist `BTCUSDT]         
``  
// Example output
| exchangeTime | okexBid | okexAsk | okexBidSize | okexAskSize | huobiBid | huobiAsk | huobiBidSize | .. |
| :----------: | :-----: | :-----: | :---------: | :---------: | :------: | :------: | :----------: | :-: |
| 2020.04.03D12:24:00.000000000 | 7262 | 7262.1000000000004 | 0.001 | 7258 | 7259.8000000000002 | 6783.1000000000004 | 0.02218099999999.. | ..| 
| 2020.04.03D12:25:00.000000000 | 7259.5 | 7259.6000000000004 | 0.01470905 | 0.001 | 7259.3000000000002 | 7259.8000000000002 | 0.03500000000000.. | ..|
| 2020.04.03D12:26:00.000000000 | 7243.8999999999996 | 7244 | 1.45955678 | 0.0044795099999999999 | 7237.1000000000004 | 7237.1999999999998 | 0.00220000000000.. | .. |
| 2020.04.03D12:27:00.000000000 | 7251.6999999999998 | 7251.8000000000002 | 0.044238479999999997 | 0.002 | 7250.3000000000002 | 7251.3999999999996 | 0.06075400000000.. | .. |
..

Get arbitrage data for the last 2 hours in buckets of 5 mins for \`SYMBOL:  
``
q)arbitrage[`sym`exchanges`starttime`endtime`bucket!(`SYMBOL;`;.proc.cp[]-01:00:00;.proc.cp[];00:05:00)]
``  
// Example output
| exchangeTime | zbBid | zbAsk | zbBidSize | zbAskSize | okexBid | okexAsk | okexB |.. |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
|2020.04.03D12:10:00.000000000 | 6974.7600000000002 | 6977.2700000000004 | 1 | 0.00059999999999999995 | 6976.3999999999996 | 6976.5 | 0.761.. | .. |
| 2020.04.03D12:15:00.000000000 | 6988.6400000000003 | 6992.0699999999997 | 0.039 | 0.00020000000000000001 | 6994.6999999999998 | 6994.8000000000002 | 0.299.. | .. |
| 2020.04.03D12:20:00.000000000 | 6991.9899999999998 | 6995.4700000000003 | 0.027 | 0.00059999999999999995 | 6994 | 6994.1000000000004 | 0.090.. | .. |
| 2020.04.03D12:25:00.000000000 | 7000.6800000000003 | 7004.4799999999996 | 0.375 | 0.00040000000000000002 | 7002.6000000000004 | 7002.6999999999998 | 0.515.. |.. |
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
``
h(`.gw.syncexec;"orderbook[`sym`exchanges!(`SYMBOL;`zb)]";`rdb)
``

Retreive yesterday's level 1 data for a single non-null sym from the huobi and finex exchanges:
``
h(`.gw.syncexec;"topofbook[`sym`exchanges`starttime`endtime!(`SYMBOL;`huobi`finex;.proc.cp[]-48:00:00;.proc.cp[]-24:00:00)]";`hdb)
``  
### Custom queries 
The above function are for users ease-of-use. Users may build their own queries for their requirements.

    q)h(`.gw.syncexec;"select min ask, max bid by (`date$exchangeTime)+60+60 xbar exchangeTime.second, exchange from exchange_top where exchange in `finex`zb";`rdb)
    exchangeTime                  exchange| ask                bid
    --------------------------------------| -------------------------------------
    2020.04.08D12:24:00.000000000 finex   | 168.00999999999999 7272.1400000000003
    2020.04.08D12:24:00.000000000 zb      | 168.08000000000001 7268.4700000000003
    2020.04.08D12:25:00.000000000 finex   | 167.91             7260.5
    2020.04.08D12:25:00.000000000 zb      | 168.08000000000001 7262.4700000000003
