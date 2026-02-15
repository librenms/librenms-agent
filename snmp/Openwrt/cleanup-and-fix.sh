#!/bin/sh

# cleanup-and-fix.sh
# Run this on the OpenWrt device to:
# 1. Remove old broken exec entries
# 2. Verify pass script is working

echo "Step 1: Removing old exec entries for lmSensors..."

# Remove exec entries with miboid containing 2021.13.16
uci show snmpd | grep "exec.*=exec" | cut -d'.' -f2 | cut -d'=' -f1 | while read idx; do
    miboid=$(uci get snmpd.$idx.miboid 2>/dev/null)
    if echo "$miboid" | grep -q "2021\.13\.16"; then
        echo "  Removing snmpd.$idx (miboid: $miboid)"
        uci delete snmpd.$idx
    fi
done

uci commit snmpd

echo ""
echo "Step 2: Verifying pass configuration..."
uci show snmpd | grep "pass.*lm-sensors"

echo ""
echo "Step 3: Restarting snmpd..."
/etc/init.d/snmpd restart

echo ""
echo "Done! Now test with:"
echo "  snmpwalk -v2c -c public localhost LM-SENSORS-MIB::lmTempSensorsValue"
