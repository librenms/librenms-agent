#!/bin/bash
unboundctl='/usr/bin/env unbound-control'
if [ "$?" != "0" ]; then
#Unbound control executable doesn't exist
exit
fi
echo '<<<app-unbound>>>'
$unboundctl stats
