// Configuration of crypto feeds

\d .crypto

// table of syms each feed subscribes to
symconfig:("*BBBBB";enlist ",") 0:hsym first .proc.getconfigfile["symconfig.csv"];

// table mapping syms to format used on each exchange
commonsyms:("******";enlist ",") 0:hsym first .proc.getconfigfile["commonsyms.csv"];

\d .
