// X47 Widgets — desktop widgets drawn into the shell's background group so
// they sit on the wallpaper, beneath windows (works on Wayland).
//   - Dual digital clock: London + New York
//   - Bitcoin ticker (CoinGecko, refreshed every 60 s)
//   - System vitals: CPU / RAM / load

import GLib from 'gi://GLib';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import Soup from 'gi://Soup';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const ZONES = [
    {id: 'Europe/London', label: 'LONDON'},
    {id: 'America/New_York', label: 'NEW YORK'},
];

const BTC_URL =
    'https://api.coingecko.com/api/v3/simple/price' +
    '?ids=bitcoin&vs_currencies=usd&include_24hr_change=true';

const WIDGET_WIDTH = 340;
const MARGIN_RIGHT = 28;
const MARGIN_TOP = 64;

export default class X47WidgetsExtension extends Extension {
    enable() {
        this._box = new St.BoxLayout({
            style_class: 'x47-widgets',
            orientation: Clutter.Orientation.VERTICAL,
            reactive: false,
            width: WIDGET_WIDTH,
        });

        // --- world clock -----------------------------------------------
        const clockCard = this._makeCard('WORLD CLOCK');
        this._clocks = [];
        for (const zone of ZONES) {
            const row = new St.BoxLayout({
                style_class: 'x47-clock-row',
                orientation: Clutter.Orientation.VERTICAL,
            });
            const zoneLabel = new St.Label({
                text: zone.label,
                style_class: 'x47-clock-zone',
            });
            const timeLabel = new St.Label({
                text: '--:--:--',
                style_class: 'x47-clock-time',
            });
            row.add_child(zoneLabel);
            row.add_child(timeLabel);
            clockCard.add_child(row);
            this._clocks.push({zone, zoneLabel, timeLabel});
        }

        // --- bitcoin ----------------------------------------------------
        const btcCard = this._makeCard('BITCOIN / USD');
        this._btcPrice = new St.Label({text: '. . .', style_class: 'x47-btc-price'});
        this._btcChange = new St.Label({text: '', style_class: 'x47-btc-change'});
        btcCard.add_child(this._btcPrice);
        btcCard.add_child(this._btcChange);

        // --- vitals -----------------------------------------------------
        const vitalsCard = this._makeCard('SYSTEM');
        this._vitalsLabel = new St.Label({text: '', style_class: 'x47-vitals'});
        vitalsCard.add_child(this._vitalsLabel);

        Main.layoutManager._backgroundGroup.add_child(this._box);
        this._position();
        this._monitorsChangedId = Main.layoutManager.connect(
            'monitors-changed', () => this._position());

        this._session = new Soup.Session({timeout: 15});
        this._prevCpu = null;

        this._tickClocks();
        this._tickVitals();
        this._fetchBtc();

        this._clockTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
            this._tickClocks();
            return GLib.SOURCE_CONTINUE;
        });
        this._vitalsTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 3, () => {
            this._tickVitals();
            return GLib.SOURCE_CONTINUE;
        });
        this._btcTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 60, () => {
            this._fetchBtc();
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        for (const id of [this._clockTimer, this._vitalsTimer, this._btcTimer]) {
            if (id)
                GLib.source_remove(id);
        }
        this._clockTimer = this._vitalsTimer = this._btcTimer = null;

        if (this._monitorsChangedId) {
            Main.layoutManager.disconnect(this._monitorsChangedId);
            this._monitorsChangedId = null;
        }
        if (this._session) {
            this._session.abort();
            this._session = null;
        }
        if (this._box) {
            this._box.destroy();
            this._box = null;
        }
        this._clocks = null;
        this._btcPrice = null;
        this._btcChange = null;
        this._vitalsLabel = null;
        this._prevCpu = null;
    }

    _makeCard(title) {
        const card = new St.BoxLayout({
            style_class: 'x47-card',
            orientation: Clutter.Orientation.VERTICAL,
        });
        card.add_child(new St.Label({text: title, style_class: 'x47-card-title'}));
        this._box.add_child(card);
        return card;
    }

    _position() {
        const mon = Main.layoutManager.primaryMonitor;
        if (!mon || !this._box)
            return;
        this._box.set_position(
            mon.x + mon.width - WIDGET_WIDTH - MARGIN_RIGHT,
            mon.y + MARGIN_TOP);
    }

    _tickClocks() {
        for (const c of this._clocks) {
            const tz = GLib.TimeZone.new_identifier(c.zone.id);
            const now = tz ? GLib.DateTime.new_now(tz) : GLib.DateTime.new_now_local();
            c.timeLabel.set_text(now.format('%H:%M:%S'));
            c.zoneLabel.set_text(`${c.zone.label} · ${now.format('%a %d %b')}`);
        }
    }

    _fetchBtc() {
        const msg = Soup.Message.new('GET', BTC_URL);
        this._session.send_and_read_async(
            msg, GLib.PRIORITY_DEFAULT, null, (session, res) => {
                try {
                    const bytes = session.send_and_read_finish(res);
                    const data = JSON.parse(new TextDecoder().decode(bytes.get_data()));
                    const usd = data?.bitcoin?.usd;
                    const chg = data?.bitcoin?.usd_24h_change;
                    if (typeof usd !== 'number')
                        return;
                    this._btcPrice?.set_text(
                        `$${usd.toLocaleString('en-US', {maximumFractionDigits: 0})}`);
                    if (typeof chg === 'number' && this._btcChange) {
                        const up = chg >= 0;
                        this._btcChange.set_text(
                            `${up ? '▲' : '▼'} ${Math.abs(chg).toFixed(2)}%  24h`);
                        this._btcChange.remove_style_class_name(up ? 'x47-down' : 'x47-up');
                        this._btcChange.add_style_class_name(up ? 'x47-up' : 'x47-down');
                    }
                } catch {
                    // Network down or API hiccup — keep the last value.
                }
            });
    }

    _readFile(path) {
        try {
            const [ok, bytes] = GLib.file_get_contents(path);
            return ok ? new TextDecoder().decode(bytes) : null;
        } catch {
            return null;
        }
    }

    _tickVitals() {
        let cpuText = 'CPU --%';
        const stat = this._readFile('/proc/stat');
        if (stat) {
            const f = stat.split('\n')[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + (f[4] || 0);
            const total = f.reduce((a, b) => a + (b || 0), 0);
            if (this._prevCpu) {
                const dTotal = total - this._prevCpu.total;
                const dIdle = idle - this._prevCpu.idle;
                if (dTotal > 0)
                    cpuText = `CPU ${Math.round(100 * (dTotal - dIdle) / dTotal)}%`;
            }
            this._prevCpu = {total, idle};
        }

        let ramText = 'RAM --%';
        const mem = this._readFile('/proc/meminfo');
        if (mem) {
            const totalKb = Number(mem.match(/MemTotal:\s+(\d+)/)?.[1]);
            const availKb = Number(mem.match(/MemAvailable:\s+(\d+)/)?.[1]);
            if (totalKb && availKb >= 0)
                ramText = `RAM ${Math.round(100 * (totalKb - availKb) / totalKb)}%`;
        }

        let loadText = '';
        const load = this._readFile('/proc/loadavg');
        if (load)
            loadText = `  LOAD ${load.split(' ')[0]}`;

        this._vitalsLabel?.set_text(`${cpuText}  ${ramText}${loadText}`);
    }
}
