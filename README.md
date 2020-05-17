# TorQ-Crypto

TorQ Crypto provides an example of how an application can be built and 
deployed on top of the [TorQ framework](https://aquaqanalytics.github.io/TorQ/). 
This application  behaves in a similar manner to the Finance Starter Pack 
with the main difference being that TorQ Crypto collects and stores real 
time data. 

This package includes:

- Fully configurable subscription to 5 Cryptocurrency exchanges
- Collection and storage  of real time level 2 order book data
- Custom API functions for data analysis

## Installation 

1.  Download and install kdb+ from [Kx Systems](http://kx.com)

2.  Download the main TorQ codebase from
    [here](https://github.com/AquaQAnalytics/TorQ/tree/master)

3.  Download TorQ Crypto from
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

## Start-up

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
     14:27:48  |  monitor1       |  up      |  8011  |  46009
     14:27:48  |  housekeeping1  |  up      |  8112  |  46011
     14:27:48  |  reporter1      |  up      |  8215  |  46012
     14:27:48  |  chainedtp1     |  up      |  8321  |  46014
     14:27:48  |  sortslave1     |  up      |  8420  |  46015
     14:27:49  |  sortslave2     |  up      |  8523  |  46016
     14:27:49  |  finexfeed1     |  up      |  8624  |  46017
     14:27:49  |  okexfeed1      |  up      |  8725  |  46018
     14:27:49  |  zbfeed1        |  up      |  8827  |  46019
     14:27:49  |  huobifeed1     |  up      |  8932  |  46020
     14:27:49  |  bhexfeed1      |  up      |  9035  |  46021

By entering the RDB process in debug mode you should see the following
tables being populated:

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


More information on how to configure and get started can be found [here](docswebsite).
