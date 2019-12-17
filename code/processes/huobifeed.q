// initialise connections
.servers.startup[]

\d .huobi

symconfig:("*BBBBB";enlist ",") 0:hsym first .proc.getconfigfile["symconfig.csv"];
commonsyms:("******";enlist ",") 0:hsym first .proc.getconfigfile["commonsyms.csv"];

syms:exec sym from symconfig where huobisym;
exchangesyms:exec huobisym from commonsyms where sym in syms;

.huobi.prev:([]time:`timestamp$(); sym:`g#`symbol$();exchangeTime:`timestamp$();bid:(); bidSize:(); ask:();askSize:())

feed:{
  if[10h~type .huobi.syms;.huobi.syms:enlist .huobi.syms];
  qt:.huobi.quotes'[.huobi.exchangesyms];
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
  d:@[(.j.k .Q.hg`$.huobi.main_url,x,"&depth=",.huobi.limit)`tick;`sym`limit;:;(upper x;.huobi.limit)];
  update bid:first each bids,
         bidSize:last each bids,
         ask:first each asks,
         askSize:last each asks,
         date:"P"$string"i"$ts%1e3
  from d
 }

.timer.repeat[.proc.cp[];0Wp;0D00:00:30.000;(`.huobi.feed;`);"Publish Feed"];

\d .

