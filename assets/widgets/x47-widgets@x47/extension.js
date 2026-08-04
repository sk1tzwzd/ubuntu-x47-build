// X47 Widgets — draggable desktop widgets (chrome layer so they receive
// clicks/drags on Wayland).
//   - World clock: London + New York
//   - Bitcoin ticker (CoinGecko, 60 s)
//   - System vitals: CPU / RAM sparklines + load
//   - Cybersecurity Reddit feed (click a title to open it)
//
// Drag from the card title. Positions persist to
// $XDG_CONFIG_HOME/x47-widgets/layout.json.

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
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

const SUBREDDITS = 'netsec+cybersecurity+hacking+AskNetsec+Malware+bugbounty';
// Reddit blocks the .json API for non-OAuth clients (403); Atom RSS works.
const REDDIT_URL = `https://www.reddit.com/r/${SUBREDDITS}/.rss?limit=12`;
const BROWSER_UA =
    'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0';

const HISTORY = 60;
const MARGIN = 28;
const CARD_GAP = 14;
const CARD_WIDTH = 320;
const REDDIT_POSTS = 4;
const TEAL = [64 / 255, 224 / 255, 208 / 255];
const DRAG_THRESHOLD = 4;

export default class X47WidgetsExtension extends Extension {
    enable() {
        this._cards = {};
        this._dragMonId = 0;
        this._drag = null;
        this._layout = this._loadLayout();
        this._session = new Soup.Session({timeout: 15, user_agent: BROWSER_UA});
        this._prevCpu = null;
        this._cpuHist = [];
        this._ramHist = [];

        this._buildClock();
        this._buildBtc();
        this._buildVitals();
        this._buildReddit();

        // Place after first allocate so heights are real (avoids Reddit cut-off).
        this._placeIdle = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._placeCards();
            this._placeIdle = 0;
            return GLib.SOURCE_REMOVE;
        });
        this._monitorsChangedId = Main.layoutManager.connect(
            'monitors-changed', () => this._placeCards());

        this._tickClocks();
        this._tickVitals();
        this._fetchBtc();
        this._fetchReddit();

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
        this._redditTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 600, () => {
            this._fetchReddit();
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        for (const id of [this._clockTimer, this._vitalsTimer, this._btcTimer,
            this._redditTimer, this._placeIdle]) {
            if (id)
                GLib.source_remove(id);
        }
        this._clockTimer = this._vitalsTimer = this._btcTimer = this._redditTimer = null;
        this._placeIdle = 0;

        if (this._dragMonId) {
            global.stage.disconnect(this._dragMonId);
            this._dragMonId = 0;
        }
        this._drag = null;

        if (this._monitorsChangedId) {
            Main.layoutManager.disconnect(this._monitorsChangedId);
            this._monitorsChangedId = null;
        }
        if (this._session) {
            this._session.abort();
            this._session = null;
        }
        for (const id in this._cards) {
            const card = this._cards[id];
            Main.layoutManager.removeChrome(card);
            card.destroy();
        }
        this._cards = null;

        this._clocks = null;
        this._btcPrice = null;
        this._btcChange = null;
        this._cpuValue = this._ramValue = this._loadLabel = null;
        this._cpuArea = this._ramArea = null;
        this._redditBox = null;
        this._prevCpu = null;
        this._cpuHist = this._ramHist = null;
    }

    // --- card scaffolding ---------------------------------------------------

    _makeCard(id) {
        const card = new St.BoxLayout({
            style_class: 'x47-card',
            orientation: Clutter.Orientation.VERTICAL,
            reactive: true,
            track_hover: true,
            width: CARD_WIDTH,
        });
        // Chrome (not backgroundGroup): receives pointer events so drag/clicks work.
        Main.layoutManager.addChrome(card, {
            affectsStruts: false,
            trackFullscreen: true,
        });
        this._cards[id] = card;
        return card;
    }

    _title(card, id, text) {
        // Drag handle = title only, so Reddit rows keep their clicks.
        const title = new St.Label({
            text,
            style_class: 'x47-card-title',
            reactive: true,
            track_hover: true,
        });
        this._attachDrag(title, card, id);
        card.add_child(title);
        return title;
    }

    _buildClock() {
        const card = this._makeCard('clock');
        this._title(card, 'clock', 'WORLD CLOCK');
        this._clocks = [];
        for (const zone of ZONES) {
            const row = new St.BoxLayout({
                style_class: 'x47-clock-row',
                orientation: Clutter.Orientation.VERTICAL,
            });
            const zoneLabel = new St.Label({text: zone.label, style_class: 'x47-clock-zone'});
            const timeLabel = new St.Label({text: '--:--:--', style_class: 'x47-clock-time'});
            row.add_child(zoneLabel);
            row.add_child(timeLabel);
            card.add_child(row);
            this._clocks.push({zone, zoneLabel, timeLabel});
        }
    }

    _buildBtc() {
        const card = this._makeCard('btc');
        this._title(card, 'btc', 'BITCOIN / USD');
        this._btcPrice = new St.Label({text: '. . .', style_class: 'x47-btc-price'});
        this._btcChange = new St.Label({text: '', style_class: 'x47-btc-change'});
        card.add_child(this._btcPrice);
        card.add_child(this._btcChange);
    }

    _buildVitals() {
        const card = this._makeCard('vitals');
        this._title(card, 'vitals', 'SYSTEM');
        this._cpuValue = new St.Label({text: 'CPU --%', style_class: 'x47-metric-value'});
        this._cpuArea = this._makeSparkline(() => this._cpuHist);
        card.add_child(this._metricRow(this._cpuValue));
        card.add_child(this._cpuArea);
        this._ramValue = new St.Label({text: 'RAM --%', style_class: 'x47-metric-value'});
        this._ramArea = this._makeSparkline(() => this._ramHist);
        card.add_child(this._metricRow(this._ramValue));
        card.add_child(this._ramArea);
        this._loadLabel = new St.Label({text: 'LOAD --', style_class: 'x47-load'});
        card.add_child(this._loadLabel);
    }

    _metricRow(valueLabel) {
        const row = new St.BoxLayout({style_class: 'x47-metric-row'});
        row.add_child(valueLabel);
        return row;
    }

    _makeSparkline(getData) {
        const area = new St.DrawingArea({style_class: 'x47-metric-graph'});
        area.connect('repaint', () => this._drawSparkline(area, getData()));
        return area;
    }

    _drawSparkline(area, data) {
        const cr = area.get_context();
        const [w, h] = area.get_surface_size();

        cr.setSourceRGBA(TEAL[0], TEAL[1], TEAL[2], 0.10);
        cr.setLineWidth(1);
        cr.moveTo(0, h - 0.5);
        cr.lineTo(w, h - 0.5);
        cr.stroke();

        if (!data || data.length < 2) {
            cr.$dispose();
            return;
        }

        const n = data.length;
        const dx = w / (HISTORY - 1);
        const x0 = w - (n - 1) * dx;
        const yOf = v => h - (Math.max(0, Math.min(100, v)) / 100) * (h - 2) - 1;

        cr.moveTo(x0, h);
        for (let i = 0; i < n; i++)
            cr.lineTo(x0 + i * dx, yOf(data[i]));
        cr.lineTo(x0 + (n - 1) * dx, h);
        cr.closePath();
        cr.setSourceRGBA(TEAL[0], TEAL[1], TEAL[2], 0.14);
        cr.fill();

        cr.setLineWidth(2);
        cr.setSourceRGBA(TEAL[0], TEAL[1], TEAL[2], 0.9);
        cr.moveTo(x0, yOf(data[0]));
        for (let i = 1; i < n; i++)
            cr.lineTo(x0 + i * dx, yOf(data[i]));
        cr.stroke();
        cr.$dispose();
    }

    _buildReddit() {
        const card = this._makeCard('reddit');
        this._title(card, 'reddit', 'CYBERSEC · REDDIT');
        this._redditBox = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL});
        card.add_child(this._redditBox);
        this._redditStatus = new St.Label({text: 'loading…', style_class: 'x47-reddit-status'});
        this._redditBox.add_child(this._redditStatus);
    }

    // --- drag + layout ------------------------------------------------------

    _attachDrag(handle, card, id) {
        handle.connect('button-press-event', (_actor, event) => {
            if (event.get_button() !== 1)
                return Clutter.EVENT_PROPAGATE;
            const [px, py] = event.get_coords();
            this._drag = {
                card,
                id,
                startX: px,
                startY: py,
                dx: px - card.x,
                dy: py - card.y,
                moved: false,
            };
            if (!this._dragMonId) {
                this._dragMonId = global.stage.connect(
                    'captured-event', (_s, ev) => this._onDragEvent(ev));
            }
            return Clutter.EVENT_STOP;
        });
    }

    _onDragEvent(ev) {
        if (!this._drag)
            return Clutter.EVENT_PROPAGATE;
        const t = ev.type();
        if (t === Clutter.EventType.MOTION) {
            const [px, py] = ev.get_coords();
            if (!this._drag.moved) {
                const adx = Math.abs(px - this._drag.startX);
                const ady = Math.abs(py - this._drag.startY);
                if (adx < DRAG_THRESHOLD && ady < DRAG_THRESHOLD)
                    return Clutter.EVENT_STOP;
                this._drag.moved = true;
            }
            const mon = Main.layoutManager.primaryMonitor;
            let x = Math.round(px - this._drag.dx);
            let y = Math.round(py - this._drag.dy);
            if (mon) {
                const w = this._drag.card.width || CARD_WIDTH;
                const h = this._drag.card.height || 80;
                x = Math.max(mon.x, Math.min(x, mon.x + mon.width - w));
                y = Math.max(mon.y, Math.min(y, mon.y + mon.height - h));
            }
            this._drag.card.set_position(x, y);
            return Clutter.EVENT_STOP;
        }
        if (t === Clutter.EventType.BUTTON_RELEASE) {
            const {card, id, moved} = this._drag;
            if (moved) {
                this._layout[id] = {x: card.x, y: card.y};
                this._saveLayout();
            }
            this._drag = null;
            if (this._dragMonId) {
                global.stage.disconnect(this._dragMonId);
                this._dragMonId = 0;
            }
            return Clutter.EVENT_STOP;
        }
        return Clutter.EVENT_PROPAGATE;
    }

    _clamp(card, x, y) {
        const mon = Main.layoutManager.primaryMonitor;
        if (!mon)
            return [x, y];
        const w = Math.max(card.width || CARD_WIDTH, 1);
        const h = Math.max(card.height || 80, 1);
        const cx = Math.max(mon.x + MARGIN, Math.min(x, mon.x + mon.width - w - MARGIN));
        const cy = Math.max(mon.y + MARGIN, Math.min(y, mon.y + mon.height - h - MARGIN));
        return [cx, cy];
    }

    _placeCards() {
        const mon = Main.layoutManager.primaryMonitor;
        if (!mon || !this._cards)
            return;

        // Default layout: clock/btc/vitals stacked on the right; Reddit on the
        // left so the tall feed is never clipped off the bottom.
        const rightStack = ['clock', 'btc', 'vitals'];
        let y = mon.y + MARGIN + 36;
        for (const id of rightStack) {
            const card = this._cards[id];
            if (!card)
                continue;
            const saved = this._layout[id];
            const w = card.width || CARD_WIDTH;
            const h = Math.max(card.height || 100, 80);
            let x, cy;
            if (saved) {
                [x, cy] = this._clamp(card, saved.x, saved.y);
            } else {
                x = mon.x + mon.width - w - MARGIN;
                cy = y;
                y += h + CARD_GAP;
            }
            card.set_position(x, cy);
        }

        const reddit = this._cards.reddit;
        if (reddit) {
            const saved = this._layout.reddit;
            let x, cy;
            if (saved) {
                [x, cy] = this._clamp(reddit, saved.x, saved.y);
            } else {
                x = mon.x + MARGIN;
                cy = mon.y + MARGIN + 36;
                [x, cy] = this._clamp(reddit, x, cy);
            }
            reddit.set_position(x, cy);
        }
    }

    _layoutFile() {
        return GLib.build_filenamev(
            [GLib.get_user_config_dir(), 'x47-widgets', 'layout.json']);
    }

    _loadLayout() {
        try {
            const [ok, bytes] = GLib.file_get_contents(this._layoutFile());
            if (ok)
                return JSON.parse(new TextDecoder().decode(bytes)) || {};
        } catch {
            // no saved layout yet
        }
        return {};
    }

    _saveLayout() {
        try {
            const dir = GLib.build_filenamev(
                [GLib.get_user_config_dir(), 'x47-widgets']);
            GLib.mkdir_with_parents(dir, 0o755);
            GLib.file_set_contents(
                this._layoutFile(), JSON.stringify(this._layout));
        } catch (e) {
            logError(e, 'x47-widgets: could not save layout');
        }
    }

    // --- data ---------------------------------------------------------------

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
                    if (msg.get_status() !== Soup.Status.OK) {
                        this._btcPrice?.set_text('unavailable');
                        this._btcChange?.set_text(`HTTP ${msg.get_status()}`);
                        return;
                    }
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
                } catch (e) {
                    logError(e, 'x47-widgets: BTC fetch failed');
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

    _push(hist, v) {
        hist.push(v);
        while (hist.length > HISTORY)
            hist.shift();
    }

    _tickVitals() {
        const stat = this._readFile('/proc/stat');
        if (stat) {
            const f = stat.split('\n')[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + (f[4] || 0);
            const total = f.reduce((a, b) => a + (b || 0), 0);
            if (this._prevCpu) {
                const dTotal = total - this._prevCpu.total;
                const dIdle = idle - this._prevCpu.idle;
                if (dTotal > 0) {
                    const pct = Math.round(100 * (dTotal - dIdle) / dTotal);
                    this._cpuValue?.set_text(`CPU ${pct}%`);
                    this._push(this._cpuHist, pct);
                    this._cpuArea?.queue_repaint();
                }
            }
            this._prevCpu = {total, idle};
        }

        const mem = this._readFile('/proc/meminfo');
        if (mem) {
            const totalKb = Number(mem.match(/MemTotal:\s+(\d+)/)?.[1]);
            const availKb = Number(mem.match(/MemAvailable:\s+(\d+)/)?.[1]);
            if (totalKb && availKb >= 0) {
                const pct = Math.round(100 * (totalKb - availKb) / totalKb);
                this._ramValue?.set_text(`RAM ${pct}%`);
                this._push(this._ramHist, pct);
                this._ramArea?.queue_repaint();
            }
        }

        const load = this._readFile('/proc/loadavg');
        if (load)
            this._loadLabel?.set_text(`LOAD ${load.split(' ').slice(0, 3).join('  ')}`);
    }

    _fetchReddit() {
        const msg = Soup.Message.new('GET', REDDIT_URL);
        this._session.send_and_read_async(
            msg, GLib.PRIORITY_DEFAULT, null, (session, res) => {
                try {
                    const bytes = session.send_and_read_finish(res);
                    if (msg.get_status() !== Soup.Status.OK) {
                        this._redditStatus?.set_text(`reddit: HTTP ${msg.get_status()}`);
                        return;
                    }
                    const xml = new TextDecoder().decode(bytes.get_data());
                    const posts = this._parseAtom(xml).slice(0, REDDIT_POSTS);
                    if (posts.length)
                        this._renderReddit(posts);
                    else
                        this._redditStatus?.set_text('no posts');
                } catch (e) {
                    logError(e, 'x47-widgets: Reddit fetch failed');
                }
            });
    }

    _decodeEntities(s) {
        return s
            .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
            .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
            .replace(/&#x27;/g, "'").replace(/&apos;/g, "'")
            .replace(/&#(\d+);/g, (_, d) => String.fromCharCode(Number(d)))
            .replace(/&amp;/g, '&');
    }

    _parseAtom(xml) {
        const out = [];
        const entries = xml.split('<entry>').slice(1);
        for (const e of entries) {
            const title = e.match(/<title>([\s\S]*?)<\/title>/)?.[1];
            const href = e.match(/<link[^>]*href="([^"]+)"/)?.[1];
            const sub = e.match(/<category[^>]*term="([^"]+)"/)?.[1];
            if (title && href) {
                out.push({
                    title: this._decodeEntities(title.trim()),
                    url: href,
                    sub: sub || 'reddit',
                });
            }
        }
        return out;
    }

    _renderReddit(posts) {
        this._redditBox.destroy_all_children();
        this._redditStatus = null;
        for (const p of posts) {
            const item = new St.Button({
                style_class: 'x47-reddit-item',
                reactive: true,
                can_focus: true,
                track_hover: true,
                x_expand: true,
            });
            const box = new St.BoxLayout({
                orientation: Clutter.Orientation.VERTICAL,
                x_expand: true,
            });
            const title = p.title.length > 68 ? `${p.title.slice(0, 66)}…` : p.title;
            box.add_child(new St.Label({
                text: title,
                style_class: 'x47-reddit-title',
                x_expand: true,
            }));
            box.add_child(new St.Label({
                text: `r/${p.sub}`,
                style_class: 'x47-reddit-sub',
            }));
            item.set_child(box);
            item.connect('clicked', () => {
                try {
                    Gio.AppInfo.launch_default_for_uri(p.url, null);
                } catch (e) {
                    logError(e, 'x47-widgets: open reddit post failed');
                }
            });
            this._redditBox.add_child(item);
        }
        // Re-clamp after content height changes so the card isn't cut off.
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._placeCards();
            return GLib.SOURCE_REMOVE;
        });
    }
}
