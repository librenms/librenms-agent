#!/bin/bash
# Based on https://github.com/Photonicsguy/CHIP
# Enable ADC registers
i2cset -y -f 0 0x34 0x82 0xff

##      REGISTER 00     ##
REG=$(i2cget -y -f 0 0x34 0x00)
STATUS_ACIN=$(($(($REG&0x80))/128))
STATUS_VBUS=$(($(($REG&0x20))/32))
STATUS_CHG_DIR=$(($(($REG&0x04))/4))

REG=$(i2cget -y -f 0 0x34 0x01)
STATUS_CHARGING=$(($(($REG&0x40))/64))
STATUS_BATCON=$(($(($REG&0x20))/32))

BAT_C=0
BAT_D=0

if [ $STATUS_ACIN == 1 ]; then
        # ACIN voltage
        REG=$(i2cget -y -f 0 0x34 0x56 w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}')
        REG=$(printf "%d" "$REG")
        ACIN=$(echo "$REG*0.0017"|bc)
        # ACIN Current
        REG=$(i2cget -y -f 0 0x34 0x58 w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}')
        REG=$(printf "%d" "$REG")
        ACIN_C=$(echo "$REG*0.000625"|bc)
else
        ACIN=0
        ACIN_C=0
fi

if [ $STATUS_VBUS == 1 ]; then
        # VBUS voltage
        REG=$(i2cget -y -f 0 0x34 0x5A w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}')
        REG=$(printf "%d" "$REG")
        VBUS=$(echo "$REG*0.0017"|bc)

        # VBUS Current
        REG=$(i2cget -y -f 0 0x34 0x5C w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}')
        REG=$(printf "%d" "$REG")
        VBUS_C=$(echo "$REG*0.000375"|bc)
else
        VBUS=0
        VBUS_C=0
fi

if [ $STATUS_BATCON  ==  1 ]; then
        # Battery Voltage
        REG=$(i2cget -y -f 0 0x34 0x78 w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}')
        REG=$(printf "%d" "$REG")
        VBAT=$(echo "$REG*0.0011"|bc)

        if [ $STATUS_CHG_DIR  ==  1 ]; then
                # Battery Charging Current
                REG=$(i2cget -y -f 0 0x34 0x7A w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}')
                REG_C=$(printf "%d" "$REG")
                BAT_C=$(echo "scale=2;$REG_C*0.001"|bc)
        else
                # Battery Discharge Current
                REG=$(i2cget -y -f 0 0x34 0x7C w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}')
                REG_D=$(printf "%d" "$REG")
                BAT_D=$(echo "scale=2;$REG_D*0.001"|bc)
        fi
        # Battery %
        REG=$(i2cget -y -f 0 0x34 0xB9)
        BAT_PERCENT=$(printf "%d" "$REG")
else
        VBAT=0
        #BATT_CUR=0
        BAT_PERCENT=0
fi

# Temperature
REG=$(i2cget -y -f 0 0x34 0x5E w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}')
REG=$(printf "%d" "$REG")
THERM=$(echo "($REG*0.1)-144.7"|bc)

echo "$THERM"
echo $ACIN
echo $ACIN_C
echo $VBUS
echo $VBUS_C
echo $VBAT
echo "$(echo "$BAT_C-$BAT_D"|bc)"
echo $BAT_PERCENT
echo $STATUS_CHARGING
