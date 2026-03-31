// Settings for cryptoagg1 — real-time aggregation process

\d .proc
loadprocesscode:1b

\d .servers
enabled:1b
STARTUP:1b
CONNECTIONS:`tickerplant
HOPENTIMEOUT:30000

\d .cryptoagg
stalenesswindow:@[value;`.cryptoagg.stalenesswindow;0D00:00:30]
outlierthreshold:@[value;`.cryptoagg.outlierthreshold;50f]
loglevel:@[value;`.cryptoagg.loglevel;`info]
gc:@[value;`.cryptoagg.gc;0b]

\d .
