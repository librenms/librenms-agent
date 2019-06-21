<?php

# It can be accessed as a snmpd extension with something like:
#       extend phpopcache /usr/bin/curl --silent http://localhost/opcache.php
# NOTE you should put an htaccess file on it for protection
# need to be surved true the webserver for correct stats / CLI = other stats
# TODO - If some sort of CGI connector to push true CLI for 1 file use....

header('Content-Type: text/plain');
$opcachestat = opcache_get_status ( False );
print $opcachestat['memory_usage']['free_memory']."\n";
print $opcachestat['memory_usage']['used_memory']."\n";
print $opcachestat['memory_usage']['wasted_memory']."\n";
print $opcachestat['interned_strings_usage']['free_memory']."\n";
print $opcachestat['interned_strings_usage']['used_memory']."\n";
print $opcachestat['opcache_statistics']['max_cached_keys']."\n";
print $opcachestat['opcache_statistics']['num_cached_keys']."\n";
print $opcachestat['opcache_statistics']['num_cached_scripts']."\n";
print $opcachestat['opcache_statistics']['hits']."\n";
print $opcachestat['opcache_statistics']['misses']."\n";
print $opcachestat['opcache_statistics']['blacklist_misses'];

