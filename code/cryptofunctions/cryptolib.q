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
  typecheck[`sym`timestamp`exchanges`window!11 12 11 18h;1000b;dict];								                // check required keys are present and all keys are of correct type
  d:`sym`timestamp`exchanges`window!(`;0Np;`;0Nv);										                              // default null dictionary. Allows user to omit keys
  d:d,dict;															                                                            // join user-passed dictionary to default dictionary
  validcheck[d;`sym;`exchange;`sym];												                                        // check a valid sym is passed
  $[`rdb in .proc.proctype;													                                                // if current process is rdb
    defaulttime:exec last time from exchange;											                                  // set default time to be last time from exchange
    defaulttime:first exec time from select last time from exchange where date=last date];					// if in hdb, set default time to be last time from yesterday

  // if any of timestamp, exchanges or window are not specified by user, update d to the default values. Pass preferred default values as dictionary to the assign function.
  d:assign[d;`timestamp`exchanges`window!(defaulttime;execcol[`exchange;`exchange];2*.crypto.deffreq)];
  validcheck[d;`exchanges;`exchange;`exchange];											                                // check valid exchanges have been passed

  // create book. If in the rdb process, exclude date clause from the select statement
  book:{[symbol;timestamp;exchanges;window;columns]
    $[`rdb in .proc.proctype;
      ungroup columns#0!select by exchange from exchange where time within(timestamp-`second$window;timestamp),sym=symbol,exchange in exchanges;
      ungroup columns#0!select by exchange from exchange where date=`date$timestamp,time within(timestamp-`second$window;timestamp),sym=symbol,exchange in exchanges]
   }[d`sym;d`timestamp;d`exchanges;d`window;];
  bid:`exchange_b`bidSize`bid xcols `exchange_b xcol `bid xdesc book[`exchange`bid`bidSize];				// create bid book
  ask:`ask`askSize`exchange_a xcols `exchange_a xcol `ask xasc book[`exchange`ask`askSize];					// create ask book
  orderbook:bid,'ask;														                                                    // join bid and ask to create orderbook
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

// creates an open, high,low close table
ohlc:{[dict]
  typecheck[`date`sym`exchange`quote!(14h;11h;11h;11h);0100b;dict];
  
  // Set default null dict and default date input depending on whether HDB or RDB is target
  nulldef:`date`sym`exchange`quote!(0Nd;`;`;`);
  defaultdate:$[`rdb in .proc.proctype; .z.d; last exec date from select distinct date from exchange];
  d:assign[nulldef,dict;`date`exchange`quote!(defaultdate;execcol[`exchange;`exchange];`bid)];

  // Check sym, exchanges and date are valid (validcheck and existencecheck are same function?!, any need to check ex and top? surely from same dataset?)
  validcheck[d;`sym;`exchange;`sym];
  validcheck[d;`sym;`exchange_top;`sym];
  validcheck[d;`exchange;`exchange;`exchange];
  
  // Check dates are valid and filter based on proctype
  if[not all .proc.cd[]>=d`date;'"Enter a valid date i.e on or before ",string .proc.cd[]];
  d[`date]:((),d[`date]) inter (),$[`rdb ~ .proc.proctype;.z.d;date];
  
  // Create sym list, bid and ask dicts for functional select
  syms:enlist d`sym;
  biddict:`openBid`closeBid`bidHigh`bidLow!((first;`bid);(last;`bid);(max;`bid);(min;`bid));
  askdict:`openAsk`closeAsk`askHigh`askLow!((first;`ask);(last;`ask);(max;`ask);(min;`ask));

  // Conditional to form the dict
  coldict:$[all `=d`quote; biddict,askdict;
            all `bid=d`quote; biddict;
            all `ask=d`quote; askdict;
            all d[`quote] in `ask`bid ; biddict,askdict;
            '"Error, please enter a valid arguement, either `ask, `bid or `."];

  // Get the right exchanges to query
  exchanges:$[all null d`exchange; enlist execcol[exchange_top;`exchange]; enlist d`exchange];
  
  // Perform query
  result:$[`rdb~.proc.proctype;
    // select coldict by date:time.date from t where time.date in d`date, sym in syms, exchange in exchanges
    ?[exchange_top; ((in;`time.date;enlist d`date);(in;`sym; syms);(in;`exchange; exchanges)); `date`sym!`time.date`sym; coldict];		
    //select colDict by date, sym from table where date in dates, sym in Syms, exchange in Exchanges
    ?[exchange_top; ((in;`date;enlist d`date);(in;`sym;syms);(in;`exchange;exchanges)); `date`sym!(($;enlist`date;`time);`sym); coldict]
    ];
  result
 };

//creates a table showing the top of the book for each excahnges at a given time
createarbtable:{[d]
  typecheck[`symbol`starttimestamp`endtimestamp`bucketsize`exchanges!11 12 12 18 11h;10000b;d];
  d2:`symbol`starttimestamp`endtimestamp`bucketsize`exchanges!(`;0Np;0Np;0Nv;`);						                                    // default dictionary
  d:d2,d;
  if[processresult:.proc.proctype=`hdb; hdbdate:last execcol[exchange_top;`date]];
  d:$[processresult;														                                                                                // sets defaults if nulls are entered depending on what process
    assign[d;(`starttimestamp`endtimestamp`bucketsize)!(`timestamp$hdbdate;-1+`timestamp$hdbdate+1;`second$2*.crypto.deffreq)];
    assign[d;(`starttimestamp`endtimestamp`bucketsize)!(`timestamp$.proc.cd[];.proc.cp[];`second$2*.crypto.deffreq)]];
  d:@[d;`symbol`starttimestamp`endtimestamp`bucketsize;first];									                                                // reassigns the dictionary keys to atoms
  if[all .proc.cp[]<d[`starttimestamp],d`endtimestamp; '"Enter a valid timestamp, one less than ",string .proc.cp[]];           // checks the timestamps entered can be queried
  if[not (`date$d`starttimestamp)=`date$d`endtimestamp; '"The date part startimestamp and endtimestamp must be the same"];      // ensures the query is over one day
  if[d[`starttimestamp]>d`endtimestamp; '"starttimestamp must be less than endtimestamp"];                                      // ensures the startTimestamp is smaller than the endTimestamp

  //gets the distinct list of exchanges in the time period
  d:$[processresult;														                                                                                // sets the default values for exchanges
  //string then cast back to a symbol to unenumerate the exchanges
    assign[d;enlist[`exchanges]!enlist `$string exec exchange from select distinct exchange from exchange_top where date=`date$d`endtimestamp, time within (d`starttimestamp;d`endtimestamp)];
    assign[d;enlist[`exchanges]!enlist exec exchange from select distinct exchange from exchange_top where time within (d`starttimestamp;d`endtimestamp)]];
  d[`bucketsize]:`long$d`bucketsize;												                                                                    // coverts the bucketSize to an integer
  existencecheck[`exchange_top;`sym;d`symbol];											                                                            // checks that the symbol passed exists in our table
  existencecheck[`exchange_top;`exchange;d`exchanges];										                                                      // checks that the exchanges passed exists in our table
  //select appriopiate cols
  t:$[processresult;														                                                                                // does the correct query depending on what process we are in
    select time,exchange,bid,ask,bidSize,askSize from exchange_top where date=`date$d`endtimestamp, time within (d`starttimestamp;d`endtimestamp),sym in d`symbol, exchange in d`exchanges;
    select time,exchange,bid,ask,bidSize,askSize from exchange_top where time within (d`starttimestamp;d`endtimestamp),sym in d`symbol, exchange in d`exchanges];
  if[not count t; '"There is no data available in the timestamp range"];
  exchanges:execcol[t;`exchange];												                                                                        // gets names of exchanges
  tablenames:{`$string[x],"Table"} each exchanges;										                                                          // table names for each exchange

  //creates a list of tables with the best bid and ask for each exchange
  exchangebook:{[x;y;z] (`time;`$string[x],"Bid";`$string[x],"Ask";`$string[x],"BidSize";`$string[x],"AskSize") 
                          xcol select bid:first bid,ask:first ask ,bidSize:first bidSize ,askSize:first askSize by time:z xbar time.second from y where exchange=x}[;t;d`bucketsize] each exchanges;
  levelonedict:tablenames!exchangebook;												                                                                   //creates a dictionary with the values being a L1 order book for each exchange
  arbtable:(,'/)value levelonedict;
  if[1=count levelonedict; :arbtable];												                                                                   // if only one exchange used output arbTable
  arbtable:0!`time xasc arbtable;												                                                                         // if more than one exchange used start to edit
  colnames: cols arbtable;													                                                                             // get column names
  arbtable:(`time,colnames where not null first each ss[;"Bid"] each string colnames) xcols arbtable;				                     // reorder the cols to have time, bids, asks
  arbtable:{![x;();0b;y]}[arbtable;(1 _ colnames)!fills,' 1_ colnames];								                                           // fill in null values
  arbtable															                                                                                         // output table
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


