# Getting Started

### Installation

1.  Download and install kdb+ from [Kx Systems](http://kx.com)

2.  Download the main TorQ codebase from
    [here](https://github.com/AquaQAnalytics/TorQ/tree/master)

3.  Download the TorQ Crypto from
    [here](https://github.com/AquaQAnalytics/TorQ-Crypto)

4.  Place the Crypto package over the top of the main TorQ package


###### Example Linux Installation:

    ~/crypto:cross@homer$ git clone https://github.com/AquaQAnalytics/TorQ.git
    ~/crypto:cross@homer$ git clone https://github.com/AquaQAnalytics/TorQ-Crypto.git
    ~/crypto:cross@homer$ mkdir deploy
    ~/crypto:cross@homer$ cp -r TorQ/* deploy/
    ~/crypto:cross@homer$ cp -r TorQ-Crypto/* deploy/
    ~/crypto:cross@homer$ ls deploy/
    appconfig  aquaq-torq-brochure.pdf  code  config  database.q  datadog  docs  hdb  html  lib  LICENSE  logs  mkdocs.yml  monit  README.md  setenv.sh  tests  torq.q  torq.sh


### Start-up

After specifiying your sever in config/process.csv and KDB base port
in setenv.sh. You can set your environment variables and run the start
script.

     ~/crypto/deploy:cross@homer$ . setenv.sh
     ~/crypto/deploy:cross@homer$ . torq.sh start all
     ~/crypto/deploy:cross@homer$ . torq.sh summary
     TIME      |  PROCESS        |  STATUS  |  PID   |  PORT
     14:27:46  |  discovery1     |  up      |  7187  |  46001
     14:27:47  |  tickerplant1   |  up      |  7289  |  46000
     14:27:47  |  rdb1           |  up      |  7388  |  46002
     14:27:47  |  hdb1           |  up      |  7493  |  46003
     14:27:47  |  hdb2           |  up      |  7594  |  46004
     14:27:47  |  wdb1           |  up      |  7704  |  46005
     14:27:47  |  sort1          |  up      |  7807  |  46006
     14:27:47  |  gateway1       |  up      |  7909  |  46007
     14:27:48  |  killtick       |  down    |
     14:27:48  |  monitor1       |  up      |  8011  |  46009
     14:27:48  |  tpreplay1      |  down    |
     14:27:48  |  housekeeping1  |  up      |  8112  |  46011
     14:27:48  |  reporter1      |  up      |  8215  |  46012
     14:27:48  |  compression1   |  down    |
     14:27:48  |  chainedtp1     |  up      |  8321  |  46014
     14:27:48  |  sortslave1     |  up      |  8420  |  46015
     14:27:49  |  sortslave2     |  up      |  8523  |  46016
     14:27:49  |  finexfeed1     |  up      |  8624  |  46017
     14:27:49  |  okexfeed1      |  up      |  8725  |  46018
     14:27:49  |  zbfeed1        |  up      |  8827  |  46019
     14:27:49  |  huobifeed1     |  up      |  8932  |  46020
     14:27:49  |  bhexfeed1      |  up      |  9035  |  46021

The stack can be stopped by running . torq.sh stop all

### TorQ Debug Mode

It is stright forward to run processes in debug mode with TorQ 
as show below. After starting you stack you should see the tables 
in the RDB being to populate:

    ~/crypto/deploy:cross@homer$ . torq.sh stop rdb1
    ~/crypto/deploy:cross@homer$ . torq.sh debug rdb1
    q)tables[]!count each `. tables[]
    bhex        | 10
    exchange    | 50
    exchange_top| 50
    finex       | 10
    huobi       | 10
    okex        | 10
    zb          | 10

We have also included HDB paritions from 2020.03.29/2020.03.29
when the feeds where subscribed to Bitcoin and Ethereum.  

     ~/crypto/deploy:cross@homer$ . torq.sh stop hdb1
     ~/crypto/deploy:cross@homer$ . torq.sh debug hdb1
     q)tables[]!count each `. tables[]
     bhex        | 10722
     exchange    | 53836
     exchange_top| 53723
     finex       | 10054
     okex        | 11250
     zb          | 10644
     q)select count i by date, sym from exchange_top
     date       sym    | x
     ------------------| -----
     2020.03.29 BTCUSDT| 13378
     2020.03.29 ETHUSDT| 13363
     2020.03.30 BTCUSDT| 13495
     2020.03.30 ETHUSDT| 13487

### File Structure:

    |-- LICENSE
    |-- README.md
    |-- appconfig
    |   |-- passwords
    |   |   |-- accesslist.txt
    |   |   |-- bhexfeed.txt
    |   |   |-- finexfeed.txt
    |   |   |-- huobifeed.txt
    |   |   |-- okexfeed.txt
    |   |   `-- zbfeed.txt
    |   |-- settings
    |   |   |-- bhexfeed.q
    |   |   |-- chainedtp.q
    |   |   |-- compression.q
    |   |   |-- default.q
    |   |   |-- finexfeed.q
    |   |   |-- gateway.q
    |   |   |-- huobifeed.q
    |   |   |-- killtick.q
    |   |   |-- monitor.q
    |   |   |-- okexfeed.q
    |   |   |-- rdb.q
    |   |   |-- sort.q
    |   |   |-- tickerplant.q
    |   |   |-- wdb.q
    |   |   `-- zbfeed.q
    |   |-- application.txt
    |   |-- compressionconfig.csv
    |   |-- dependency.csv
    |   |-- housekeeping.csv
    |   |-- process.csv
    |   |-- reporter.csv
    |   |-- symconfig.csv
    |   `-- symmap.csv
    |-- code
    |   |-- cryptofeed
    |   |   `-- cryptofeed.q
    |   |-- cryptofunctions
    |   |   `-- cryptolib.q
    |   `-- processes
    |       |-- bhexfeed.q
    |       |-- finexfeed.q
    |       |-- huobifeed.q
    |       |-- okexfeed.q
    |       `-- zbfeed.q
    |-- hdb/database             <- example hdb data
    |   |--2020.03.29
    |   |--2020.03.30
    |   `-- sym
    |-- database.q
    `-- setenv.sh           <- set environment variables
    |-- LICENSE
    |-- README.md
    |-- appconfig
    |   |-- passwords
    |   |   |-- accesslist.txt
    |   |   |-- bhexfeed.txt
    |   |   |-- finexfeed.txt
    |   |   |-- huobifeed.txt
    |   |   |-- okexfeed.txt
    |   |   `-- zbfeed.txt
    |   |-- settings
    |   |   |-- bhexfeed.q
    |   |   |-- chainedtp.q
    |   |   |-- compression.q
    |   |   |-- default.q
    |   |   |-- finexfeed.q
    |   |   |-- gateway.q
    |   |   |-- huobifeed.q
    |   |   |-- killtick.q
    |   |   |-- monitor.q
    |   |   |-- okexfeed.q
    |   |   |-- rdb.q
    |   |   |-- sort.q
    |   |   |-- tickerplant.q
    |   |   |-- wdb.q
    |   |   `-- zbfeed.q
    |   |-- application.txt
    |   |-- compressionconfig.csv
    |   |-- dependency.csv
    |   |-- housekeeping.csv
    |   |-- process.csv
    |   |-- reporter.csv
    |   |-- symconfig.csv
    |   `-- symmap.csv
    |-- code
    |   |-- cryptofeed
    |   |   `-- cryptofeed.q
    |   |-- cryptofunctions
    |   |   `-- cryptolib.q
    |   `-- processes
    |       |-- bhexfeed.q
    |       |-- finexfeed.q
    |       |-- huobifeed.q
    |       |-- okexfeed.q
    |       `-- zbfeed.q
    |-- hdb/database             <- example hdb data
    |   |--2020.03.29
    |   |--2020.03.30
    |   `-- sym
    |-- database.q

The package consists of:

-   fullly configurable Cyptocurrency exchange feed handlers

-   a slightly modified version of kdb+tick from Kx Systems

-   an example set of historic data

-   configuration changes for base TorQ

-   functions for data analysis to run on the RDB and HDB

-   start and stop scripts

Make It Your Own
----------------

This system is production ready. Users may customize what currencies are 
subscribed to, the rate of data retreval and even add new feed handlers!
