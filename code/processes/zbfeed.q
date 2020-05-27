// initialise connections

.servers.startup[]

\d .zb

syms:.crypto.symmap'[exec sym from .crypto.symconfig where zbsym;`zbsym]

.zb.prev:([]time:`timestamp$();sym:`g#`symbol$(); exchangeTime:`timestamp$();bid:(); bidSize:(); ask:();askSize:())

feed:{
  if[10h~type .zb.syms;.zb.syms:enlist .zb.syms];
  qt:.zb.quotes'[.zb.syms]; 
  if[99h~type qt;qt:enlist qt];
  t:select time:.z.p,
           sym:`$sym,
           exchangeTime:timestamp,
           exchange:`zb,
           bid:`float$bid,
           bidSize:`float$bidSize,
           ask:asc each `float$ask,
           askSize:asc each `float$askSize
  from qt;
  if[0=count ts:@[t;where not max (~\:/:/)`time`exchangeTime _/:tl:(t;{(1|count x)#x}.zb.prev)];:()];
    h:neg .servers.gethandlebytype[`tickerplant;`any];
    h(`.u.upd;`exchange;value flip ts);
    h(`.u.upd;`zb;value flip delete exchange from ts);
    ts:@[tt 0;where not max (~\:/:/)`time`exchangeTime _/:tt:{@[x;where 0=type each flip x;first each]}each tl];
    if[count ts; h(`.u.upd;`exchange_top;value flip ts)];
    .zb.prev:t;
 }

quotes:{[x]
  d:@[(.j.k .Q.hg .zb.main_url,x,"&size=",.zb.limit);`sym`limit;:;(upper x except "-_";.zb.limit)];
  update bid:first each bids, 
         bidSize:last each bids,
         ask:first each asks, 
         askSize:last each asks,
         timestamp:"P"$string"i"$timestamp 
  from d
 }

runfeed:{@[feed;`;{.lg.e[`timer;"error: ",x]}]}

.timer.repeat[.proc.cp[];0Wp;.zb.freq;(`.zb.runfeed;`);"Publish Feed"];

\d .
