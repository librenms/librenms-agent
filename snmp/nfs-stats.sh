#!/usr/bin/env bash

# - Copy this script to somewhere (like /opt/nfs-stats.sh)
# - Make it executable (chmod +x /opt/nfs-stats.sh)
# - Add the following line to your snmpd.conf file
#   extend nfs-stats /opt/nfs-stats.sh
# - Restart snmpd
#
# Note: Change the path accordingly, if you're not using "/opt/nfs-stats.sh"

# You need the following tools to be in your PATH env, adjust accordingly
# - awk, cat, mv, paste, rm, sed, tr
PATH=$PATH

CFG_NFSFILE='/proc/net/rpc/nfsd'

LOG_OLD='/tmp/nfsio_old'
LOG_NEW='/tmp/nfsio_new'
LOG_FIX='/tmp/nfsio_fix'

#get reply cache (rc - values: hits, misses, nocache)
cat $CFG_NFSFILE | sed -n 1p | awk '{print $2,$3,$4}' | tr " " "\n" > $LOG_NEW

#get server file handle (fh - values: lookup, anon, ncachedir, ncachenondir, stale)
cat $CFG_NFSFILE | sed -n 2p | awk '{print $2,$3,$4,$5,$6}' | tr " " "\n" >> $LOG_NEW

#get io bytes (io - values: read, write)
cat $CFG_NFSFILE | sed -n 3p | awk '{print $2,$3}' | tr " " "\n" >> $LOG_NEW

#get read ahead cache (ra - values: cache_size, 0-10%, 10-20%, 20-30%, 30-40%, 40-50%, 50-60%, 60-70%, 70-80%, 80-90%, 90-100%, not-found)
cat $CFG_NFSFILE | sed -n 5p | awk '{print $3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13}' | tr " " "\n" >> $LOG_NEW
cat $CFG_NFSFILE | sed -n 5p | awk '{print $2}' > $LOG_FIX

#get server packet stats (net - values: all reads, udp packets, tcp packets, tcp conn)
cat $CFG_NFSFILE | sed -n 6p | awk '{print $2,$3,$4,$5}' | tr " " "\n" >> $LOG_NEW

#get server rpc operations (rpc - values: calls, badcalls, badfmt, badauth, badclnt)
cat $CFG_NFSFILE | sed -n 7p | awk '{print $2,$3,$4,$5,$6}' | tr " " "\n" >> $LOG_NEW

#get nfs v3 stats (proc3 - values: null, getattr, setattr, lookup, access, readlink, read, write, create, mkdir, symlink, mknod, remove, rmdir, rename, link, readdir, readdirplus, fsstat, fsinfo, pathconf, commit)
cat $CFG_NFSFILE | sed -n 8p | awk '{print $3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24}' | tr " " "\n" >> $LOG_NEW

paste $LOG_FIX
paste $LOG_NEW $LOG_OLD | while read a b ; do
  echo $(($a-$b))
done

rm $LOG_OLD 2>&1
mv $LOG_NEW $LOG_OLD 2>&1
