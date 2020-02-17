// function which returns level 2 orderbook. Takes a dictionary as parameter
// for the latest data from all exchanges for a sym, run orderbook[(enlist `sym)!enlist (`SYMBOL)] on the rdb
// timestamp,exchanges and look-back window can all be configured by the user. eg. orderbook[(`sym`timestamp`exchanges`window)!(`BTCUSDT;.z.p;`finex`bhex;30)]
// if these parameters are not specified, timestamp defaults to latest timestamp present in exchange table, exchanges defaults to all available, window defaults to twice the query frequency
// if timestamp < today's date, run the function on the hdb only
// window must be passed in as type -18h (second)
// examples through handle to gateway:
// h(`.gw.syncexec;"orderbook[(enlist `sym)!enlist (`BTCUSDT)]";`rdb)
// h(`.gw.syncexec;"orderbook[(`sym`timestamp)!(`BTCUSDT;2020.02.09D11:30:00)]";`hdb)
// h(`.gw.syncexec;"orderbook[(`sym`exchanges)!(`BTCUSDT;`finex`huobi)]";`rdb)
// h(`.gw.syncexec;"orderbook[(`sym`timestamp`exchanges`window)!(`BTCUSDT;.z.p;`bhex;00:01:30)]";`rdb)

orderbook:{[dict]
  typecheck[(`sym`timestamp`exchanges`window)!(11h;12h;11h;18h);1000b;dict;99h];                             // check required keys are present and all keys are of correct type
  d:`sym`timestamp`exchanges`window!(`;0Np;`;0Nv);                                                           // default null dictionary. Allows user to omit keys
  d:d,dict;                                                                                                  // join user-passed dictionary to default dictionary
  validcheck[d;`sym;`exchange;`sym];                                                                         // check a valid sym is passed
  // if any of timestamp, exchanges or window are not specified by user, update d to the default values. Pass preferred default values as dictionary to the assign function.
  d:assign[d;(`timestamp`exchanges`window)!(first exec time from select last time from exchange;execcol[`exchange;`exchange];2*.crypto.deffreq)];
  validcheck[d;`exchanges;`exchange;`exchange];                                                              // check valid exchanges have been passed
  // create book: select columns by exchange from exchange where time within(timestamp-`second$window;timestamp),sym=sym,exchange in exchanges
  book:{[sym;timestamp;exchanges;window;columns];
    ungroup ungroup ?[`exchange;((within;`time;(enlist;(-;`timestamp;($;enlist`second;window));`timestamp));(=;`sym;enlist sym);(in;`exchange;enlist exchanges));(enlist `exchange)!enlist `exchange;columns!columns]
    }[d`sym;d`timestamp;d`exchanges;d`window;];
  bid:`exchange_b`bidSize`bid xcols `exchange_b xcol `bid xdesc book[`bid`bidSize];                          // create bid book
  ask:`ask`askSize`exchange_a xcols `exchange_a xcol `ask xasc book[`ask`askSize];                           // create ask book
  orderbook:bid,'ask;                                                                                        // join bid and ask to create orderbook
  $[(0=count orderbook) & .z.d>`date$d`timestamp;'":no data for the specified timestamp. Please try an alternative. For historical data run the function on the hdb only."; orderbook]
 }

// function to exec a column. Eg exec sym from select distinct sym from exchange
execcol:{[table;column] 
  ?[(?[table;();1b;(enlist column)!enlist column]);();();column]
 }

// function for checking types of dictionary values
typecheck:{[typedict;booleanlist;dict;dicttype]
  if[not dicttype=type dict;'"error - arguement passed must be of type ",.Q.s1 dicttype];                    // check type of argument passed to original function
  requiredkeys:(key typedict) where booleanlist;                                                             // create list of required keys, given in boolean list
  //error if any required keys are missing
  if[not all requiredkeys in key dict;'"error - the following keys must be included: ",", " sv  string requiredkeys];
  typematch:typedict[key dict]=abs type each dict;                                                           // create dictionary showing where types match
  //error if any dict types do not match
  if[not all typematch;'"error - dictionary parameter ",(", "sv string where not typematch)," must be of type: ",", "sv string {key'[x$\:()]}typedict where not typematch];
 }

// function to check if valid values are passed and output available options if not
validcheck:{[dict;dictkey;table;column]
  if[not all dict[dictkey] in execcol[table;column];'"error - not a valid ",(string dictkey)," value. The following are available: ",", " sv string execcol[table;column]]
 }

// function to assign default values to dictionary where null values occur
assign:{[d;nulldict]                                                                                         // pass in a dictionary with matching keys to d, with the preferred default values
  // assign new values to d where null with the values of nulldict
  if[any (raze/) null d; d:@[d;where 1=sum each any each null d;:;nulldict[where 1=sum each any each null d]]];
  :d
 }



//creates an open, high,low close table

ohlc:{[d]
  typecheck[`date`sym`exchange`quote!(14h;11h;11h;11h);1111b;d;99h];
  if[not all .z.d>=d`date;'"Enter a valid date i.e on or before ",string .z.d];                                                                 			//checks the date is valid
  //checks that the symbol passed exists in our table
  if[not d[`sym] in execcol[exchange_top;`sym]; '"This sym is not in the exchange_top table, please enter a valid one"];
  if[not d[`date] in exec time from select distinct `date$time from exchange_top;
    '"This date does not exist in exchange_top, please check you have entered a valid date and you are using the correct process."];
  syms:enlist d`sym;
  biddict:`openBid`closeBid`bidHigh`bidLow!((first;`bid);(last;`bid);(max;`bid);(min;`bid));                                  						//bid dict for functional select
  askdict:`openAsk`closeAsk`askHigh`askLow!((first;`ask);(last;`ask);(max;`ask);(min;`ask));                                   						//ask dict for functional select
  $[all `=d`quote; coldict:biddict,askdict;                                                                                 						//makes the dict needed for the functional select
    all `bid=d`quote; coldict:biddict;
    all `ask=d`quote; coldict:askdict;
    all d[`quote] in `ask`bid ; coldict:biddict,askdict;
    '"Error, please enter a valid arguement, either `ask, `bid or `."];
  $[all null d`exchange;                                                                                                                        			//get the correct exchanges to query
    exchanges: enlist exec exchange from select distinct exchange from exchange_top;
    exchanges: enlist d`exchange];
  if[any .z.d=d`date;
    rdbresult:{?[exchange_top; ((in;`sym; x);(in;`exchange; y)); `date`sym!(($;enlist `date;`time);`sym); z]}[syms;exchanges;coldict];          			//select z by date,sym from table where sym in x, exchange in y
    ];
  if[any .z.d>d`date;
  //select colDict by date, sym from table where date in dates, sym in Syms, exchange in Excahnges
    hdbresult:{[dates;Syms;Exchanges;Cols] ?[exchange_top; ((in;`date;dates);(in;`sym;Syms);(in;`exchange;Exchanges)); `date`sym!(($;enlist`date;`time);`sym); Cols]}[enlist d`date; syms; exchanges;coldict];
    ];
  rdbresult,hdbresult
 };



//reassigns the dict keys to atoms

dictfix:{[dict;dictkey]
  dict:@[dict;dictkey;:;first dict[dictkey]];
  dict
 };



//creates a table showing the top of the book for each excahnges at a given time

createarbtable:{[d]
  if[not 99h=type d; '"the arguement passed needs to be a dictionary"];													//checks a dictionary has been passed
  if[not `symbol in key d; '"You need to have symbol as a key"];
  d2:`symbol`starttimestamp`endtimestamp`bucketsize`exchanges!`````;													//default dictionary
  d:d2,d;
  if[not all keyresult:key[d] in dictkeys:`symbol`starttimestamp`endtimestamp`bucketsize`exchanges;									//checks the correct keys have been passed
    '"The following keys are incorrect ", ", " sv string key[d] where 0=keyresult,". Valid keys are symbol, starttimestamp, endtimestamp, bucketsize and exchanges"];
  d:enlist each d;																			//allows us to amedn the dictionary regardless of type
  d:assign[d;(`starttimestamp`endtimestamp`bucketsize)!(`timestamp$.z.d;.z.p;`second$2*.crypto.deffreq)];								//gives default values if nulls inserted
  d:dictfix/[d;] `symbol`starttimestamp`endtimestamp`bucketsize;													//reassigns the dictionary keys to atoms
  d:assign[d;enlist[`exchanges]!enlist exec exchange from select distinct exchange from exchange_top where time within (d`starttimestamp;d`endtimestamp)];	//gets the distinct list of exchanges in the time period
  if[not -11h=type d`symbol; '"The symbol value has to be a symbol atom"];												//checks the correct type has been entered for symbol key
  if[not 12h=type d[`starttimestamp],d`endtimestamp; '"The values for starttimestamp and endtimestamp need to be timestamp atoms"];					//checks the type for the timestamp enteries
  if[not -18h=type d`bucketsize; '"The value of bucketsize needs to be a second atom"];											//checks the bucketsize type
  if[not 11h=abs type d`exchanges; d[`exchanges]:first d`exchanges];
  if[not 11h=abs type d`exchanges; '"The value of exchanges needs to be a symbol"];
  d[`bucketsize]:`long$d`bucketsize;																	//coverts the bucketSize to an integer
  if[not d[`symbol] in execcol[exchange_top;`sym]; '"This symbol is not in the exchange_top table, please enter a valid one"];						//checks that the symbol passed exists in our table
  if[all .z.p<d[`starttimestamp],d`endtimestamp; '"Enter a valid timestamp, one less than ",string .z.p];								//checks the timestamps entered can be queried
  if[not (`date$d`starttimestamp)=`date$d`endtimestamp; '"The date part startimestamp and endtimestamp must be the same"];						//ensures the query is over one day
  if[d[`starttimestamp]>d`endtimestamp; '"starttimestamp must be less than endtimestamp"];										//ensures the startTimestamp is smaller than the endTimestamp
  t:select time,exchange,bid,ask,bidSize,askSize from exchange_top where time within (d`starttimestamp;d`endtimestamp),sym in d`symbol, exchange in d`exchanges;	//select appriopiate cols
  if[not count t; '"There is no data available in the timestamp range"];
  assignFunc:{set'[x;y]};                                                                                                                       			//used in getting exchange tables
  exchanges:exec exchange from select distinct exchange from t;                                                                                 			//gets names of exchanges
  tablenames:{`$string[x],"Table"} each exchanges;                                                                                              			//table names for each exchange
  //creates a list of tables with the best bid and ask for each exchange
  exchangetables:assignFunc[tablenames;{[x;y;z] (`time;`$string[x],"Bid";`$string[x],"Ask";`$string[x],"BidSize";`$string[x],"AskSize") xcol select bid:first bid,ask:first ask ,bidSize:first bidSize ,askSize:first askSize  by time:z xbar time.second from y where exchange=x}[;t;d`bucketsize] each exchanges];
  $[exchangenumber:1=count exchangetables;                                                                                                      			//depending on how many tables does the appriopiate function
    arbtable:value first exchangetables;                                                                                                        			//if only one exchange, creates arbTable
    arbtable:(,'/) value each exchangetables];                                                                                                  			//if multiple exchanges joins them to create arbTable
  $[exchangenumber;
    :arbtable;                                                                                                                                 	 			//if only one exchange used output arbTable
    arbtable:0!`time xasc arbtable];                                                                                                            			//if more than one exchange used start to edit
  colnames: cols arbtable;                                                                                                                      			//get column names
  arbtable:(`time,colnames where not null first each ss[;"Bid"] each string colnames) xcols arbtable;                                           			//reorder the cols to have time, bids, asks
  arbtable:{![x;();0b;y]}[arbtable;(1 _ colnames)!fills,' 1_ colnames];                                                                         			//fill in null values
  arbtable                                                                                                                                      			//output table
 };



//Used for creating column names

colnamesfunc:{[table;word]
  col where (col:cols table) like word
 };




//adds a column saying if there is a chance of risk free profit

arbitrage:{[d]
  arbtable:createarbtable[d];											                  					//create arbitrage table
  bidcols:colnamesfunc[arbtable;"*Bid"];                                                                                          					//create list of bid column names
  askcols:colnamesfunc[arbtable;"*Ask"];                                                                                          					//create list of ask column names
  extractcols:{[table;columns] ?[table;();0b;columns!columns]};                                                                   					//function for extracting columns from arbitrage table
  bidtab:extractcols[arbtable;bidcols];                                                                                           					//create table of bid columns only
  asktab:extractcols[arbtable;askcols];                                                                                           					//create table of ask columns only
  //create matrix of arbitrage opportunities
  arbitrageops:{[bidtable;asktable;length](value bidtable[length])>\:value (max value max bidtable)^asktable[length]}[bidtab;asktab]'[til count arbtable];
  //create a new column which shows if arbitrage opportunity exists for each row
  update arbitrage:1b from arbtable where any flip {[opstable;length] any each opstable[length]}[arbitrageops]'[til count arbitrageops]
 };




//adds a column saying how much potenital profit you can make by only looking at the best bid and ask

profit:{[d]
  table:arbitrage[d];
  arbitragerows:exec i from table where arbitrage=1b;
  updatetablefunc:{[table;row]
    bidcols:colnamesfunc[table;"*Bid"];                                                                 								//gets the bid cols
    askcols:colnamesfunc[table;"*Ask"];                                                                 								//gets the ask cols
    pricefunc:{?[x;enlist (=;`i;z);();y!y]};                                                            								//used for getting prices from exchanges
    biddict:pricefunc[table;bidcols;row];                                                               								//dict of exchanges and their bids
    askdict:pricefunc[table;askcols;row];                                                               								//dict of exchanges and their asks
    sellpricecol:biddict?max biddict;                                                                   								//exchange we will sell on
    buypricecol:askdict?min askdict;                                                                    								//exchange we will buy on
    bidsizecol:`$(-3_string sellpricecol),"BidSize";                                                    								//bid size col
    asksizecol:`$(-3_string buypricecol),"AskSize";                                                     								//ask size col
    sellsize:value pricefunc[table;enlist bidsizecol;row];
    buysize:value pricefunc[table; enlist asksizecol;row];
    size:min buysize,sellsize;                                                                          								//size of sym we will buy and sell
    table:update profit:first (size*max biddict)-size* min askdict from table where i=row};
  (ljf/) `time xkey' updatetablefunc[table;] each arbitragerows
 };
               
