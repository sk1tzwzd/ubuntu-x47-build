// X47 Widgets — desktop cards below window_group (never over apps),
// snap-to-grid, hide in fullscreen, title-bar drag.
//   - World clock, BTC, vitals sparklines, Reddit feed
//   - PKG helper: update cheat sheet + search → install/upgrade commands

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
const REDDIT_URL = `https://www.reddit.com/r/${SUBREDDITS}/.rss?limit=12`;
const BROWSER_UA =
    'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0';

const HISTORY = 60;
const MARGIN = 32;
const CARD_GAP = 16;
const CARD_WIDTH = 320;
const CELL = 16;
const REDDIT_POSTS = 4;
const DRAG_THRESHOLD = 4;
const TEAL = [64 / 255, 224 / 255, 208 / 255];

const UPDATE_CHEAT = [
    {label: 'Update all apt', cmd: 'sudo apt update && sudo apt upgrade'},
    {label: 'Update all snaps', cmd: 'sudo snap refresh'},
    {label: 'Update Cursor', cmd: 'update-cursor'},
];

export default class X47WidgetsExtension extends Extension {
    enable() {
        this._cards = {};
        this._dragMonId = 0;
        this._drag = null;
        this._winSignals = [];
        this._layout = this._loadLayout();
        this._session = new Soup.Session({timeout: 15, user_agent: BROWSER_UA});
        this._prevCpu = null;
        this._cpuHist = [];
        this._ramHist = [];
        this._hiddenForFullscreen = false;

        this._buildClock();
        this._buildBtc();
        this._buildVitals();
        this._buildReddit();
        this._buildPkg();

        this._placeIdle = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._placeCards();
            this._placeIdle = 0;
            return GLib.SOURCE_REMOVE;
        });
        this._monitorsChangedId = Main.layoutManager.connect(
            'monitors-changed', () => this._placeCards());
        this._setupFullscreenWatch();

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
        this._teardownFullscreenWatch();

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
            const parent = card.get_parent();
            if (parent)
                parent.remove_child(card);
            card.destroy();
        }
        this._cards = null;
        this._clocks = null;
        this._btcPrice = this._btcChange = null;
        this._cpuValue = this._ramValue = this._loadLabel = null;
        this._cpuArea = this._ramArea = null;
        this._redditBox = null;
        this._pkgResults = null;
        this._pkgStatus = null;
        this._pkgEntry = null;
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
        // Below window_group: apps cover widgets; empty desktop still clickable.
        Main.layoutManager.uiGroup.insert_child_below(card, global.window_group);
        this._cards[id] = card;
        return card;
    }

    _title(card, id, text) {
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

    _buildPkg() {
        const card = this._makeCard('pkg');
        this._title(card, 'pkg', 'INSTALL / UPDATE');

        const cheat = new St.BoxLayout({
            orientation: Clutter.Orientation.VERTICAL,
            style_class: 'x47-pkg-cheat',
        });
        for (const row of UPDATE_CHEAT) {
            const btn = new St.Button({
                style_class: 'x47-pkg-cmd',
                reactive: true,
                can_focus: true,
                track_hover: true,
                x_expand: true,
            });
            const box = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true});
            box.add_child(new St.Label({text: row.label, style_class: 'x47-pkg-label'}));
            box.add_child(new St.Label({text: row.cmd, style_class: 'x47-pkg-cmdtext'}));
            btn.set_child(box);
            btn.connect('clicked', () => this._copyCmd(row.cmd));
            cheat.add_child(btn);
        }
        card.add_child(cheat);

        const searchRow = new St.BoxLayout({style_class: 'x47-pkg-search-row'});
        this._pkgEntry = new St.Entry({
            style_class: 'x47-pkg-entry',
            hint_text: 'search app (e.g. notepad++)',
            can_focus: true,
            x_expand: true,
        });
        this._pkgEntry.clutter_text.connect('activate', () => this._runPkgSearch());
        const go = new St.Button({
            label: 'GO',
            style_class: 'x47-pkg-go',
            reactive: true,
            can_focus: true,
        });
        go.connect('clicked', () => this._runPkgSearch());
        searchRow.add_child(this._pkgEntry);
        searchRow.add_child(go);
        card.add_child(searchRow);

        this._pkgStatus = new St.Label({text: 'click a command to copy', style_class: 'x47-pkg-status'});
        card.add_child(this._pkgStatus);
        this._pkgResults = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL});
        card.add_child(this._pkgResults);
    }

    _copyCmd(cmd) {
        const clip = St.Clipboard.get_default();
        clip.set_text(St.ClipboardType.CLIPBOARD, cmd);
        if (this._pkgStatus)
            this._pkgStatus.set_text('copied — paste in a terminal');
        GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 3, () => {
            if (this._pkgStatus)
                this._pkgStatus.set_text('click a command to copy');
            return GLib.SOURCE_REMOVE;
        });
    }

    _runCmd(argv) {
        return new Promise((resolve, reject) => {
            try {
                const proc = Gio.Subprocess.new(
                    argv,
                    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
                proc.communicate_utf8_async(null, null, (p, res) => {
                    try {
                        const [, stdout] = p.communicate_utf8_finish(res);
                        resolve(stdout || '');
                    } catch (e) {
                        reject(e);
                    }
                });
            } catch (e) {
                reject(e);
            }
        });
    }

    async _runPkgSearch() {
        const q = (this._pkgEntry?.get_text() || '').trim();
        this._pkgResults.destroy_all_children();
        if (!q) {
            this._pkgStatus?.set_text('type a name, then Enter / GO');
            return;
        }
        this._pkgStatus?.set_text('searching…');
        const results = [];
        try {
            const aptOut = await this._runCmd([
                'apt-cache', 'search', '--names-only', q.replace(/[^a-zA-Z0-9+._-]/g, ' '),
            ]);
            const aptLines = aptOut.split('\n').filter(l => l.includes(' - ')).slice(0, 4);
            for (const line of aptLines) {
                const pkg = line.split(' - ')[0].trim();
                if (!pkg)
                    continue;
                let installed = false;
                try {
                    const st = await this._runCmd(['dpkg-query', '-W', '-f=${Status}', pkg]);
                    installed = st.includes('install ok installed');
                } catch {
                    installed = false;
                }
                results.push({
                    label: installed ? `apt · upgrade ${pkg}` : `apt · install ${pkg}`,
                    cmd: installed
                        ? `sudo apt install --only-upgrade ${pkg}`
                        : `sudo apt install ${pkg}`,
                });
            }
        } catch {
            // apt-cache missing / failed
        }

        if (GLib.find_program_in_path('snap')) {
            try {
                const snapOut = await this._runCmd(['snap', 'find', q]);
                const lines = snapOut.split('\n').slice(1).filter(l => l.trim());
                for (const line of lines.slice(0, 2)) {
                    const name = line.trim().split(/\s+/)[0];
                    if (!name || name === 'Name')
                        continue;
                    let installed = false;
                    try {
                        await this._runCmd(['snap', 'list', name]);
                        installed = true;
                    } catch {
                        installed = false;
                    }
                    results.push({
                        label: installed ? `snap · refresh ${name}` : `snap · install ${name}`,
                        cmd: installed
                            ? `sudo snap refresh ${name}`
                            : `sudo snap install ${name}`,
                    });
                }
            } catch {
                // snap find failed / no matches
            }
        }

        const uniq = [];
        const seen = new Set();
        for (const r of results) {
            if (seen.has(r.cmd))
                continue;
            seen.add(r.cmd);
            uniq.push(r);
            if (uniq.length >= 3)
                break;
        }

        if (!uniq.length) {
            this._pkgStatus?.set_text('no match — try another name');
            return;
        }
        this._pkgStatus?.set_text(`${uniq.length} match(es) — click to copy`);
        for (const r of uniq) {
            const btn = new St.Button({
                style_class: 'x47-pkg-cmd',
                reactive: true,
                track_hover: true,
                x_expand: true,
            });
            const box = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true});
            box.add_child(new St.Label({text: r.label, style_class: 'x47-pkg-label'}));
            box.add_child(new St.Label({text: r.cmd, style_class: 'x47-pkg-cmdtext'}));
            btn.set_child(box);
            btn.connect('clicked', () => this._copyCmd(r.cmd));
            this._pkgResults.add_child(btn);
        }
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._placeCards();
            return GLib.SOURCE_REMOVE;
        });
    }

    // --- drag / grid / layout -----------------------------------------------

    _attachDrag(handle, card, id) {
        handle.connect('button-press-event', (_actor, event) => {
            if (event.get_button() !== 1)
                return Clutter.EVENT_PROPAGATE;
            const [px, py] = event.get_coords();
            this._drag = {
                card, id,
                startX: px, startY: py,
                dx: px - card.x, dy: py - card.y,
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
                if (Math.abs(px - this._drag.startX) < DRAG_THRESHOLD &&
                    Math.abs(py - this._drag.startY) < DRAG_THRESHOLD)
                    return Clutter.EVENT_STOP;
                this._drag.moved = true;
            }
            let x = Math.round(px - this._drag.dx);
            let y = Math.round(py - this._drag.dy);
            [x, y] = this._snapClamp(this._drag.card, x, y);
            this._drag.card.set_position(x, y);
            return Clutter.EVENT_STOP;
        }
        if (t === Clutter.EventType.BUTTON_RELEASE) {
            const {card, id, moved} = this._drag;
            if (moved) {
                const [x, y] = this._snapClamp(card, card.x, card.y);
                card.set_position(x, y);
                this._layout[id] = {x, y};
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

    _snapClamp(card, x, y) {
        const mon = Main.layoutManager.primaryMonitor;
        if (!mon)
            return [x, y];
        const w = Math.max(card.width || CARD_WIDTH, 1);
        const h = Math.max(card.height || 80, 1);
        let sx = mon.x + MARGIN + Math.round((x - mon.x - MARGIN) / CELL) * CELL;
        let sy = mon.y + MARGIN + Math.round((y - mon.y - MARGIN) / CELL) * CELL;
        sx = Math.max(mon.x + MARGIN, Math.min(sx, mon.x + mon.width - w - MARGIN));
        sy = Math.max(mon.y + MARGIN, Math.min(sy, mon.y + mon.height - h - MARGIN));
        // Re-snap after clamp so edges stay on-grid.
        sx = mon.x + MARGIN + Math.round((sx - mon.x - MARGIN) / CELL) * CELL;
        sy = mon.y + MARGIN + Math.round((sy - mon.y - MARGIN) / CELL) * CELL;
        return [sx, sy];
    }

    _placeCards() {
        const mon = Main.layoutManager.primaryMonitor;
        if (!mon || !this._cards)
            return;

        const rightStack = ['clock', 'btc', 'vitals', 'pkg'];
        let y = mon.y + MARGIN + CELL * 2;
        for (const id of rightStack) {
            const card = this._cards[id];
            if (!card)
                continue;
            const saved = this._layout[id];
            const h = Math.max(card.height || 100, 80);
            let x, cy;
            if (saved) {
                [x, cy] = this._snapClamp(card, saved.x, saved.y);
            } else {
                x = mon.x + mon.width - CARD_WIDTH - MARGIN;
                cy = y;
                [x, cy] = this._snapClamp(card, x, cy);
                y = cy + h + CARD_GAP;
            }
            card.set_position(x, cy);
        }

        const reddit = this._cards.reddit;
        if (reddit) {
            const saved = this._layout.reddit;
            let x, cy;
            if (saved) {
                [x, cy] = this._snapClamp(reddit, saved.x, saved.y);
            } else {
                [x, cy] = this._snapClamp(reddit, mon.x + MARGIN, mon.y + MARGIN + CELL * 2);
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
        } catch { /* none */ }
        return {};
    }

    _saveLayout() {
        try {
            const dir = GLib.build_filenamev(
                [GLib.get_user_config_dir(), 'x47-widgets']);
            GLib.mkdir_with_parents(dir, 0o755);
            GLib.file_set_contents(this._layoutFile(), JSON.stringify(this._layout));
        } catch (e) {
            logError(e, 'x47-widgets: could not save layout');
        }
    }

    // --- fullscreen hide ----------------------------------------------------

    _setupFullscreenWatch() {
        const refresh = () => this._updateFullscreenVisibility();
        try {
            this._fsDisplayId = global.display.connect('in-fullscreen-changed', refresh);
        } catch {
            this._fsDisplayId = 0;
        }
        try {
            this._fsCreatedId = global.display.connect('window-created', (_d, win) => {
                this._watchWindow(win);
                refresh();
            });
        } catch {
            this._fsCreatedId = 0;
        }
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (win)
                this._watchWindow(win);
        }
        refresh();
        this._fsTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
            refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _watchWindow(win) {
        if (!win || win._x47FsWatched)
            return;
        win._x47FsWatched = true;
        try {
            const id = win.connect('notify::fullscreen', () => this._updateFullscreenVisibility());
            this._winSignals.push([win, id]);
        } catch { /* ignore */ }
    }

    _teardownFullscreenWatch() {
        if (this._fsDisplayId) {
            global.display.disconnect(this._fsDisplayId);
            this._fsDisplayId = 0;
        }
        if (this._fsCreatedId) {
            global.display.disconnect(this._fsCreatedId);
            this._fsCreatedId = 0;
        }
        if (this._fsTimer) {
            GLib.source_remove(this._fsTimer);
            this._fsTimer = 0;
        }
        for (const [win, id] of this._winSignals) {
            try {
                win.disconnect(id);
            } catch { /* gone */ }
        }
        this._winSignals = [];
    }

    _primaryHasFullscreen() {
        const mon = Main.layoutManager.primaryMonitor;
        if (!mon)
            return false;
        try {
            if (typeof global.display.get_monitor_in_fullscreen === 'function' &&
                global.display.get_monitor_in_fullscreen(mon.index))
                return true;
        } catch { /* fall through */ }
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (!win || win.minimized)
                continue;
            try {
                if (win.get_monitor() !== mon.index)
                    continue;
                if (win.is_fullscreen && win.is_fullscreen())
                    return true;
                if (win.fullscreen)
                    return true;
            } catch { /* ignore */ }
        }
        return false;
    }

    _updateFullscreenVisibility() {
        const hide = this._primaryHasFullscreen();
        if (hide === this._hiddenForFullscreen)
            return;
        this._hiddenForFullscreen = hide;
        for (const id in this._cards) {
            const card = this._cards[id];
            if (card)
                card.visible = !hide;
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
        for (const e of xml.split('<entry>').slice(1)) {
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
            box.add_child(new St.Label({text: title, style_class: 'x47-reddit-title', x_expand: true}));
            box.add_child(new St.Label({text: `r/${p.sub}`, style_class: 'x47-reddit-sub'}));
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
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._placeCards();
            return GLib.SOURCE_REMOVE;
        });
    }
}
