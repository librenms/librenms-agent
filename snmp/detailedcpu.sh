#!/bin/bash

# This is to get Detailed CPU stats into LibreNMS. 
# The goal being to track Steal and IOWait in shared virtual enviornements. 

# Please make sure you have tail, vmstat, and awk installed.
# Currently modern kernels beyond 2.6.11 should be supported. 

# By Munzy https://github.com/Munzy

# vmstat -w
# procs -----------------------memory---------------------- ---swap-- -----io---- -system-- --------cpu--------
#  r  b         swpd         free         buff        cache   si   so    bi    bo   in   cs  us  sy  id  wa  st
#  0  0        18432       348376       256872      3150908    0    0     0     2    1    2   0   0 100   0   0
#
# vmstat | tail -n 1 |  awk '{print $13, $14, $15, $16, $17}'
# 0 0 100 0 0

# $13 = User
# $14 = System
# $15 = Idle
# $16 = IO Wait
# $17 = CPU Steal


vmstat | tail -n 1 |  awk '{print $13}'
vmstat | tail -n 1 |  awk '{print $14}'
vmstat | tail -n 1 |  awk '{print $15}'
vmstat | tail -n 1 |  awk '{print $16}'
vmstat | tail -n 1 |  awk '{print $17}'
