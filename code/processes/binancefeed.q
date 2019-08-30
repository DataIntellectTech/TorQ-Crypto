// initialise connections

.servers.startup[]

\d .binance

.binance.prev:([]time:`timestamp$(); sym:`g#`symbol$(); exchangeTime:`timestamp$();bid:(); bidSize:(); ask:();askSize:())

feed:{
  if[10h~type .binance.syms;.binance.syms:enlist .binance.syms];
  qt:.binance.quotes'[.binance.syms];
  serverTime:"P"$string "i"$0.001*(.j.k .Q.hg `$"https://api.binance.com/api/v1/time")`serverTime;
  if[99h~type qt;qt:enlist qt];  
  t:select time:.z.p,
           sym:`$sym,
           exchangeTime:serverTime,
           exchange:`$"binance",
           bid:"F"$bid,
           bidSize:"F"$bidSize,
           ask:asc each "F"$ask,
           askSize:asc each "F"$askSize
  from qt;
  if[count ts:@[t;(),where not max (~\:/:/)`time`exchangeTime _/:tl:(t;$[c:count .binance.prev;c;1]#.binance.prev)];
    h:.servers.gethandlebytype[`tickerplant;`any];
    h(`.u.upd;`exchange;get flip ts);
    h(`.u.upd;`binance;get flip ![ts;();0b;enlist `exchange]);
    ts:@[tt 0;(),where not max (~\:/:/)`time`exchangeTime _/:tt:{@[x;where 0=type each flip x;first each]}each tl];
    if[count ts; h(`.u.upd;`exchange_top;get flip ts)];
    .binance.prev:t];
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
