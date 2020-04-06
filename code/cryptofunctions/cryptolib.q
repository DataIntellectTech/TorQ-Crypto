// TorQ-Crypto functions
// Collaborators: Cormac Ross, James Rutledge, Catherine Higgins, Nicole Watterson, Michael Potter

// Function for logging and signalling errors
errfunc:{.lg.e[x;"Crypto User Error:",y];'y};

/ 
                                **** ORDER BOOK FUNCTION ****
  This function returns a level 2 orderbook and takes a parameter dictionary as an argument.
  Sym is the only mandatory parameter that the user has to pass in, the others will revert to defaults.
  If a null parameter value is passed in, this will remove the pertinent where clause from the query.
  This function can be run on the RDB and/or HDB and will adjust queries accordingly.
  Window must be passed in as a second type (-18h).

  Example usage:
  orderbook[(enlist `sym)!enlist (`SYMBOL)]                                                ->  get latest SYMBOL data from table
  orderbook[(`sym`timestamp`exchanges`window)!(`BTCUSDT;.proc.cp[];`finex`bhex;00:00:30)]  ->  get `BTCUSDT data from finex and bhex exchnages for last 30 seconds 
\

orderbook:{[dict]
  allkeys:`timestamp`sym`exchanges`window;
  typecheck[allkeys!12 11 11 18h;0100b;dict];
  if[not(1=count dict`sym)and not any null dict`sym;errfunc[`orderbook;"Please enter one non-null sym."]];

  // Set default dict and default date input depending on whether HDB or RDB is target (this allows user to omit keys)
  defaulttime:$[`rdb in .proc.proctype;
    exec last time from exchange;
    first exec time from select last time from exchange where date=last date];
  d:setdefaults[allkeys!(defaulttime;`;`;`second$2*.crypto.deffreq);dict];

  // Create extra key if on HDB and order dictionary by date
  if[`hdb~.proc.proctype;d:`date xcols update date:timestamp from d];

  // Edit where clause based on proctype
  // If proctype is HDB, add on date to where clause at the start,
  // then join on default clause, then pass in dictionary elements which are not null
  wherecl:()!();
  window:enlist d[`timestamp] -d[`window],0;
  if[`hdb~.proc.proctype;wherecl[`date]:enlist(within;`date;`date$window)];
  wherecl,:`timestamp`sym`exchanges!(
    (within;`time;window);
    (=;`sym;enlist d`sym);
    (in;`exchange;enlist d`exchanges));
  wherecl@:(where not all each null d) except `window;
  // Define book builder projected function
  book:{[wherecl;columns]ungroup columns#0!?[exchange;wherecl;{x!x}enlist`exchange;()]}wherecl;

  // Create bid and ask books and join to create order book
  bid:`exchange_b`bidSize`bid xcols `exchange_b xcol `bid xdesc book[`exchange`bid`bidSize];
  ask:`ask`askSize`exchange_a xcols `exchange_a xcol `ask xasc book[`exchange`ask`askSize];
  orderbook:bid,'ask;
  $[(0=count orderbook) & .z.d>`date$d`timestamp;
    errfunc[`orderbook;"No data for the specified timestamp. Please try an alternative. For historical data run the function on the hdb only."];
    orderbook]
 };

/
                          **** OPEN HIGH LOW CLOSE (OHLC) FUNCTION ****
  This function returns OHLC data for bid and/or ask data and takes a paramter dictionary as an argument.
  The only parameter that must be passed in is sym, the others will revert to defaults.

  Example usage:
  ohlc[enlist[`sym]!enlist `SYMBOL]                                             ->  get latest OHLC data for SYMBOL
  ohlc[`date`sym`exchange`quote`byexchange!(.z.d;`SYMBOL;`finex`okex;`bid;1b)]  ->  get only bid data by exchange for SYMBOL
\

ohlc:{[dict]
  allkeys:`date`sym`exchanges`quote`byexchange;
  typecheck[allkeys!14 11 11 11 1h;01000b;dict];
  
  // Set default null dict and default date input depending on whether HDB or RDB is target (this allows user to omit keys)
  defaultdate:$[`rdb in .proc.proctype; .proc.cd[]; last date];
  d:setdefaults[allkeys!(defaultdate;`;`;`ask`bid;0b);dict];
  
  // Filter dates based on proctype
  d[`date]:((),d`date) inter (),$[`rdb ~ .proc.proctype;.proc.cd[];date];
  
  // Create sym and exchange lists, bid and ask dicts for functional select
  biddict:`openBid`closeBid`bidHigh`bidLow!((first;`bid);(last;`bid);(max;`bid);(min;`bid));
  askdict:`openAsk`closeAsk`askHigh`askLow!((first;`ask);(last;`ask);(max;`ask);(min;`ask));

  // Save time.date/date colname as variable based on proctype
  c:$[`rdb~.proc.proctype;`time.date;`date];

  // Conditionals to form the ohlc column dict, where clause and by clause
  coldict:$[any i:`bid`ask in d`quote;(,/)(biddict;askdict) where i;(enlist`)!(enlist())];
  wherecl:`date`sym`exchanges!
    ((in;c;enlist d`date);(in;`sym;enlist d`sym);(in;`exchange;enlist d`exchanges));
  wherecl@:where[not all each null d]except `quote`byexchange;

  bycl:(`date`sym!c,`sym),$[d`byexchange;{x!x}enlist`exchange;()!()];

  // Perform query - (select coldict by date:time.date,sym from t (where time.date in d`date, sym in syms, exchange in exchanges))
  ?[exchange_top; wherecl; bycl; coldict]
 };

/
                                  **** ARBITRATION FUNCTIONS ****
  The following two functions, topofbook and arbitrage, are to do with arbitration.
  The arbitrage function will call the topofbook function.
  Sym is the only mandatory parameter that the user has to pass in, the others will revert to defaults.
  If a null parameter value is passed in, this will remove the pertinent where clause from the query.
  This function can be run on the RDB and/or HDB and will adjust queries accordingly.

  topofbook[dict arg] generates a table showing the top of the book for each exchange
  arbitrage[dict arg] then gets this table and adds a column that shows if there is an opportunity to make profit and then adds a column showing how much potential profit can be made, just looking at the bid and ask
\

//TOPOFBOOK FUNCTION

// Creates a table showing the top of the book for each exchanges at a given time
topofbook:{[dict]
  allkeys:`starttime`endtime`sym`exchanges`bucket;
  typecheck[allkeys!12 12 11 11 18h;00100b;dict];
  if[any 1 0<(count;sum)@\: null dict[`sym];errfunc[`topofbook;"Please enter one non-null sym."]];

  // Set defaults and sanitise input
  defaulttimes:$[`rdb~.proc.proctype;"p"$(.proc.cd[];.proc.cp[]);0 -1 + "p"$0 1 + last date];
  d:setdefaults[allkeys!raze(defaulttimes;`;`;`second$2*.crypto.deffreq);dict];
  d:@[d;`starttime`endtime`bucket;first];
  d[`bucket]:`long$d`bucket;

  // Create extra date key if proctype=HDB and order dictionary by date
  if[`hdb~.proc.proctype;d:`date xcols update date:distinct "d"$d`starttime`endtime from d];

  // Check that dates passed in are valid
  if[any (all .proc.cp[]<;>/)@\:d`starttime`endtime;errfunc[`topofbook;"Invalid start and end times."]];

  // If proctype=HDB, add date to beginning of where clause and join remaining dict args to where clause
  wherecl:$[`hdb~.proc.proctype;(enlist `date)!enlist(within;`date;enlist,"d"$d`starttime`endtime);()!()];
  wherecl[`starttime]:(within;`time;enlist,d`starttime`endtime);
  wherecl[`sym]:(in;`sym;enlist d`sym);
  wherecl[`exchanges]:(in;`exchange;enlist d`exchanges);
  wherecl@:where not all each null `endtime`bucket _d;

  // Perform query - (select time, exchange, bid, ask, bisSize, askSize from exchange_top where (wherecl))
  t:?[exchange_top;wherecl;0b;cls!cls:`time`exchange`bid`ask`bidSize`askSize];

  // Get exchanges and use them to generate table names
  exchanges:exec distinct exchange from t;

  // If no data is available, return an empty table 
  if[0=count t;r:{(raze(`time;`$string[x],/:("Bid";"Ask";"BidSize";"AskSize"))) xcol y}[;t] each d`exchanges;:$[98h~type r;r;(,'/)r]];

  // Creates a list of tables with the best bid and ask for each exchange
  exchangebook:{[x;y;z] 
    (`time,`$string[x],/:("Bid";"Ask";"BidSize";"AskSize"))xcol 
    select bid:last bid,ask:last ask ,bidSize:last bidSize ,askSize:last askSize 
      by time:(`date$time)+z+z xbar time.second 
      from y where exchange=x
   }[;t;d`bucket] each exchanges;

  // If more than one exchange, join together all datasets, reorder the columns and return result
  :0!`time xasc (,'/) exchangebook;
 };

//ARBITRAGE FUNCTION

  // Adds a column saying if there is a chance of risk free profit and what that profit is
arbitrage:{[d]
  // Generate arbitrage table
  arbtable:topofbook[d];

  // If no data is available or only one non-null exchange is passed, update arbtable with profit and arbitrage as 0
  if[(0=count arbtable) or (5=count cols arbtable);:update profit:0,arbitrage:0 from arbtable];

  // Aggregate profit-column function - calculates profit to be made
  calprofit:{[b;bs;a;as]
    enlist({[b;bs;a;as]
      // Find best bid
      b:max@'l:(,'/)b;
      // Find best BidSize
      bs:@'[flip bs;where'[b=l]];
      // Find best ask
      a:min@'l:(,'/)a;
      // Find best AskSize
      as:@'[flip as;where'[a=l]];
      // Calculates profit
      p:min'[(bs,'as)]*b-a;
      ?[0>p;0;p]
     };
    // Enlists args to aggregate clause
    enlist,b;enlist,bs;enlist,a;enlist,as)
   };
 
  // Input columns for aggregate profit-col function
  cc:calprofit . getcols[arbtable;] each ("*Bid";"*BidSize";"*Ask";"*AskSize");

  // Perform query - (update arbitrage:profit>0 from (update profit:cc from arbtable))
  :update arbitrage:profit>0 from ![arbtable;();0b;enlist[`profit]!cc]
 };
/
                                    **** UTILITY FUNCTIONS ****
  The following three functions, getcols, typecheck and setdefaults, are utility functions used elsewhere in this script

  getcols[] gets columns from a table which match a particular pattern, ie. "*Bid"
  setdefaults[] produces a dictionary where missing values are filled in with defaults
  typecheck[] checks the types of dictionary values that are passed in by the user
\

getcols:{[table;word]col where(col:cols table)like word};

setdefaults:{[def;dict]def,(where not all each null dict)#dict};

typecheck:{[typedict;requiredkeylist;dict]
  // Checks the arguments are given in the correct form and the right keys are given
  if[not 99=type dict;errfunc[`typecheck;"The argument passed must be a dictionary."]];
  if[not all keyresult:key[dict] in key typedict;
    errfunc[`typecheck;"The following dictionary keys are incorrect: ",(", " sv string key[dict] where 0=keyresult),". The allowed keys are: ",", " sv string key typedict]];

  // Determine required keys and throw an error if any are missing
  requiredkeys:(key typedict) where requiredkeylist;
  if[not all requiredkeys in key dict;errfunc[`requiredkeys;"The following key(s) must be included: ",", " sv  string requiredkeys]];
 
  // Determine if arguments passed in are of the correct types
  typematch:typedict[key dict]=abs type each dict;
  if[not all typematch;
    errfunc[`typematch;"The dictionary parameter(s) ",(", "sv string where not typematch)," must be of type(s): ",", "sv string {key'[x$\:()]}typedict where not typematch]]
 };

