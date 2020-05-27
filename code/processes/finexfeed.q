// initialise connections

.servers.startup[]

\d .finex

syms:.crypto.symmap'[exec sym from .crypto.symconfig where finexsym;`finexsym]

.finex.prev:([]time:`timestamp$(); sym:`g#`symbol$();exchangeTime:`timestamp$();bid:(); bidSize:(); ask:();askSize:())

feed:{
  if[10h~type .finex.syms;.finex.syms:enlist .finex.syms];
  qt:.finex.quotes'[.finex.syms];
  if[99h~type qt;qt:enlist qt];
  t:select time:.z.p,
           sym:`$sym,
           exchangeTime:date,
           exchange:`finex,
           bid:`float$bid,
           bidSize:`float$bidSize,
           ask:asc each `float$ask,
           askSize:asc each `float$askSize
  from qt;
  if[0=count ts:@[t;where not max (~\:/:/)`time`exchangeTime _/:tl:(t;{(1|count x)#x}.finex.prev)];:()];
    h:neg .servers.gethandlebytype[`tickerplant;`any];
    h(`.u.upd;`exchange;value flip ts);
    h(`.u.upd;`finex;value flip delete exchange from ts);
    ts:@[tt 0;where not max (~\:/:/)`time`exchangeTime _/:tt:{@[x;where 0=type each flip x;first each]}each tl];
    if[count ts; h(`.u.upd;`exchange_top;value flip ts)];
    .finex.prev:t;
 }

quotes:{[x]
  d:@[(.j.k .Q.hg .finex.main_url,x,"&limit=",.finex.limit);`sym`limit;:;(upper x except "-_";.finex.limit)];
  update bid:first each bids,
         bidSize:last each bids,
         ask:first each asks,
         askSize:last each asks,
         date:"P"$string"i"$date
  from d
 }

runfeed:{@[feed;`;{.lg.e[`timer;"error: ",x]}]}

.timer.repeat[.proc.cp[];0Wp;.finex.freq;(`.finex.runfeed;`);"Publish Feed"];

\d .
