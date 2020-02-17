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
