/ initialise connections
.servers.startup[]

\d .bhex

syms:.crypto.symmap'[exec sym from .crypto.symconfig where bhexsym;`bhexsym]

.bhex.prev:([]time:`timestamp$(); sym:`g#`symbol$();exchangeTime:`timestamp$();bid:(); bidSize:(); ask:();askSize:())

feed:{
  if[10h~type .bhex.syms;.bhex.syms:enlist .bhex.syms];
  qt:.bhex.quotes'[.bhex.syms];
  if[99h~type qt;qt:enlist qt];
  t:select time:.z.p,
           sym:`$sym,
           exchangeTime:date,
           exchange:`bhex,
           bid:`float$bid,
           bidSize:`float$bidSize,
           ask:`float$ask,
           askSize:`float$askSize
  from qt;
  if[0=count ts:@[t;where not max (~\:/:/)`time`exchangeTime _/:tl:(t;{(1|count x)#x}.bhex.prev)];:()];
    h:neg .servers.gethandlebytype[`tickerplant;`any];
    h(`.u.upd;`exchange;value flip ts);
    h(`.u.upd;`bhex;value flip delete exchange from ts);
    ts:@[tt 0;where not max (~\:/:/)`time`exchangeTime _/:tt:{@[x;where 0=type each flip x;first each]}each tl];
    if[count ts; h(`.u.upd;`exchange_top;value flip ts)];
    .bhex.prev:t;
 }

quotes:{
  d:@[(.j.k .Q.hg .bhex.main_url,x,"&limit=",.bhex.limit);`sym`limit;:;(upper x;.bhex.limit)];
  update bid:"F"$(first each bids),
         bidSize:"F"$(last each bids),
         ask:"F"$(first each asks),
         askSize:"F"$(last each asks),
         date:"P"$string"i"$time%1e3
  from d
 }

runfeed:{@[feed;`;{.lg.e[`timer;"error: ",x]}]}

.timer.repeat[.proc.cp[];0Wp;.bhex.freq;(`.bhex.runfeed;`);"Publish Feed"];

\d .
