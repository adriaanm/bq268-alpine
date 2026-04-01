# Wata app launcher — starts /opt/wata/start.sh with exclusive framebuffer access
echo "--- Setting up wata app launcher ---"

cat > "$ROOTFS/usr/local/bin/wata-launcher.sh" << 'LAUNCHER'
#!/bin/sh
# Wata app launcher — unbinds fbcon so the app has exclusive /dev/fb0,
# then falls back to a login shell if the app exits.

# Find the fbcon vtconsole bind path
FBCON=""
for vtc in /sys/class/vtconsole/vtcon*; do
    [ -e "$vtc/name" ] || continue
    read name < "$vtc/name" 2>/dev/null
    case "$name" in
        *"frame buffer"*) FBCON="$vtc/bind" ;;
    esac
done

if [ -x /opt/wata/start.sh ]; then
    # Unbind fbcon — app owns /dev/fb0
    [ -n "$FBCON" ] && echo 0 > "$FBCON" 2>/dev/null
    /opt/wata/start.sh
    # App exited — rebind fbcon for shell fallback
    [ -n "$FBCON" ] && echo 1 > "$FBCON" 2>/dev/null
fi

# Fallback: interactive shell on fbcon
exec /sbin/getty -n -l /bin/sh 38400 tty0
LAUNCHER
chmod 755 "$ROOTFS/usr/local/bin/wata-launcher.sh"
