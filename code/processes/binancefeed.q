// initialise connections

.servers.startup[]

\d .binance

.binance.prev:([]time:`timestamp$(); sym:`g#`symbol$(); exchangeTime:`timestamp$();bid:(); bidSize:(); ask:();askSize:())

h:.servers.gethandlebytype[`tickerplant;`any];

feed:{
  if[10h~type .binance.syms;.binance.syms:enlist .binance.syms];
  qt:.binance.quotes'[.binance.syms];
  serverTime:"P"$string "i"$0.001*(.j.k .Q.hg `$"https://api.binance.com/api/v1/time")`serverTime;
  if[99h~type qt;qt:enlist qt];  
  t:select time:.z.p,
           sym:`$sym,
           exchangeTime:serverTime,
           exchange:`binance,
           bid:"F"$bid,
           bidSize:"F"$bidSize,
           ask:asc each "F"$ask,
           askSize:asc each "F"$askSize
  from qt;
  if[0=count ts:@[t;where not max (~\:/:/)`time`exchangeTime _/:tl:(t;{(1|count x)#x}.binance.prev)];:()];
    h(`.u.upd;`exchange;value flip ts);
    h(`.u.upd;`binance;value flip delete exchange from ts);
    ts:@[tt 0;where not max (~\:/:/)`time`exchangeTime _/:tt:{@[x;where 0=type each flip x;first each]}each tl];
    if[count ts; h(`.u.upd;`exchange_top;value flip ts)];
    .binance.prev:t;
 }

quotes:{[x]
  d:@[(.j.k .Q.hg `$.binance.main_url,x,"&limit=",.binance.limit);`sym`limit;:;(upper x except "-_";.binance.limit)];
  update bid:first each bids,
         bidSize:last each bids,
         ask:first each asks,
         askSize:last each asks 
  from d
 }

.timer.repeat[.proc.cp[];0Wp;0D00:00:30.000;(`.binance.feed;`);"Publish Feed"];

\d .
