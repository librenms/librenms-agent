#!/bin/sh

# lm-sensors-pass.sh
# SNMP pass script for LM-SENSORS-MIB thermal sensors
# Provides proper MIB structure at .1.3.6.1.4.1.2021.13.16.2.1

BASE_OID=".1.3.6.1.4.1.2021.13.16.2.1"

# Function to get all thermal zone data
# Output format: index:name:temp
# Re-indexes zones sequentially starting from 1
get_zones() {
    local idx=0
    for zone in /sys/devices/virtual/thermal/thermal_zone*; do
        [ -d "$zone" ] || continue
        idx=$((idx + 1))
        zone_type=$(cat "$zone/type" 2>/dev/null || echo "unknown")
        zone_temp=$(cat "$zone/temp" 2>/dev/null || echo "0")
        echo "$idx:$zone_type:$zone_temp"
    done | sort -t':' -k1 -n
}

case "$1" in
    -g)
        # GET request - return exact OID match
        REQ_OID="$2"
        FOUND=0
        
        while IFS=':' read idx name temp; do
            case "$REQ_OID" in
                "$BASE_OID.1.$idx")
                    echo "$REQ_OID"
                    echo "integer"
                    echo "$idx"
                    FOUND=1
                    break
                    ;;
                "$BASE_OID.2.$idx")
                    echo "$REQ_OID"
                    echo "string"
                    echo "$name"
                    FOUND=1
                    break
                    ;;
                "$BASE_OID.3.$idx")
                    echo "$REQ_OID"
                    echo "gauge"
                    echo "$temp"
                    FOUND=1
                    break
                    ;;
            esac
        done << EOF
$(get_zones)
EOF
        
        [ "$FOUND" -eq 0 ] && echo "NONE"
        ;;
        
    -n)
        # GETNEXT request - return next OID after requested
        REQ_OID="$2"
        
        # Create temporary file with all OIDs
        TMP_FILE="/tmp/snmp_oids.$$"
        > "$TMP_FILE"
        
        get_zones | while IFS=':' read idx name temp; do
            # Pad index to ensure proper numeric sorting
            # Format: column.index where index is zero-padded to 3 digits
            printf "%d.%03d|$BASE_OID.1.$idx|integer|$idx\n" 1 $idx >> "$TMP_FILE"
            printf "%d.%03d|$BASE_OID.2.$idx|string|$name\n" 2 $idx >> "$TMP_FILE"
            printf "%d.%03d|$BASE_OID.3.$idx|gauge|$temp\n" 3 $idx >> "$TMP_FILE"
        done
        
        # Sort by our padded key, then extract and compare OIDs
        sort -t'|' -k1 "$TMP_FILE" | cut -d'|' -f2- | while IFS='|' read oid type value; do
            # Use awk for proper numeric OID comparison
            is_greater=$(awk -v req="$REQ_OID" -v curr="$oid" '
                BEGIN {
                    # Split OIDs into arrays
                    split(req, req_parts, ".");
                    split(curr, curr_parts, ".");
                    
                    # Compare each part numerically
                    for (i = 1; i <= length(curr_parts); i++) {
                        req_val = (i <= length(req_parts)) ? req_parts[i] : 0;
                        curr_val = curr_parts[i];
                        
                        if (curr_val > req_val) {
                            print "1";
                            exit;
                        } else if (curr_val < req_val) {
                            print "0";
                            exit;
                        }
                    }
                    print "0";
                }
            ')
            
            if [ "$is_greater" = "1" ]; then
                echo "$oid"
                echo "$type"
                echo "$value"
                rm -f "$TMP_FILE"
                exit 0
            fi
        done
        
        rm -f "$TMP_FILE"
        echo "NONE"
        ;;
        
    *)
        echo "Usage: $0 -g|-n OID" >&2
        exit 1
        ;;
esac
