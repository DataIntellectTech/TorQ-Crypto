// Settings for pythonfeed1 — kdb+ receiver for Python WebSocket feed manager

\d .proc
loadprocesscode:1b

\d .servers
enabled:1b
STARTUP:1b
CONNECTIONS:`tickerplant`rdb
HOPENTIMEOUT:30000

\d .pythonfeed
loglevel:@[value;`.pythonfeed.loglevel;`info]

\d .
