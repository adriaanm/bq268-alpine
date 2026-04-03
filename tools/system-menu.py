#!/usr/bin/python3
"""System menu for BQ268 — main UI on 160×128 fbcon (20×8 chars).

Launched by inittab as respawn on tty0.
Navigation: UP/DOWN, SELECT/RIGHT to activate, BACK/ESC to go back.
"""

import os
import re
import subprocess
import sys
import time
import select
import signal
import tempfile

# -- Display (26 cols × 11 rows, 6×12 font on 160×128 fb) --

COLS = 26
ROWS = 11

def clear():
    sys.stdout.write('\033[H\033[2J')
    sys.stdout.flush()

def draw_lines(lines):
    """Draw up to ROWS lines, truncated to COLS chars."""
    clear()
    for i, line in enumerate(lines[:ROWS]):
        sys.stdout.write(line[:COLS] + '\n')
    sys.stdout.flush()


# -- Status helpers --

def screen_on():
    """Check if the display backlight is on."""
    bl = read_file('/sys/class/leds/lcd-bl/brightness', '0')
    try:
        return int(bl) > 0
    except ValueError:
        return True

def read_file(path, default=''):
    try:
        with open(path) as f:
            return f.read().strip()
    except (OSError, IOError):
        return default

def run(cmd, timeout=3):
    """Run a command, return stdout. Returns '' on failure."""
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True,
                           text=True, timeout=timeout)
        return r.stdout
    except Exception:
        return ''

def battery_info():
    pct = read_file('/sys/class/power_supply/battery/capacity', '?')
    status = read_file('/sys/class/power_supply/battery/status', '')
    ico = {'Charging': '+', 'Full': '=', 'Discharging': '-'}.get(status, '')
    mv = read_file('/sys/class/power_supply/battery/voltage_now')
    mv = f'{int(mv)//1000}mV' if mv else '?'
    return pct, ico, status, mv

def wifi_info():
    out = run("ip -4 addr show wlan0 2>/dev/null")
    m = re.search(r'inet (\S+)/', out)
    ip = m.group(1) if m else ''
    ssid = ''
    iw = run("iw dev wlan0 info 2>/dev/null")
    m = re.search(r'ssid\s+(.+)', iw)
    if m:
        ssid = m.group(1).strip()
    return ip, ssid

_modem_cache = {}
_modem_cache_time = 0

def modem_info(force=False):
    """Get modem status. Cached for 10s unless force=True."""
    global _modem_cache, _modem_cache_time
    if not force and time.time() - _modem_cache_time < 10:
        return _modem_cache

    nas = run("qmicli -d msmipc://0 --nas-get-serving-system 2>&1", timeout=4)
    sig = run("qmicli -d msmipc://0 --nas-get-signal-strength 2>&1", timeout=4)

    registered = "'registered'" in nas

    # Network name
    net = ''
    m = re.search(r"Description: '(.+)'", nas)
    if m and m.group(1):
        net = m.group(1)
    if not net and registered:
        mcc = re.search(r"MCC: '(\d+)'", nas)
        mnc = re.search(r"MNC: '(\d+)'", nas)
        if mcc and mnc:
            net = f"{mcc.group(1)}/{mnc.group(1)}"

    # RAT
    rat = ''
    m = re.search(r"\[0\]: '(\w+)'", nas)
    if m and m.group(1) != 'none':
        rat = m.group(1)

    # Signal — parse "Network 'xxx': 'YYY dBm'" after "Current:"
    dbm = '--'
    m = re.search(r"Current:\s*\n\s*Network '[^']+': '(-?\d+) dBm'", sig)
    if m:
        val = int(m.group(1))
        if val != -128:
            dbm = f'{val}dBm'

    # PPP data
    ppp_ip = ''
    if os.path.exists('/sys/class/net/ppp0'):
        out = run("ip -4 addr show ppp0 2>/dev/null")
        m = re.search(r'inet (\S+)/', out)
        if m:
            ppp_ip = m.group(1)

    _modem_cache = {
        'registered': registered,
        'net': net or '--',
        'rat': rat,
        'dbm': dbm,
        'ip': ppp_ip,
    }
    _modem_cache_time = time.time()
    return _modem_cache


def status_bar():
    """One-line status: battery + wifi + modem. Max 20 chars."""
    pct, ico, _, _ = battery_info()
    wifi_ip, _ = wifi_info()
    mdm = modem_info()

    w = 'W' if wifi_ip else 'w'
    if mdm['ip']:
        m = 'M'
    elif mdm['registered']:
        m = 'm'
    else:
        m = '.'
    sig = mdm['dbm'] if mdm['dbm'] != '--' else ''

    bar = f"{pct}%{ico} {w}{m}"
    if sig:
        bar += f" {sig}"
    return bar


# -- Key input via evtest --

class KeyReader:
    """Reads key events via evtest. Detects chords (e.g. F3+F6).

    Emits synthetic 'CHORD_F3_F6' when both are held simultaneously.
    Regular key presses are emitted on key-down as before.
    """

    # F3 = KEY_F3 (single-dot button), F4 = KEY_F4 (power/double-dot button)
    CHORD_KEYS = {'KEY_F3', 'KEY_F4'}

    def __init__(self):
        self._fifo_path = tempfile.mktemp(prefix='keys-')
        os.mkfifo(self._fifo_path)
        # Open read end non-blocking to avoid deadlock (FIFO blocks until
        # both ends are open; we need to open read before the writer starts)
        fd = os.open(self._fifo_path, os.O_RDONLY | os.O_NONBLOCK)
        self._fifo = os.fdopen(fd, 'r')
        # Emit "KEY press" and "KEY release" for all key events
        cmd = (
            '('
            'for dev in /dev/input/event*; do '
            '[ -e "$dev" ] && evtest "$dev" 2>/dev/null & '
            'done; wait'
            ') | awk \'/EV_KEY/{'
            'match($0, /KEY_[A-Z0-9_]+/);'
            'if (RSTART) {'
            '  k=substr($0, RSTART, RLENGTH);'
            '  if (/value 1/) print k " press";'
            '  else if (/value 0/) print k " release";'
            '  fflush()'
            '}}\''
        )
        self._fifo_wr = open(self._fifo_path, 'w')
        self._proc = subprocess.Popen(
            cmd, shell=True, stdout=self._fifo_wr,
            stderr=subprocess.DEVNULL
        )
        self._held = set()

    def read(self, timeout=None):
        """Read a key name. Returns None on timeout.

        Returns 'CHORD_F3_F6' when both are held, otherwise returns
        the key name on press (ignores releases for non-chord keys).
        """
        while True:
            if timeout is not None:
                r, _, _ = select.select([self._fifo], [], [], timeout)
                if not r:
                    return None
            line = self._fifo.readline().strip()
            if not line:
                return None

            parts = line.split()
            if len(parts) != 2:
                continue
            key, action = parts

            if action == 'press':
                self._held.add(key)
                # Check for chord
                if self.CHORD_KEYS.issubset(self._held):
                    self._held.clear()
                    return 'CHORD_F3_F6'
                # For chord keys, don't emit immediately — wait to see
                # if the other chord key arrives within a short window
                if key in self.CHORD_KEYS:
                    r, _, _ = select.select([self._fifo], [], [], 0.15)
                    if r:
                        continue  # more input available, loop to process it
                    # Timeout — no chord, emit as regular key
                    return key
                return key
            elif action == 'release':
                self._held.discard(key)
            # Releases are silently consumed; loop for next event

    def close(self):
        self._proc.terminate()
        self._proc.wait()
        self._fifo.close()
        self._fifo_wr.close()
        try:
            os.unlink(self._fifo_path)
        except OSError:
            pass


# -- Menus --

_on_dmesg_vt = False

def toggle_dmesg_vt():
    """Switch between VT1 (menu) and VT2 (dmesg). F3+F6 chord."""
    global _on_dmesg_vt
    if _on_dmesg_vt:
        os.system('chvt 1')
        _on_dmesg_vt = False
    else:
        os.system('chvt 2')
        _on_dmesg_vt = True

def menu_loop(keys, items, draw_fn, on_select, on_back=None, refresh_interval=5):
    """Generic menu loop. items = list of labels.
    draw_fn(sel, items) renders the screen.
    on_select(sel) handles selection (return True to exit).
    on_back() handles ESC/BACK (return True to exit)."""
    sel = 0
    n = len(items)
    draw_fn(sel, items)
    while True:
        key = keys.read(timeout=refresh_interval)
        if key is None:
            if screen_on():
                draw_fn(sel, items)
            continue
        if key == 'CHORD_F3_F6':
            toggle_dmesg_vt()
            continue
        if key == 'KEY_UP':
            sel = (sel - 1) % n
        elif key == 'KEY_DOWN':
            sel = (sel + 1) % n
        elif key in ('KEY_RIGHT', 'KEY_ENTER'):
            if on_select(sel):
                return
        elif key in ('KEY_ESC', 'KEY_BACK'):
            if on_back and on_back():
                return
            elif on_back is None:
                pass  # main menu: no back
        draw_fn(sel, items)


# -- Main menu --

def draw_main(sel, items):
    bar = status_bar()
    lines = [bar, '-' * COLS]
    for i, label in enumerate(items):
        prefix = '> ' if i == sel else '  '
        lines.append(f'{prefix}{label}')
    draw_lines(lines)


# -- System Info --

def show_sysinfo(keys):
    pct, ico, status, mv = battery_info()
    wifi_ip, wifi_ssid = wifi_info()
    mdm = modem_info(force=True)

    bst = {'Charging': 'Chrg', 'Discharging': 'Dchg', 'Full': 'Full'}.get(status, 'Idle')
    up = int(read_file('/proc/uptime', '0').split('.')[0])
    mem = run("awk '/MemAvail/{printf \"%dM\",$2/1024}' /proc/meminfo")

    rat = f'({mdm["rat"]})' if mdm['rat'] else ''
    lines = [
        '=== System Info ===',
        f'Bat:{pct}% {bst} {mv}',
        f'WiFi:{wifi_ssid or "--"} {wifi_ip or "--"}',
        f'Net:{mdm["net"]} {rat}',
        f'Sig:{mdm["dbm"]}',
        f'Data:{mdm["ip"] or "off"}',
        f'Up:{up//3600}h{(up%3600)//60}m Mem:{mem}',
        ' BACK to close',
    ]
    draw_lines(lines)
    # Wait for any key, refresh while screen is on
    while True:
        k = keys.read(timeout=5)
        if k == 'CHORD_F3_F6':
            toggle_dmesg_vt()
            continue
        if k:
            break
        if not screen_on():
            continue
        mdm = modem_info(force=True)
        pct, ico, status, mv = battery_info()
        bst = {'Charging': 'Chrg', 'Discharging': 'Dchg', 'Full': 'Full'}.get(status, 'Idle')
        lines[1] = f'Bat:{pct}% {bst} {mv}'
        lines[4] = f'Sig:{mdm["dbm"]}'
        draw_lines(lines)


# -- Network Test --

def show_nettest(keys):
    targets = [
        ('Gateway', None),  # auto-detect
        ('1.1.1.1', '1.1.1.1'),
        ('8.8.8.8', '8.8.8.8'),
    ]

    # Auto-detect gateway
    gw = ''
    out = run("ip route show dev wlan0 2>/dev/null")
    m = re.search(r'default via (\S+)', out)
    if m:
        gw = m.group(1)
    if not gw:
        out = run("ip route show dev ppp0 2>/dev/null")
        m = re.search(r'default via (\S+)', out)
        if m:
            gw = m.group(1)
    targets[0] = ('GW ' + (gw or '?'), gw)

    lines = ['=== Net Test ===', 'Pinging...']
    draw_lines(lines)

    results = []
    for name, addr in targets:
        if not addr:
            results.append(f'{name}: skip')
            continue
        out = run(f'ping -c2 -W3 {addr} 2>&1', timeout=10)
        m = re.search(r'min/avg/max = [\d.]+/([\d.]+)/', out)
        loss_m = re.search(r'(\d+)% packet loss', out)
        if m:
            avg = float(m.group(1))
            results.append(f'{name}: {avg:.0f}ms')
        elif loss_m:
            results.append(f'{name}: {loss_m.group(1)}%loss')
        else:
            results.append(f'{name}: fail')

    # Also test DNS
    out = run('nslookup google.com 2>&1', timeout=5)
    if 'Address' in out and 'NXDOMAIN' not in out:
        results.append('DNS: ok')
    else:
        results.append('DNS: fail')

    lines = ['=== Net Test ==='] + results + ['', ' BACK to close']
    draw_lines(lines)
    keys.read()


# -- Settings --

def show_settings(keys):
    bright = int(read_file('/sys/class/leds/lcd-bl/brightness', '20'))
    timeout_s = 30
    try:
        for line in open('/etc/bq268.conf'):
            if line.startswith('SCREEN_TIMEOUT='):
                timeout_s = int(line.split('=')[1])
            elif line.startswith('BACKLIGHT_BRIGHTNESS='):
                bright = int(line.split('=')[1])
    except (OSError, ValueError):
        pass

    wifi_on = os.path.exists('/sys/class/net/wlan0')
    items = ['Brightness', 'WiFi', 'Timeout', 'Reboot to BL']
    sel = 0
    timeouts = [15, 30, 60, 120, 0]

    def draw_s(s, _items):
        pct, ico, _, _ = battery_info()
        lines = [
            f'{pct}%{ico}  Settings',
            '-' * COLS,
            f'{">" if s==0 else " "} Bright   [{bright:3d}]',
            f'{">" if s==1 else " "} WiFi    [{"ON" if wifi_on else "OFF":>3s}]',
            f'{">" if s==2 else " "} Timeout [{timeout_s:3d}s]',
            f'{">" if s==3 else " "} Reboot\u2192BL',
        ]
        draw_lines(lines)

    def on_sel(s):
        nonlocal bright, wifi_on, timeout_s
        if s == 0:
            bright = min(255, bright + 25)
            write_bright(bright)
        elif s == 1:
            if wifi_on:
                run('killall wpa_supplicant 2>/dev/null; ip link set wlan0 down')
                wifi_on = False
            else:
                run('ip link set wlan0 up; wpa_supplicant -B -i wlan0 '
                    '-c /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null; '
                    'udhcpc -i wlan0 -b -R -q 2>/dev/null &')
                wifi_on = True
        elif s == 2:
            idx = timeouts.index(timeout_s) if timeout_s in timeouts else 0
            timeout_s = timeouts[(idx + 1) % len(timeouts)]
            save_conf('SCREEN_TIMEOUT', timeout_s)
        elif s == 3:
            clear()
            sys.stdout.write('Rebooting to\nbootloader...\n')
            sys.stdout.flush()
            time.sleep(1)
            os.system('/usr/local/bin/reboot-bootloader')
        return False

    def on_back():
        return True

    menu_loop(keys, items, draw_s, on_sel, on_back, refresh_interval=30)


def write_bright(val):
    try:
        with open('/sys/class/leds/lcd-bl/brightness', 'w') as f:
            f.write(str(val))
    except OSError:
        pass
    save_conf('BACKLIGHT_BRIGHTNESS', val)

def save_conf(key, val):
    path = '/etc/bq268.conf'
    lines = []
    found = False
    try:
        with open(path) as f:
            lines = f.readlines()
    except OSError:
        pass
    with open(path, 'w') as f:
        for line in lines:
            if line.startswith(f'{key}='):
                f.write(f'{key}={val}\n')
                found = True
            else:
                f.write(line)
        if not found:
            f.write(f'{key}={val}\n')


# -- Wata launcher --

def launch_wata():
    fbcon = None
    for vtc in os.listdir('/sys/class/vtconsole/'):
        name_path = f'/sys/class/vtconsole/{vtc}/name'
        name = read_file(name_path)
        if 'frame buffer' in name:
            fbcon = f'/sys/class/vtconsole/{vtc}/bind'
            break

    if os.path.isfile('/opt/wata/start.sh') and os.access('/opt/wata/start.sh', os.X_OK):
        if fbcon:
            try:
                with open(fbcon, 'w') as f:
                    f.write('0')
            except OSError:
                pass
        os.system('/opt/wata/start.sh')
        if fbcon:
            try:
                with open(fbcon, 'w') as f:
                    f.write('1')
            except OSError:
                pass
    else:
        lines = ['Wata not installed', '', '/opt/wata/start.sh', 'not found']
        draw_lines(lines)
        time.sleep(2)


# -- Cellular data --

def show_cellular(keys):
    mdm = modem_info(force=True)
    ppp_up = os.path.exists('/sys/class/net/ppp0')

    items = ['Start data', 'Stop data', 'Back'] if not ppp_up else ['Stop data', 'Start data', 'Back']

    def draw_c(sel, _items):
        mdm2 = modem_info()
        lines = [
            '=== Cellular ===',
            f'Net:{mdm2["net"]} {mdm2["rat"]}',
            f'Sig:{mdm2["dbm"]}',
            f'Data:{"ppp0 " + mdm2["ip"] if mdm2["ip"] else "off"}',
            '',
        ]
        for i, label in enumerate(_items):
            lines.append(f'{">" if i==sel else " "} {label}')
        draw_lines(lines)

    def on_sel(s):
        nonlocal ppp_up, items
        label = items[s]
        if label == 'Start data':
            clear()
            sys.stdout.write('Starting PPP...\n')
            sys.stdout.flush()
            os.system('pppd call cellular &')
            time.sleep(15)
            ppp_up = os.path.exists('/sys/class/net/ppp0')
            items = ['Stop data', 'Start data', 'Back'] if ppp_up else ['Start data', 'Stop data', 'Back']
        elif label == 'Stop data':
            os.system('killall pppd 2>/dev/null')
            time.sleep(2)
            ppp_up = False
            items = ['Start data', 'Stop data', 'Back']
        elif label == 'Back':
            return True
        return False

    menu_loop(keys, items, draw_c, on_sel, lambda: True, refresh_interval=5)


# -- Main --

def setup_dmesg_vt():
    """Start a scrollable dmesg viewer on VT2.

    UP/DOWN scroll through the kernel log buffer. New messages from
    dmesg -w are appended and auto-scrolled to bottom.
    """
    viewer = r'''
import os, sys, subprocess, select, tempfile

ROWS, COLS = 11, 26
tty = open("/dev/tty2", "w", buffering=1)
lines = []
scroll_pos = None  # None = follow tail
hscroll = 0        # horizontal scroll offset

def load_dmesg():
    global lines
    r = subprocess.run("dmesg", capture_output=True, text=True)
    lines = r.stdout.splitlines()

def draw():
    tty.write("\033[H\033[2J")
    end = scroll_pos if scroll_pos is not None else len(lines)
    start = max(0, end - ROWS)
    for line in lines[start:end]:
        tty.write(line[hscroll:hscroll+COLS] + "\n")
    tty.flush()

load_dmesg()
draw()

fifo_path = tempfile.mktemp(prefix="dmesg-keys-")
os.mkfifo(fifo_path)
fd = os.open(fifo_path, os.O_RDONLY | os.O_NONBLOCK)
fifo_r = os.fdopen(fd, "r")
fifo_w = open(fifo_path, "w")
cmd = ("(for dev in /dev/input/event*; do [ -e \"$dev\" ] && "
       "evtest \"$dev\" 2>/dev/null & done; wait) | "
       "awk '/EV_KEY.*value 1$/{match($0,/KEY_[A-Z0-9_]+/);"
       "if(RSTART){print substr($0,RSTART,RLENGTH);fflush()}}'")
kproc = subprocess.Popen(cmd, shell=True, stdout=fifo_w,
                         stderr=subprocess.DEVNULL)
dproc = subprocess.Popen(["dmesg", "-w"], stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True)

while True:
    rlist, _, _ = select.select([fifo_r, dproc.stdout], [], [], 2)
    if dproc.stdout in rlist:
        line = dproc.stdout.readline().rstrip()
        if line:
            lines.append(line)
            if scroll_pos is None:
                draw()
    if fifo_r in rlist:
        key = fifo_r.readline().strip()
        if key == "KEY_UP":
            if scroll_pos is None:
                scroll_pos = len(lines)
            scroll_pos = max(ROWS, scroll_pos - 1)
            draw()
        elif key == "KEY_DOWN":
            if scroll_pos is not None:
                scroll_pos += 1
                if scroll_pos >= len(lines):
                    scroll_pos = None
            draw()
        elif key == "KEY_RIGHT":
            hscroll += 10
            draw()
        elif key == "KEY_LEFT":
            hscroll = max(0, hscroll - 10)
            draw()
    if not rlist:
        if scroll_pos is None:
            draw()
'''
    subprocess.Popen(
        ['python3', '-u', '-c', viewer],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

def claim_vt():
    """Ensure VT1 is foreground and clear boot residue."""
    os.system('chvt 1')
    # Force stdout unbuffered so draws appear immediately
    sys.stdout.reconfigure(line_buffering=True)
    sys.stdout.write('\033[H\033[2J')
    sys.stdout.flush()

def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    claim_vt()
    setup_dmesg_vt()

    keys = KeyReader()
    try:
        main_items = ['Wata', 'System Info', 'Net Test', 'Cellular', 'Settings', 'Reboot']

        def on_select(sel):
            if sel == 0:
                launch_wata()
            elif sel == 1:
                show_sysinfo(keys)
            elif sel == 2:
                show_nettest(keys)
            elif sel == 3:
                show_cellular(keys)
            elif sel == 4:
                show_settings(keys)
            elif sel == 5:
                clear()
                sys.stdout.write('Rebooting...\n')
                sys.stdout.flush()
                time.sleep(1)
                os.system('reboot')
            return False

        menu_loop(keys, main_items, draw_main, on_select,
                  refresh_interval=5)
    finally:
        keys.close()

if __name__ == '__main__':
    main()
