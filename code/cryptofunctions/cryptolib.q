// TorQ-Crypto functions
// Collaborators: Cormac Ross, James Rutledge, Catherine Higgins, Nicole Watterson, Michael Potter

// Have some global description, particularly talking about HDB/RDB dynamism and null parameters taking where clause away

/ 
                                **** ORDER BOOK FUNCTION ****
  This function returns a level 2 orderbook and takes a parameter dictionary as an argument.
  Sym is the only mandatory parameter that the user has to pass in, the others will revert to defaults.
  If a null parameter value is passed in, this will remove the pertinent where clause from the query.
  This function can be run on the RDB and/or HDB and will adjust queries accordingly.
  Window must be passed in as a second type (-18h).

  Example usage:
  orderbook[(enlist `sym)!enlist (`SYMBOL)]                                          ->  get latest `SYMBOL data from table
  orderbook[(`sym`timestamp`exchanges`window)!(`BTCUSDT;.proc.cp[];`finex`bhex;30)]  ->  more user input example
\

orderbook:{[dict]
  allkeys:`timestamp`sym`exchanges`window;
  typecheck[allkeys!12 11 11 18h;0100b;dict];
  if[not (1=count dict[`sym]) and not any null dict [`sym];'"Please enter one non-null sym."];

  // Set default dict and default date input depending on whether HDB or RDB is target (this allows user to omit keys)
  defaulttime:$[`rdb in .proc.proctype;
    exec last time from exchange;
    first exec time from select last time from exchange where date=last date];
  d:setdefaults[allkeys!(defaulttime;`;`;`second$2*.crypto.deffreq);dict];

  // Create extra key if on HDB and order dictionary by date
  if[`hdb~.proc.proctype;d[`date]:d[`timestamp];`date xcols d];

  // Choose where clause based on proc
  // If proc is HDB, add on extra where clause at the start, 
  // then join on default clause then pass in dictionary elements which are not null
  wherecl:($[`hdb ~ .proc.proctype;(enlist `date)!
    enlist (within;`date;(enlist;($;enlist`date;(-;d`timestamp;d`window));($;enlist`date;d`timestamp)));()!()],
    (`timestamp`sym`exchanges!(
      (within;`time;(enlist;(-;d`timestamp;d`window);d`timestamp));
      (=;`sym;enlist d`sym);
      (in;`exchange;enlist d`exchanges))
    )) (where not all each null d) except `window;

  // Define book builder projected function
  book:{[wherecl;columns] ungroup columns#0!?[exchange;wherecl; (enlist`exchange)!enlist`exchange; ()]}[wherecl;];

  // Create bid and ask books and join to create order book
  bid:`exchange_b`bidSize`bid xcols `exchange_b xcol `bid xdesc book[`exchange`bid`bidSize];
  ask:`ask`askSize`exchange_a xcols `exchange_a xcol `ask xasc book[`exchange`ask`askSize];
  orderbook:bid,'ask;
  $[(0=count orderbook) & .z.d>`date$d`timestamp;
    '":no data for the specified timestamp. Please try an alternative. For historical data run the function on the hdb only."; 
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
  allkeys:`date`sym`exchange`quote`byexchange;
  typecheck[allkeys!(14h;11h;11h;11h;1h);01000b;dict];
  
  // Set default null dict and default date input depending on whether HDB or RDB is target (this allows user to omit keys)
  defaultdate:$[`rdb in .proc.proctype; .proc.cd[]; last date];
  d:setdefaults[allkeys!(defaultdate;`;`;`ask`bid;0b);dict];
  
  // Filter dates based on proctype
  d[`date]:((),d[`date]) inter (),$[`rdb ~ .proc.proctype;.proc.cd[];date];
  
  // Create sym and exchange lists, bid and ask dicts for functional select
  biddict:`openBid`closeBid`bidHigh`bidLow!((first;`bid);(last;`bid);(max;`bid);(min;`bid));
  askdict:`openAsk`closeAsk`askHigh`askLow!((first;`ask);(last;`ask);(max;`ask);(min;`ask));

  // Conditionals to form the ohlc column dict, where clause and by clause
  coldict:$[any i:`bid`ask in d[`quote];(,/)(biddict;askdict) where i;(enlist`)!(enlist())];
  wherecl:$[`rdb ~ .proc.proctype;
    `date`sym`exchange!((in;`time.date;enlist d`date);(in;`sym; enlist d`sym);(in;`exchange; enlist d`exchange));
    `date`sym`exchange!((in;`date;enlist d`date);(in;`sym;enlist d`sym);(in;`exchange;enlist d`exchange))
    ] (where not all each null d) except `quote`byexchange;
  bycl:$[`rdb ~ .proc.proctype;(`date`sym!`time.date`sym);(`date`sym!`date`sym)], $[d[`byexchange];ex!ex:enlist `exchange;()!()];

  // Perform query - (select coldict by date:time.date,sym from t (where time.date in d`date, sym in syms, exchange in exchanges))
  ?[exchange_top; wherecl; bycl; coldict]
 };

/
                                  **** ARBITRATION FUNCTIONS ****
  The following two functions, topofbook and arbitrage, are all to do with arbitration.
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
  if[any 1 0<(count;sum)@\: null dict[`sym];'"Please enter one non-null sym."];

  // Set defaults and sanitise input
  defaulttimes:$[`rdb~.proc.proctype;"p"$(.proc.cd[];.proc.cp[]);0 -1 + "p"$0 1 + last date];
  d:setdefaults[allkeys!raze(defaulttimes;`;`;`second$2*.crypto.deffreq);dict];
  d:@[d;`starttime`endtime`bucket;first];
  d[`bucket]:`long$d`bucket;
  
  // Check that dates passed in are valid
  if[any (all .proc.cp[]<;>/)@\:d[`starttime`endtime];'"Invalid start and end times"];

  // If on HDB generate new where clause and join the rest on
   wherecl:($[`hdb ~ .proc.proctype;(enlist `date)!enlist (within;`date;enlist,"d"$d[`starttime`endtime]);()!()], `starttime`sym`exchanges!(
      (within;`time;enlist,d[`starttime`endtime]);
      (in;`sym;enlist d[`sym]);
      (in;`exchange;enlist d[`exchanges])
    ))where not all each null `endtime`bucket _d;

  // Perform query 
  t:?[exchange_top;wherecl;0b;cls!cls:`time`exchange`bid`ask`bidSize`askSize];

  // Get exchanges and use them to generate table names
  exchanges:exec distinct exchange from t;
  tablenames:{`$string[x],"Table"} each exchanges;

  // If no data is available, return an empty table 
  if[0=count t;:t:`time xkey (,'/){(raze(`time;`$string[x],/:("Bid";"Ask";"BidSize";"AskSize"))) xcol y}[;t] each d`exchanges];

  // Creates a list of tables with the best bid and ask for each exchange
  exchangebook:{[x;y;z] 
    (raze(`time;`$string[x],/:("Bid";"Ask";"BidSize";"AskSize"))) xcol 
    select bid:last bid,ask:last ask ,bidSize:last bidSize ,askSize:last askSize 
      by time:(`date$time)+z+z xbar time.second 
      from y where exchange=x
   }[;t;d`bucket] each exchanges;

  // If there is only one exchange, return the unedited arbtable
  if[99h~type exchangebook;:(,'/) value l1dict:tablenames!exchangebook];

  // If more than one exchange, join together all datasets, reorder the columns, fill in nulls and return
  arbtable:`time xasc (,'/) value l1dict:tablenames!exchangebook;
  arbtable:{![x;();0b;y]}[arbtable;ca!fills,' ca:asc 1 _cols arbtable]

 };


//ARBITRAGE FUNCTION

  // Adds a column saying if there is a chance of risk free profit and what that profit is
  arbitrage:{[d]
  // Generate arbitrage table, extract bid and ask columns and create two subtables (if empty list return nothing)
  if[0h=type arbtable:topofbook[d];:()];
  tabs:(getcols[arbtable;] each ("*Bid";"*Ask")) #\: arbtable;

  // Define function to compare bids and asks across exchanges and apply to arbtable
  makeops:{[bidtable;asktable;length] (value bidtable[length])>\:value (max value max bidtable)^asktable[length]};
  arbitrageops:.[makeops;tabs] each til count arbtable;

  // Create a new column which shows if arbitrage opportunity exists for each row
  table:update arbitrage:1b from arbtable where any flip {[opstable;length] any each opstable[length]}[arbitrageops;] each til count arbitrageops;
 
  // Add a column saying how much potential profit you can make by only looking at the best bid and ask
  // Can we replace this iterative approach with a broader update approach?

  arbitragerows:exec i from table where arbitrage=1b;
  updatetable:{[table;row]
    // Get dictionaries of exchanges and their bids and asks, then extract exchanges to buy and sell on and what amount
    dicts:(getcols[table;] each ("*Bid";"*Ask")) #\: table row;
    pricecols:{[f;d] d?f d}'[(max;min);dicts];
    sizecols:{`$(-3_ string x),y}'[pricecols;("BidSize";"AskSize")];

    // Get the size of sym to buy and sell and update the arbitrage table
    size:min raze {value enlist[z]#x y}[table;row;] each sizecols;
    table:update profit:first (size*max first dicts)-size* min last dicts from table where i=row
   };
  (ljf/) `time xkey' updatetable[table;] each arbitragerows
 };
/
                                    **** UTILITY FUNCTIONS ****
  The following three functions, getcols, typecheck and setdefaults, are utility functions used elsewhere in this script

  getcols[] gets columns from a table which match a particular pattern, ie. "*Bid"
  setdefaults[] produces a dictionary where missing values are filled in with defaults
  typecheck[] checks the types of dictionary values that are passed in by the user
\

getcols:{[table;word] col where (col:cols table) like word };

setdefaults:{[def;dict] def,(where not all each null dict)#dict };

typecheck:{[typedict;requiredkeylist;dict]
  // Checks the arguments are given in the correct form and the right keys are given
  if[not 99=type dict;'"error - arguement passed must be a dictionary"];
  if[not all keyresult:key[dict] in key typedict;
    '"The following dictionary keys are incorrect: ",(", " sv string key[dict] where 0=keyresult),
     ". The allowed keys are: ",", " sv string key typedict];
  
  // Determine required keys and throw an error if any are missing
  requiredkeys:(key typedict) where requiredkeylist;
  if[not all requiredkeys in key dict;'"error - the following keys must be included: ",", " sv  string requiredkeys];
  
  // Determine if arguments passed in are of the correct types
  typematch:typedict[key dict]=abs type each dict;
  if[not all typematch;
    '"error - dictionary parameter ",(", "sv string where not typematch)," must be of type: ",", "sv string {key'[x$\:()]}typedict where not typematch];
 };

