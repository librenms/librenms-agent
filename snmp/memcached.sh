#!/bin/bash

declare -A stats

exec 200<>/dev/tcp/localhost/11211
echo "stats" >&200
echo "quit" >&200

while read -r pre var val ; do 
	if [ "$pre" = "END" ] ; then
        break
    elif [ "$pre" = "STAT" ] ; then
		val="${val/$'\r'/}"
		if [ "$var" = "rusage_system" ] || [ "$var" = "rusage_user" ] ; then
			val=$(bc -l <<< "scale=0 ; ($val * 1000)/1")
			var+="_microseconds"
		fi
		stats["$var"]=$val
	fi
done <&200

exec 200>&-

cat <<EOD
{
    "data": {
        "localhost:11211": {
EOD

for var in "${!stats[@]}" ; do
	val=${stats["$var"]}
	if [ "$val" -eq "$val" ] 2>/dev/null ; then
		#echo -nE "s:${#var}:\"$var\";i:$val;"
		echo "\"$var\": $val,"
	else
		#echo -nE "s:${#var}:\"$var\";s:${#val}:\"$val\";"
		echo "\"$var\": \"$val\","
	fi
done
echo '"dummy":"value"'

cat <<EOD
        }
    },
    "error": 0,
    "errorString": "SUCCESS",
    "version": "1.1"
}
EOD
