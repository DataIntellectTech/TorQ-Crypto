// initialise connections
.servers.startup[]

\d .huobi

syms:.crypto.symmap'[exec sym from .crypto.symconfig where huobisym;`huobisym]

.huobi.prev:([]time:`timestamp$(); sym:`g#`symbol$();exchangeTime:`timestamp$();bid:(); bidSize:(); ask:();askSize:())

feed:{
  if[10h~type .huobi.syms;.huobi.syms:enlist .huobi.syms];
  qt:.huobi.quotes'[.huobi.syms];
  if[99h~type qt;qt:enlist qt];
  t:select time:.z.p,
           sym:`$sym,
           exchangeTime:date,
           exchange:`huobi,
           bid:`float$bid,
           bidSize:`float$bidSize,
           ask:`float$ask,
           askSize:`float$askSize
  from qt;
  if[0=count ts:@[t;where not max (~\:/:/)`time`exchangeTime _/:tl:(t;{(1|count x)#x}.huobi.prev)];:()];
    h:neg .servers.gethandlebytype[`tickerplant;`any];
    h(`.u.upd;`exchange;value flip ts);
    h(`.u.upd;`huobi;value flip delete exchange from ts);
    ts:@[tt 0;where not max (~\:/:/)`time`exchangeTime _/:tt:{@[x;where 0=type each flip x;first each]}each tl];
    if[count ts; h(`.u.upd;`exchange_top;value flip ts)];
    .huobi.prev:t;
 }

quotes:{
  d:@[(r:.j.k .Q.hg .huobi.main_url,x,"&depth=",.huobi.limit)`tick;`sym`limit;:;(upper x;.huobi.limit)];
  update bid:first each bids,
         bidSize:last each bids,
         ask:first each asks,
         askSize:last each asks,
         date:"P"$string"i"$r[`ts]%1e3
  from d
 }

runfeed:{@[feed;`;{.lg.e[`timer;"error: ",x]}]}

.timer.repeat[.proc.cp[];0Wp;.huobi.freq;(`.huobi.runfeed;`);"Publish Feed"];

\d .

