# Diagnostic init (boot with init=/sbin/init.debug)
cat > "$ROOTFS/sbin/init.debug" << 'INITDBG'
#!/bin/sh
# Diagnostic init — signals progress via LEDs, prints to console.
# Boot with: init=/sbin/init.debug

G=/sys/class/leds/green/brightness
R=/sys/class/leds/red/brightness

echo "=== init.debug: ALIVE ===" > /dev/console 2>&1
echo 1 > $G 2>/dev/null

mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
echo "=== init.debug: filesystems mounted ===" > /dev/console 2>&1
echo 1 > $R 2>/dev/null

echo "--- /proc/version ---" > /dev/console 2>&1
cat /proc/version > /dev/console 2>&1
echo "--- /proc/cmdline ---" > /dev/console 2>&1
cat /proc/cmdline > /dev/console 2>&1
echo "--- block devices ---" > /dev/console 2>&1
cat /proc/partitions > /dev/console 2>&1

echo "=== init.debug: dropping to shell ===" > /dev/console 2>&1
echo 0 > $R 2>/dev/null
exec /bin/sh < /dev/console > /dev/console 2>&1
INITDBG
chmod 755 "$ROOTFS/sbin/init.debug"
