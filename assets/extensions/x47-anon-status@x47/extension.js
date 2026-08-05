// X47 Anon Status — desktop card for the amnesia session showing, at a
// glance: network signal, VPN state (Mullvad / Nym / NetworkManager),
// Tor status incl. bridges, and a one-line security verdict.
//
// Layering matches the CMD Helper: inside window_group just below the lowest
// app window — visible on the desktop, covered by apps, hidden in fullscreen.
// Refreshes every 10 s; click the card to refresh immediately.

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const MARGIN = 32;
const REFRESH_SECONDS = 10;

// One probe, many facts. Prints KEY=VALUE lines; parsed in _onProbe().
const PROBE = `
w=$(nmcli -t -f IN-USE,SIGNAL,SSID dev wifi list 2>/dev/null | awk -F: '$1=="*"{print $2"|"$3; exit}')
e=$(nmcli -t -f TYPE,STATE dev 2>/dev/null | awk -F: '$1=="ethernet"&&$2=="connected"{print 1; exit}')
v=$(nmcli -t -f NAME,TYPE con show --active 2>/dev/null | awk -F: '$2=="vpn"||$2=="wireguard"{print $1; exit}')
m=$(command -v mullvad >/dev/null 2>&1 && mullvad status 2>/dev/null | head -n1)
nd=$(systemctl is-active nym-vpnd 2>/dev/null)
nt=$(ip -brief link 2>/dev/null | awk '{print $1}' | grep -m1 -E '^(nym|tun|wg)')
t=$(systemctl is-active tor 2>/dev/null)
ts=$(ss -ltn 2>/dev/null | grep -c ':9050')
b=0; grep -qsE '^[[:space:]]*UseBridges[[:space:]]+1' /etc/tor/torrc /etc/tor/torrc.d/*.conf 2>/dev/null && b=1
printf 'WIFI=%s\\nETH=%s\\nVPNCON=%s\\nMULLVAD=%s\\nNYMD=%s\\nNYMTUN=%s\\nTOR=%s\\nTORSOCK=%s\\nBRIDGE=%s\\n' \\
  "$w" "$e" "$v" "$m" "$nd" "$nt" "$t" "$ts" "$b"
`;

export default class X47AnonStatusExtension extends Extension {
    enable() {
        this._cancel = new Gio.Cancellable();
        this._hiddenForFullscreen = false;

        this._buildCard();
        this._restack();

        this._restackedId = global.display.connect('restacked', () => this._restack());
        this._monitorsChangedId = Main.layoutManager.connect(
            'monitors-changed', () => this._placeCard());
        try {
            this._fsChangedId = global.display.connect(
                'in-fullscreen-changed', () => this._updateFullscreenVisibility());
        } catch {
            this._fsChangedId = 0;
        }

        this._placeCard();
        this._refresh();
        this._timer = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, REFRESH_SECONDS, () => {
                this._refresh();
                return GLib.SOURCE_CONTINUE;
            });
    }

    disable() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = 0;
        }
        if (this._restackedId) {
            global.display.disconnect(this._restackedId);
            this._restackedId = 0;
        }
        if (this._fsChangedId) {
            global.display.disconnect(this._fsChangedId);
            this._fsChangedId = 0;
        }
        if (this._monitorsChangedId) {
            Main.layoutManager.disconnect(this._monitorsChangedId);
            this._monitorsChangedId = null;
        }
        if (this._cancel) {
            this._cancel.cancel();
            this._cancel = null;
        }
        if (this._card) {
            this._card.get_parent()?.remove_child(this._card);
            this._card.destroy();
            this._card = null;
        }
        this._rows = null;
        this._verdict = null;
    }

    // --- UI ----------------------------------------------------------------

    _buildCard() {
        this._card = new St.BoxLayout({
            style_class: 'x47-anon-card',
            orientation: Clutter.Orientation.VERTICAL,
            reactive: true,
            track_hover: true,
            width: 340,
        });
        global.window_group.add_child(this._card);

        const titleRow = new St.BoxLayout({style_class: 'x47-anon-title-row'});
        titleRow.add_child(new St.Label({text: '●', style_class: 'x47-anon-dot'}));
        titleRow.add_child(new St.Label({
            text: 'ANON STATUS', style_class: 'x47-anon-title', x_expand: true,
        }));
        this._card.add_child(titleRow);

        this._rows = {};
        for (const key of ['NET', 'VPN', 'TOR']) {
            const row = new St.BoxLayout({style_class: 'x47-anon-row'});
            row.add_child(new St.Label({text: key, style_class: 'x47-anon-key'}));
            const val = new St.Label({text: 'checking…', style_class: 'x47-anon-val', x_expand: true});
            val.clutter_text.set_line_wrap(true);
            row.add_child(val);
            this._card.add_child(row);
            this._rows[key] = val;
        }

        this._verdict = new St.Label({
            text: 'REPORT: gathering…',
            style_class: 'x47-anon-verdict',
        });
        this._verdict.clutter_text.set_line_wrap(true);
        this._card.add_child(this._verdict);

        this._card.add_child(new St.Label({
            text: 'click to refresh — updates every 10s',
            style_class: 'x47-anon-hint',
        }));

        this._card.connect('button-press-event', () => {
            this._refresh();
            return Clutter.EVENT_STOP;
        });
    }

    _placeCard() {
        const mon = Main.layoutManager.primaryMonitor;
        if (!mon || !this._card)
            return;
        const workArea = Main.layoutManager.getWorkAreaForMonitor(mon.index);
        this._card.set_position(workArea.x + MARGIN, workArea.y + MARGIN);
    }

    // Same stacking rule as the CMD Helper: under every app window, above
    // wallpaper and desktop icons.
    _restack() {
        const wg = global.window_group;
        if (!this._card || this._card.get_parent() !== wg)
            return;
        const appTypes = new Set([
            Meta.WindowType.NORMAL,
            Meta.WindowType.DIALOG,
            Meta.WindowType.MODAL_DIALOG,
            Meta.WindowType.UTILITY,
            Meta.WindowType.SPLASHSCREEN,
        ]);
        let lowestApp = null;
        for (const child of wg.get_children()) {
            if (child === this._card)
                continue;
            const win = typeof child.meta_window !== 'undefined' ? child.meta_window : null;
            if (win && appTypes.has(win.get_window_type())) {
                lowestApp = child;
                break;
            }
        }
        if (lowestApp)
            wg.set_child_below_sibling(this._card, lowestApp);
        else
            wg.set_child_above_sibling(this._card, null);
        this._updateFullscreenVisibility();
    }

    _updateFullscreenVisibility() {
        if (!this._card)
            return;
        const mon = Main.layoutManager.primaryMonitor;
        let hide = false;
        try {
            hide = !!(mon && global.display.get_monitor_in_fullscreen(mon.index));
        } catch { /* keep visible */ }
        if (hide !== this._hiddenForFullscreen) {
            this._hiddenForFullscreen = hide;
            this._card.visible = !hide;
        }
    }

    // --- data --------------------------------------------------------------

    _refresh() {
        if (!this._card)
            return;
        try {
            const proc = Gio.Subprocess.new(
                ['bash', '-c', PROBE],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
            proc.communicate_utf8_async(null, this._cancel, (p, res) => {
                try {
                    const [, out] = p.communicate_utf8_finish(res);
                    this._onProbe(out || '');
                } catch (e) {
                    if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                        console.warn(`x47-anon-status: probe failed: ${e}`);
                }
            });
        } catch (e) {
            console.warn(`x47-anon-status: probe spawn failed: ${e}`);
        }
    }

    _onProbe(out) {
        if (!this._card)
            return;
        const kv = {};
        for (const line of out.split('\n')) {
            const i = line.indexOf('=');
            if (i > 0)
                kv[line.slice(0, i)] = line.slice(i + 1);
        }

        // NET
        let net = 'OFFLINE';
        let online = false;
        if (kv.WIFI) {
            const [sig, ssid] = kv.WIFI.split('|');
            const n = parseInt(sig, 10) || 0;
            const bars = n > 75 ? '▂▄▆█' : n > 50 ? '▂▄▆_' : n > 25 ? '▂▄__' : '▂___';
            net = `${bars} ${n}%${ssid ? ` — ${ssid}` : ''}`;
            online = true;
        } else if (kv.ETH === '1') {
            net = 'wired connection';
            online = true;
        }

        // VPN
        let vpn = 'none';
        let vpnUp = false;
        const mull = (kv.MULLVAD || '').trim();
        const nymUp = kv.NYMD === 'active' && !!kv.NYMTUN;
        if (mull.toLowerCase().includes('connected') && !mull.toLowerCase().includes('disconnected')) {
            vpn = mull;
            vpnUp = true;
        } else if (nymUp) {
            vpn = 'Nym — mixnet tunnel up';
            vpnUp = true;
        } else if (kv.VPNCON) {
            vpn = `${kv.VPNCON} (active)`;
            vpnUp = true;
        }

        // TOR
        const torActive = kv.TOR === 'active';
        const torSock = parseInt(kv.TORSOCK || '0', 10) > 0;
        const bridge = kv.BRIDGE === '1';
        let tor;
        if (!torActive)
            tor = 'Tor Status: Stopped';
        else if (!torSock)
            tor = 'Tor Status: Starting…';
        else
            tor = bridge ? 'Tor Status: Connected w Bridge' : 'Tor Status: Connected';

        this._rows.NET.set_text(net);
        this._rows.VPN.set_text(vpn);
        this._rows.TOR.set_text(tor);

        // Verdict
        const torUp = torActive && torSock;
        let verdict, cls;
        if (!online) {
            verdict = 'REPORT: offline — nothing is leaking';
            cls = 'x47-anon-warn';
        } else if (vpnUp && torUp && bridge) {
            verdict = 'REPORT: SECURE — VPN + Tor bridge active';
            cls = 'x47-anon-good';
        } else if (vpnUp && torUp) {
            verdict = 'REPORT: SECURE — VPN + Tor active (no bridge)';
            cls = 'x47-anon-good';
        } else if (vpnUp) {
            verdict = 'REPORT: OK — VPN up, Tor not running';
            cls = 'x47-anon-warn';
        } else if (torUp) {
            verdict = 'REPORT: OK — Tor up, no VPN layer';
            cls = 'x47-anon-warn';
        } else {
            verdict = 'REPORT: EXPOSED — direct connection, no VPN/Tor';
            cls = 'x47-anon-bad';
        }
        this._verdict.set_text(verdict);
        this._verdict.set_style_class_name(`x47-anon-verdict ${cls}`);
    }
}
