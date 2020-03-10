// function which returns level 2 orderbook. Takes a dictionary as parameter
// for the latest data from all exchanges for a sym, run orderbook[(enlist `sym)!enlist (`SYMBOL)] on the rdb
// timestamp,exchanges and look-back window can all be configured by the user. eg. orderbook[(`sym`timestamp`exchanges`window)!(`BTCUSDT;.proc.cp[];`finex`bhex;30)]
// if these parameters are not specified, timestamp defaults to latest timestamp present in exchange table, exchanges defaults to all available, window defaults to twice the query frequency
// if timestamp < today's date, run the function on the hdb only
// window must be passed in as type -18h (second)
// examples through handle to gateway:
// h(`.gw.syncexec;"orderbook[(enlist `sym)!enlist (`BTCUSDT)]";`rdb)
// h(`.gw.syncexec;"orderbook[`sym`timestamp!(`BTCUSDT;2020.02.09D11:30:00)]";`hdb)
// h(`.gw.syncexec;"orderbook[`sym`exchanges!(`ETHUSDT;`finex`huobi)]";`rdb)
// h(`.gw.syncexec;"orderbook[`sym`timestamp`exchanges`window!(`BTCUSDT;.z.p;`bhex;00:01:30)]";`rdb)

orderbook:{[dict]
  allkeys:`sym`timestamp`exchanges`window;
  typecheck[allkeys!11 12 11 18h;1000b;dict];
  if[not (1=count dict[`sym]) and not any null dict [`sym];'"Please enter one non-null sym."];

  // Set default dict and default date input depending on whether HDB or RDB is target (this allows user to omit keys)
  defaulttime:$[`rdb in .proc.proctype;exec last time from exchange;first exec time from select last time from exchange where date=last date];
  d:setdefaults[allkeys!(`;defaulttime;`;"v"$2*.crypto.deffreq);dict];

  // Create extra key if on HDB
  if[`hdb~.proc.proctype;d[`date]:d`timestamp];

  // Choose where clause based on proc
  // If proc is HDB, add on extra where clause at the start, 
  // then join on default clause then pass in dictionary elements which are not null
  wherecl:($[`hdb ~ .proc.proctype;(enlist `date)!
    enlist (within;`date;(enlist;($;enlist`date;(-;d`timestamp;d`window));($;enlist`date;d`timestamp)));()!()],
    (`timestamp`sym`exchanges!(
      (within;`time;(enlist;(-;d`timestamp;d`window);d`timestamp));
      (=;`sym;enlist d`sym);
      (in;`exchange;enlist d`exchanges))
    )) (where not any each null d) except `window;

  // Define book builder projected function
  book:{[wherecl;columns] ungroup columns#0!?[exchange;wherecl; (enlist`exchange)!enlist`exchange; ()]}[wherecl;];

  // Create bid and ask books and join to create order book
  bid:`exchange_b`bidSize`bid xcols `exchange_b xcol `bid xdesc book[`exchange`bid`bidSize];
  ask:`ask`askSize`exchange_a xcols `exchange_a xcol `ask xasc book[`exchange`ask`askSize];
  orderbook:bid,'ask;
  $[(0=count orderbook) & .z.d>`date$d`timestamp;'":no data for the specified timestamp. Please try an alternative. For historical data run the function on the hdb only."; orderbook]
 }

// function to exec a column. Eg exec sym from select distinct sym from exchange
execcol:{[table;column] 
  ?[(?[table;();1b;(enlist column)!enlist column]);();();column]
 }

// function for checking types of dictionary values
typecheck:{[typedict;requiredkeylist;dict]
  if[not 99=type dict;'"error - arguement passed must be a dictionary"];							               // check type of argument passed to original function
  if[not all keyresult:key[dict] in key typedict;										                                 //checks the keys entered have been spelt correctly
    '"The following dictionary keys are incorrect: ",(", " sv string key[dict] where 0=keyresult),". The allowed keys are: ",", " sv string key typedict];
  requiredkeys:(key typedict) where requiredkeylist;										                             // create list of required keys, given in requiredkeylist

  //error if any required keys are missing
  if[not all requiredkeys in key dict;'"error - the following keys must be included: ",", " sv  string requiredkeys];
  typematch:typedict[key dict]=abs type each dict;										                               // create dictionary showing where types match

  //error if any dict types do not match
  if[not all typematch;'"error - dictionary parameter ",(", "sv string where not typematch)," must be of type: ",", "sv string {key'[x$\:()]}typedict where not typematch];
 }

// function to check if valid values are passed and output available options if not
validcheck:{[dict;dictkey;table;column]
  if[not all dict[dictkey] in execcol[table;column];'"error - not a valid ",(string dictkey)," value. The following are available: ",", " sv string execcol[table;column]]
 }

// function to assign default values to dictionary where null values occur
assign:{[d;nulldict]														                                                      // pass in a dictionary with matching keys to d, with the preferred default values
  if[any raze null d; d:@[d;where any each null d;:;nulldict[where any each null d]]];						    // assign new values to d where null with the values of nulldict
  :d
 }

//function to check if something exists in a table
existencecheck:{[tablename;columnname;dictvalue]
  dictvalue:(),dictvalue;
  if[not all result:dictvalue in execcol[tablename;columnname];										
    '"The following ",sv[", ";string dictvalue where 0=result]," does not exist in ",string tablename];
 }; 

// Quick function for setting default dictionary values
setdefaults:{[def;dict] def,(where not all each null dict)#dict };

// Creates an open, high,low close table
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
    ] (where not any each null d) except `quote`byexchange;
  bycl:$[`rdb ~ .proc.proctype;(`date`sym!`time.date`sym);(`date`sym!`date`sym)], $[d[`byexchange];ex!ex:enlist `exchange;()!()];

  // Perform query - (select coldict by date:time.date,sym from t (where time.date in d`date, sym in syms, exchange in exchanges))
  ?[exchange_top; wherecl; bycl; coldict]
 };

// Creates a table showing the top of the book for each exchanges at a given time
createarbtable:{[dict]
  allkeys:`starttimestamp`endtimestamp`sym`exchanges`bucketsize;
  typecheck[allkeys!12 12 11 11 18h;00100b;dict];

  // Set defaults and sanitise input
  defaulttimes:$[`rdb~.proc.proctype;"p"$(.proc.cd[];.proc.cp[]);0 -1 + "p"$0 1 + last date];
  d:setdefaults[allkeys!raze(defaulttimes;`;`;`second$2*.crypto.deffreq);dict];
  d:@[d;`sym`starttimestamp`endtimestamp`bucketsize;first];
  d[`bucketsize]:`long$d`bucketsize;
  
  // Check that dates passed in are valid
  if[(all .proc.cp[] < stet) or (not ~/["d"$stet]) or (>/[stet:d[`starttimestamp`endtimestamp]]);'"Invalid start and end times"];

  // Create extra key if on HDB
  if[`hdb~.proc.proctype;d[`date]:`date$d[`endtimestamp];`date xcols d];

  // If on HDB generate new where clause and join the rest on
  wherecl:($[`hdb ~ .proc.proctype;(enlist`date)!enlist (=;`date;d[`date]);()!()],
    `starttimestamp`sym`exchanges!(
      (within;`time;(enlist;(d[`starttimestamp]);(d[`endtimestamp])));
      (in;`sym;enlist d[`sym]);
      (in;`exchange;enlist d[`exchanges])
    )) (where not any each null d) except `endtimestamp`bucketsize;

  // Perform query, then get exchanges and use them to generate table names
  t:?[exchange_top;wherecl;0b;cls!cls:`time`exchange`bid`ask`bidSize`askSize];  
  exchanges:exec exchange from (select distinct exchange from t);
  tablenames:{`$string[x],"Table"} each exchanges;

  // Creates a list of tables with the best bid and ask for each exchange
  exchangebook:{[x;y;z] (`time;`$string[x],"Bid";`$string[x],"Ask";`$string[x],"BidSize";`$string[x],"AskSize") xcol 
    select bid:first bid,ask:first ask ,bidSize:first bidSize ,askSize:first askSize by time:z xbar time.second 
      from y where exchange=x}[;t;d`bucketsize] each exchanges;

  // If there is only one exchange, return the unedited arbtable
  if[1=count l1dict:tablenames!exchangebook;:(,'/) value l1dict];

  // If more than one exchange, join together all datasets, reorder the columns, fill in nulls and return
  arbtable:0!`time xasc (,'/) value l1dict;
  colnames: cols arbtable;
  arbtable:(`time,colnames where not null first each ss[;"Bid"] each string colnames) xcols arbtable;
  arbtable:{![x;();0b;y]}[arbtable;(1 _ colnames)!fills,' 1_ colnames];
  arbtable
 };

//Used for getting column names that match a given pattern eg. getcols[arbtable;"*Bid"] will get the names of the columns which have Bid in them from arbtable
getcols:{[table;word]
  col where (col:cols table) like word
 };

//adds a column saying if there is a chance of risk free profit
arbitrage:{[d]
  arbtable:createarbtable[d];													    // create arbitrage table
  bidcols:getcols[arbtable;"*Bid"];												// create list of bid column names
  askcols:getcols[arbtable;"*Ask"];												// create list of ask column names
  bidtab:bidcols#arbtable;													      // create table of bid columns only
  asktab:askcols#arbtable;													      // create table of ask columns only

  //create matrix of arbitrage opportunities
  arbitrageops:{[bidtable;asktable;length](value bidtable[length])>\:value (max value max bidtable)^asktable[length]}[bidtab;asktab]'[til count arbtable];
  //create a new column which shows if arbitrage opportunity exists for each row
  update arbitrage:1b from arbtable where any flip {[opstable;length] any each opstable[length]}[arbitrageops]'[til count arbitrageops]
 };

//adds a column saying how much potenital profit you can make by only looking at the best bid and ask
profit:{[d]
  table:arbitrage[d];
  arbitragerows:exec i from table where arbitrage=1b;
  updatetable:{[table;row]
    bidcols:getcols[table;"*Bid"];											 // gets the bid cols
    askcols:getcols[table;"*Ask"];											 // gets the ask cols
    biddict:bidcols#table row;													 // dict of exchanges and their bids
    askdict:askcols#table row;													 // dict of exchanges and their asks
    sellpricecol:biddict?max biddict;										 // exchange we will sell on
    buypricecol:askdict?min askdict;										 // exchange we will buy on
    bidsizecol:`$(-3_string sellpricecol),"BidSize";		 // bid size col
    asksizecol:`$(-3_string buypricecol),"AskSize";			 // ask size col
    sellsize:value enlist[bidsizecol]#table row;
    buysize:value enlist[asksizecol]#table row;
    size:min buysize,sellsize;													 // size of sym we will buy and sell
    table:update profit:first (size*max biddict)-size* min askdict from table where i=row};
  (ljf/) `time xkey' updatetable[table;] each arbitragerows
 };


