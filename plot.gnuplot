#!/usr/bin/env gnuplot
set terminal svg size 1024,768 background rgb "white"
set style data lines
set xdata time
#set datafile separator ", "
set timefmt "%Y-%m-%dT%H:%M:%S"
set format x "%m/%d/%Y %H:%M:%S"

set output "query-IU-ANMO-BH1.svg"
plot "query-IU-ANMO-BH1.txt" using 1:2

set output "query-IU-ANMO-BHZ.svg"
plot "query-IU-ANMO-BHZ.txt" using 1:2
