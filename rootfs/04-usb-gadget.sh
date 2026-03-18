# USB gadget (ACM serial + ECM ethernet)
echo "--- Creating USB gadget setup ---"
mkdir -p "$ROOTFS/etc/init.d"

# Stage 1 (boot): ACM serial only — the debug lifeline.
# Detects CAF android_usb vs mainline configfs automatically.
cat > "$ROOTFS/etc/init.d/usb-gadget" << 'GADGET'
#!/sbin/openrc-run

description="USB gadget serial (ACM)"

depend() {
    after devfs
    before networking
}

start() {
    if [ -d /sys/class/android_usb/android0 ]; then
        # CAF 3.18 android_usb driver
        ebegin "Configuring USB gadget (ACM serial) via android_usb"
        A=/sys/class/android_usb/android0
        echo 0 > $A/enable
        echo 1d6b > $A/idVendor
        echo 0104 > $A/idProduct
        echo UdoTech > $A/iManufacturer
        echo BQ268 > $A/iProduct
        echo acm > $A/functions
        echo 1 > $A/enable
        eend $?
    else
        # Mainline configfs
        ebegin "Configuring USB gadget (ACM serial) via configfs"
        G=/sys/kernel/config/usb_gadget/g1

        [ -d /sys/kernel/config ] || mount -t configfs none /sys/kernel/config 2>/dev/null

        # Wait for a UDC controller to appear (up to 5s)
        local udc="" i=0
        while [ $i -lt 50 ] && [ -z "$udc" ]; do
            udc=$(ls /sys/class/udc/ 2>/dev/null | head -1)
            [ -z "$udc" ] && sleep 0.1
            i=$((i + 1))
        done
        if [ -z "$udc" ]; then
            eerror "No UDC found"
            eend 1
            return 1
        fi

        mkdir -p $G
        echo 0x1d6b > $G/idVendor
        echo 0x0104 > $G/idProduct

        mkdir -p $G/strings/0x409
        echo "UdoTech"  > $G/strings/0x409/manufacturer
        echo "BQ268"    > $G/strings/0x409/product
        echo "00000000" > $G/strings/0x409/serialnumber

        mkdir -p $G/configs/c.1/strings/0x409
        echo "Serial" > $G/configs/c.1/strings/0x409/configuration

        # ACM serial only — ECM added later in default runlevel
        mkdir -p $G/functions/acm.usb0
        ln -sf $G/functions/acm.usb0 $G/configs/c.1/ 2>/dev/null

        echo "$udc" > $G/UDC
        eend $?
    fi
}
GADGET
chmod 755 "$ROOTFS/etc/init.d/usb-gadget"

# Stage 2 (default): Add ECM ethernet after boot is stable.
# Skipped on CAF (android_usb handles functions in a single step).
# On mainline, unbinds UDC briefly to add the function.
cat > "$ROOTFS/etc/init.d/usb-gadget-ecm" << 'GADGETECM'
#!/sbin/openrc-run

description="USB gadget ECM ethernet"

depend() {
    need usb-gadget
    after networking
}

start() {
    # CAF android_usb: skip ECM (could add rndis later if needed)
    if [ -d /sys/class/android_usb/android0 ]; then
        ebegin "ECM skipped (android_usb)"
        eend 0
        return 0
    fi

    ebegin "Adding ECM ethernet to USB gadget"
    G=/sys/kernel/config/usb_gadget/g1

    # Read current UDC
    local udc
    udc=$(cat $G/UDC 2>/dev/null)
    [ -z "$udc" ] && { eerror "Gadget not bound"; eend 1; return 1; }

    # Unbind, add ECM, rebind (safe — we're in default runlevel, boot is done)
    echo "" > $G/UDC

    mkdir -p $G/functions/ecm.usb0
    ln -sf $G/functions/ecm.usb0 $G/configs/c.1/ 2>/dev/null

    echo "$udc" > $G/UDC

    # Wait for usb0 network interface, then bring it up via ifupdown
    local i=0
    while [ $i -lt 30 ] && [ ! -d /sys/class/net/usb0 ]; do
        sleep 0.1
        i=$((i + 1))
    done

    if [ -d /sys/class/net/usb0 ]; then
        ifup usb0 2>/dev/null
    fi

    eend $?
}
GADGETECM
chmod 755 "$ROOTFS/etc/init.d/usb-gadget-ecm"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add usb-gadget boot
rc-update add usb-gadget-ecm default
'
