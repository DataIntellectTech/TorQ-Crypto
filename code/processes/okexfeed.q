// initialise connections

.servers.startup[]

\d .okex

.okex.prev:([]time:`timestamp$(); sym:`g#`symbol$(); exchangeTime:`timestamp$();bid:(); bidSize:(); ask:();askSize:())

feed:{[]
  if[10h~type .okex.syms;.okex.syms:enlist .okex.syms];
  qt:.okex.quotes'[.okex.syms];
  if[99h~type qt;qt:enlist qt];
  t:select time:.z.p,
           sym:`$sym,
           exchangeTime:timestamp,
           exchange:`$"okex",
           bid:"F"$bid,
           bidSize:"F"$bidSize,
           ask:asc each "F"$ask,
           askSize:asc each "F"$askSize 
  from qt;
  if[count ts:@[t;(),where not max (~\:/:/)`time`exchangeTime _/:tl:(t;$[c:count .okex.prev;c;1]#.okex.prev)];
    h:.servers.gethandlebytype[`tickerplant;`any];
    h(`.u.upd;`exchange;get flip ts);
    h(`.u.upd;`okex;get flip ![ts;();0b;enlist `exchange]);
    ts:@[tt 0;(),where not max (~\:/:/)`time`exchangeTime _/:tt:{@[x;where 0=type each flip x;first each]}each tl];
    if[count ts; h(`.u.upd;`exchange_top;get flip ts)];
    .okex.prev:t];
 }

quotes:{[x]
  d:@[(.j.k .Q.hg `$.okex.main_url,x,"/book?size=",.okex.limit);`sym`limit;:;(upper x except "-_";.okex.limit)];
  update  bid:first each bids,
          bidSize:.[bids;(::;1)],
          ask:first each asks,
          askSize:.[asks;((::;1))],
          timestamp:"P"$-1_ssr/[timestamp;("-";"T");(".";"D")]
  from d
 }

.timer.repeat[.proc.cp[];0Wp;0D00:00:30.000;(`.okex.feed;`);"Publish Feed"];

\d .

