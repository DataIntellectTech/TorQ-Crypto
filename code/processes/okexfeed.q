// initialise connections

.servers.startup[]

\d .okex

syms:.crypto.symmap'[exec sym from .crypto.symconfig where okexsym;`okexsym]

.okex.prev:([]time:`timestamp$(); sym:`g#`symbol$(); exchangeTime:`timestamp$();bid:(); bidSize:(); ask:();askSize:())

feed:{[]
  if[10h~type .okex.syms;.okex.syms:enlist .okex.syms];
  qt:.okex.quotes'[.okex.syms];
  if[99h~type qt;qt:enlist qt];
  t:select time:.z.p,
           sym:`$sym,
           exchangeTime:timestamp,
           exchange:`okex,
           bid:"F"$bid,
           bidSize:"F"$bidSize,
           ask:asc each "F"$ask,
           askSize:asc each "F"$askSize 
  from qt;
  if[0=count ts:@[t;where not max (~\:/:/)`time`exchangeTime _/:tl:(t;{(1|count x)#x}.okex.prev)];:()];
    h:neg .servers.gethandlebytype[`tickerplant;`any];
    h(`.u.upd;`exchange;value flip ts);
    h(`.u.upd;`okex;value flip delete exchange from ts);
    ts:@[tt 0;where not max (~\:/:/)`time`exchangeTime _/:tt:{@[x;where 0=type each flip x;first each]}each tl];
    if[count ts; h(`.u.upd;`exchange_top;value flip ts)];
    .okex.prev:t;
 }

quotes:{[x]
  d:@[(.j.k .Q.hg .okex.main_url,x,"/book?size=",.okex.limit);`sym`limit;:;(upper x except "-_";.okex.limit)];
  update  bid:first each bids,
          bidSize:.[bids;(::;1)],
          ask:first each asks,
          askSize:.[asks;((::;1))],
          timestamp:"P"$-1_ssr/[timestamp;("-";"T");(".";"D")]
  from d
 }

runfeed:{@[feed;`;{.lg.e[`timer;"error: ",x]}]}

.timer.repeat[.proc.cp[];0Wp;.okex.freq;(`.okex.runfeed;`);"Publish Feed"];

\d .

