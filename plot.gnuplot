#!/usr/bin/env gnuplot
set terminal svg size 1024,768 background rgb "white"

# plotting tspair
#
# set style data lines
# set xdata time
# #set datafile separator ", "
# set timefmt "%Y-%m-%dT%H:%M:%S"
# set format x "%m/%d/%Y %H:%M:%S"
# 
# set output "query-IU-ANMO-BH1.svg"
# plot "query-IU-ANMO-BH1-tspair.txt" using 1:2
# 
# set output "query-IU-ANMO-BHZ.svg"
# plot "query-IU-ANMO-BHZ-tspair.txt" using 1:2

# plotting slist

set style data lines
set xlabel "seconds"	# the hz is specified in the file header comments
set output "query-IU-ANMO-BH1.svg"
plot "query-IU-ANMO-BH1-slist.txt" using ($0/20.):1
set output "query-IU-ANMO-BH2.svg"
plot "query-IU-ANMO-BH2-slist.txt" using ($0/20.):1
set output "query-IU-ANMO.svg"
plot "query-IU-ANMO-slist.txt" using ($0/20.):1
