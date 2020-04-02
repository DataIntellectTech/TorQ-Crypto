# TorQ-Crypto Functions

## Summary table of TorQ-Crypto Functions

|                 Function                 |               Description                |
| :--------------------------------------: | :--------------------------------------: |
|    **orderbook**[\`sym\`exchanges\`timestamp\`window!(symbol;symbol;timestamp;second)]    | Returns level 2 orderbook. |
|    **ohlc**[\`date\`sym\`exchanges\`quote\`byexchange!(date;symbol;symbol;symbol;boolean)] | Returns open, high, low and close data for bid and/or ask data. |
|    **topofbook**[\`sym\`exchanges\`starttime\`endtime\`bucket!(symbol;symbol;timestamp;timestamp;time)] | Returns the level 1 orderbook. |
|    **arbitrage**[\`sym\`exchanges\`starttime\`endtime\`bucket!(symbol;symbol;timestamp;timestamp;time)] | Returns topofbook table with how much profit can be made with arbitrage opportunities. |

Here we discuss the use and give examples of pre-made functions available with the TorQ-Crypto package.

#### Orderbook Function
Returns level 2 orderbook and takes a dictionary parameter as an argument.   
Available keys include: sym, exchanges, timestamp and window.   
Sym is the only mandatory key that user must pass in, others may revert to defaults.   
If a null parameter is passed in the dictionary argument, this will remove the relevant key from the where clause of the query.
This function may be run on the RDB and/or HDB and will adjust defaults for queries accordingly.   

###### Example usage:
Get latest \`SYMBOL data from table:   
``
orderbook[(enlist `sym)!enlist (`SYMBOL)]   
``  

Get \`SYMBOL data from finex and bhex for last 30 secs:   
``
orderbook[(`sym`timestamp`exchanges`window)!(`SYMBOL;.proc.cp[];`finex`bhex;30)]   
``  

#### OHLC Function
Returns the OHLC data for bid and/or ask data and tales a dictionary parameter as an argument.  
The only parameter that must be passed in is sym, the others will revert to defaults.  

###### Example usage:
Get latest OHLC data for \`SYMBOL:  
``
ohlc[enlist[`sym]!enlist `SYMBOL]
``  

Get only bid data by exchange for \`SYMBOL:  
``
ohlc[`date`sym`exchanges`quote`byexchange!(.z.d;`SYMBOL;`finex`okex;`bid;1b)]
`` 

#### Topofbook Function  
Creates a table showing top of the book for each exchange (Level 1) at a given time.  
Sym is the only mandatory parameter that the use must pass in, the other will revert to defaults.  
If a null parameter value is passed in, this will remove the pertinent where clause from the query.  
This function can be run on the RDB and/or HDB and will adjust queries accordingly.  

###### Example usage:
Get level 1 data for \`SYMBOL from exchanges: \`finex and \`okex:  
``
topofbook[`sym`exchanges!(`SYMBOL;`finex`okex)]
``  

Get level 1 data in the last hour in buckets of 5 mins for \`SYMBOL:  
``
topofbook[`sym`exchanges`starttime`endtime`bucket!(`SYMBOL;`;.proc.cp[]-01:00:00;.proc.cp[];00:05:00)
``  

#### Arbitrage Function  
Arbitrage calls the topofbook function and adds columns saying if there is a chance of risk free profit and what that profit is.  

###### Example usage:  
Get arbitrage data for \`SYMBOL from exchanges: \`zb and \`okex:  
``
arbitrage[`sym`exchanges!(`SYMBOL;`zb`okex)]
``  

Get arbitrage data for the last hour in buckets of 5 mins for \`SYMBOL:  
``
arbitrage[`sym`exchanges`starttime`endtime`bucket!(`SYMBOL;`;.proc.cp[]-01:00:00;.proc.cp[];00:05:00)
``  

### Using Functions via Gateway
