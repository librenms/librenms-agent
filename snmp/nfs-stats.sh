#!/bin/bash
############################################################
# copy this file somewhere like /opt and chmod +x it       #
# edit your snmpd.conf and add the below line and restart: #
# extend nfs-stats /opt/nfs-stats.sh                       #
############################################################
exists_command()
{
  command -v "$1" >/dev/null 2>&1
}
require_commands=("cat" "sed" "awk" "tr" "paste" "rm" "mv") ;

for i in "${require_commands[@]}" ;
do
    if exists_command $i; then
        eval "BIN_${i^^}"="$(command -v $i)";
    else
        echo "Your system does not have [$i]";
        exit
    fi

done ;

CFG_NFSFILE='/proc/net/rpc/nfsd'

LOG_OLD='/tmp/nfsio_old'
LOG_NEW='/tmp/nfsio_new'
LOG_FIX='/tmp/nfsio_fix'

if [ ! -f $CFG_NFSFILE ]; then
   echo "File $CFG_NFSFILE does not exist.";
   exit;
fi


#get reply cache (rc - values: hits, misses, nocache)
$BIN_CAT $CFG_NFSFILE | $BIN_SED -n 1p | $BIN_AWK '{print $2,$3,$4}' | $BIN_TR " " "\n" > $LOG_NEW

#get server file handle (fh - values: lookup, anon, ncachedir, ncachenondir, stale)
$BIN_CAT $CFG_NFSFILE | $BIN_SED -n 2p | $BIN_AWK '{print $2,$3,$4,$5,$6}' | $BIN_TR " " "\n" >> $LOG_NEW

#get io bytes (io - values: read, write)
$BIN_CAT $CFG_NFSFILE | $BIN_SED -n 3p | $BIN_AWK '{print $2,$3}' | $BIN_TR " " "\n" >> $LOG_NEW

#get read ahead cache (ra - values: cache_size, 0-10%, 10-20%, 20-30%, 30-40%, 40-50%, 50-60%, 60-70%, 70-80%, 80-90%, 90-100%, not-found)
$BIN_CAT $CFG_NFSFILE | $BIN_SED -n 5p | $BIN_AWK '{print $3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13}' | $BIN_TR " " "\n" >> $LOG_NEW
$BIN_CAT $CFG_NFSFILE | $BIN_SED -n 5p | $BIN_AWK '{print $2}' > $LOG_FIX

#get server packet stats (net - values: all reads, udp packets, tcp packets, tcp conn)
$BIN_CAT $CFG_NFSFILE | $BIN_SED -n 6p | $BIN_AWK '{print $2,$3,$4,$5}' | $BIN_TR " " "\n" >> $LOG_NEW

#get server rpc operations (rpc - values: calls, badcalls, badfmt, badauth, badclnt)
$BIN_CAT $CFG_NFSFILE | $BIN_SED -n 7p | $BIN_AWK '{print $2,$3,$4,$5,$6}' | $BIN_TR " " "\n" >> $LOG_NEW

#get nfs v3 stats (proc3 - values: null, getattr, setattr, lookup, access, readlink, read, write, create, mkdir, symlink, mknod, remove, rmdir, rename, link, readdir, readdirplus, fsstat, fsinfo, pathconf, commit)
$BIN_CAT $CFG_NFSFILE | $BIN_SED -n 8p | $BIN_AWK '{print $3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24}' | $BIN_TR " " "\n" >> $LOG_NEW

$BIN_PASTE $LOG_FIX
$BIN_PASTE $LOG_NEW $LOG_OLD | while read a b ; do
  echo $(($a-$b))
done

$BIN_RM $LOG_OLD 2>&1
$BIN_MV $LOG_NEW $LOG_OLD 2>&1
