// Linux CMD Helper — a single desktop card: type a question ("how do I
// install notepad++"), get back just the Ubuntu terminal command (Claude
// Haiku via the Anthropic API). Click the result to copy it.
//
// Layering: chrome overlay (always clickable / focusable on Wayland). Hides
// in true fullscreen. API key: ~/.config/x47-widgets/anthropic.key
// (chmod 600, never in git).

import GLib from 'gi://GLib';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import Soup from 'gi://Soup';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const API_URL = 'https://api.anthropic.com/v1/messages';
const API_VERSION = '2023-06-01';
const MODEL = 'claude-haiku-4-5';
const SYSTEM_PROMPT =
    'You are Linux CMD Helper on Ubuntu. Reply with ONLY the exact terminal ' +
    'command for the request — no explanation, no markdown, no backticks. ' +
    'Prefer apt, then snap. Join multi-step commands with " && ". If no ' +
    'command can do it, reply exactly: no command for that';

const CARD_ID = 'cmd';
const CARD_WIDTH = 380;
const MARGIN = 32;
const CELL = 16;
const DRAG_THRESHOLD = 4;

export default class LinuxCmdHelperExtension extends Extension {
    enable() {
        this._session = new Soup.Session();
        try {
            this._session.timeout = 30;
        } catch { /* soup variant without timeout prop */ }
        this._layout = this._loadLayout();
        this._drag = null;
        this._dragMonId = 0;
        this._requestSeq = 0;
        this._chrome = false;

        this._buildCard();

        this._monitorsChangedId = Main.layoutManager.connect(
            'monitors-changed', () => this._placeCard());

        this._placeIdle = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._placeCard();
            this._focusEntry();
            this._placeIdle = 0;
            return GLib.SOURCE_REMOVE;
        });
    }

    disable() {
        if (this._placeIdle) {
            GLib.source_remove(this._placeIdle);
            this._placeIdle = 0;
        }
        if (this._statusTimer) {
            GLib.source_remove(this._statusTimer);
            this._statusTimer = 0;
        }
        if (this._monitorsChangedId) {
            Main.layoutManager.disconnect(this._monitorsChangedId);
            this._monitorsChangedId = null;
        }
        if (this._dragMonId) {
            global.stage.disconnect(this._dragMonId);
            this._dragMonId = 0;
        }
        this._drag = null;
        if (this._session) {
            this._session.abort();
            this._session = null;
        }
        if (this._card) {
            if (this._chrome) {
                try {
                    Main.layoutManager.removeChrome(this._card);
                } catch {
                    this._card.get_parent()?.remove_child(this._card);
                }
                this._chrome = false;
            } else {
                this._card.get_parent()?.remove_child(this._card);
            }
            this._card.destroy();
            this._card = null;
        }
        this._entry = this._status = this._resultBtn = this._resultLabel = null;
    }

    // --- UI -------------------------------------------------------------

    _buildCard() {
        this._card = new St.BoxLayout({
            style_class: 'x47-cmd-card',
            orientation: Clutter.Orientation.VERTICAL,
            reactive: true,
            track_hover: true,
            can_focus: true,
            width: CARD_WIDTH,
            visible: true,
        });

        // Chrome overlay: reliable clicks + keyboard focus on Wayland.
        // trackFullscreen hides it during F11 / true fullscreen apps.
        Main.layoutManager.addChrome(this._card, {
            affectsInputRegion: true,
            affectsStruts: false,
            trackFullscreen: true,
        });
        this._chrome = true;

        const titleRow = new St.BoxLayout({
            style_class: 'x47-cmd-title-row', reactive: true, track_hover: true,
        });
        const dot = new St.Label({text: '●', style_class: 'x47-cmd-dot'});
        const title = new St.Label({
            text: 'LINUX CMD HELPER', style_class: 'x47-cmd-title', x_expand: true,
        });
        titleRow.add_child(dot);
        titleRow.add_child(title);
        this._attachDrag(titleRow);
        this._card.add_child(titleRow);

        const inputRow = new St.BoxLayout({style_class: 'x47-cmd-input-row'});
        this._entry = new St.Entry({
            style_class: 'x47-cmd-entry',
            hint_text: 'how do I install notepad++ …',
            can_focus: true,
            reactive: true,
            track_hover: true,
            x_expand: true,
        });
        this._entry.clutter_text.connect('activate', () => this._ask());
        // Wayland: St.Entry often won't take focus unless we force it on click.
        this._entry.connect('button-press-event', () => {
            this._focusEntry();
            return Clutter.EVENT_PROPAGATE;
        });
        this._card.connect('button-press-event', () => {
            this._focusEntry();
            return Clutter.EVENT_PROPAGATE;
        });
        const go = new St.Button({
            label: '➜', style_class: 'x47-cmd-go',
            reactive: true, can_focus: true, track_hover: true,
        });
        go.connect('clicked', () => this._ask());
        inputRow.add_child(this._entry);
        inputRow.add_child(go);
        this._card.add_child(inputRow);

        this._resultBtn = new St.Button({
            style_class: 'x47-cmd-result',
            reactive: true,
            can_focus: true,
            track_hover: true,
            x_expand: true,
            visible: false,
        });
        this._resultLabel = new St.Label({
            text: '', style_class: 'x47-cmd-result-text', x_expand: true,
        });
        this._resultLabel.clutter_text.set_line_wrap(true);
        this._resultBtn.set_child(this._resultLabel);
        this._resultBtn.connect('clicked', () => this._copyResult());
        this._card.add_child(this._resultBtn);

        this._status = new St.Label({
            text: 'ask for a command — click result to copy',
            style_class: 'x47-cmd-status',
        });
        this._card.add_child(this._status);
    }

    _focusEntry() {
        if (!this._entry)
            return;
        try {
            this._entry.grab_key_focus();
        } catch { /* older shell */ }
        try {
            global.stage.set_key_focus(this._entry.clutter_text);
        } catch { /* ignore */ }
    }

    _setStatus(text, revertAfter = 0) {
        if (!this._status)
            return;
        this._status.set_text(text);
        if (this._statusTimer) {
            GLib.source_remove(this._statusTimer);
            this._statusTimer = 0;
        }
        if (revertAfter > 0) {
            this._statusTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, revertAfter, () => {
                this._status?.set_text('ask for a command — click result to copy');
                this._statusTimer = 0;
                return GLib.SOURCE_REMOVE;
            });
        }
    }

    _copyResult() {
        const cmd = this._resultLabel?.get_text() || '';
        if (!cmd)
            return;
        St.Clipboard.get_default().set_text(St.ClipboardType.CLIPBOARD, cmd);
        this._setStatus('copied — paste in a terminal', 3);
    }

    // --- Anthropic query --------------------------------------------------

    _keyFile() {
        return GLib.build_filenamev(
            [GLib.get_user_config_dir(), 'x47-widgets', 'anthropic.key']);
    }

    _readKey() {
        try {
            const [ok, bytes] = GLib.file_get_contents(this._keyFile());
            if (ok)
                return new TextDecoder().decode(bytes).trim();
        } catch { /* missing */ }
        return null;
    }

    _cleanCommand(text) {
        let t = (text || '').trim();
        // Strip markdown fences / backticks the model sometimes ignores.
        t = t.replace(/^```[a-zA-Z0-9_-]*\s*/m, '').replace(/\s*```$/m, '');
        t = t.replace(/^`+|`+$/g, '').trim();
        // If multiple lines of prose slipped through, keep the first command-looking line.
        const lines = t.split('\n').map(l => l.trim()).filter(Boolean);
        if (lines.length > 1) {
            const cmdLike = lines.find(l =>
                !/^(here|the|this|you|to|run|use|try)\b/i.test(l));
            if (cmdLike)
                t = cmdLike.replace(/^`+|`+$/g, '').trim();
        }
        return t;
    }

    _ask() {
        const q = (this._entry?.get_text() || '').trim();
        if (!q) {
            this._setStatus('type a question first', 3);
            this._focusEntry();
            return;
        }
        const key = this._readKey();
        if (!key) {
            this._setStatus('no API key — put it in ~/.config/x47-widgets/anthropic.key');
            return;
        }

        const seq = ++this._requestSeq;
        this._resultBtn.visible = false;
        this._setStatus('thinking…');

        const payload = {
            model: MODEL,
            max_tokens: 150,
            system: SYSTEM_PROMPT,
            messages: [{role: 'user', content: q}],
        };
        const msg = Soup.Message.new('POST', API_URL);
        const headers = msg.get_request_headers();
        headers.append('x-api-key', key);
        headers.append('anthropic-version', API_VERSION);
        msg.set_request_body_from_bytes(
            'application/json',
            new GLib.Bytes(new TextEncoder().encode(JSON.stringify(payload))));

        this._session.send_and_read_async(
            msg, GLib.PRIORITY_DEFAULT, null, (session, res) => {
                if (seq !== this._requestSeq || !this._card)
                    return;
                try {
                    const bytes = session.send_and_read_finish(res);
                    const body = new TextDecoder().decode(bytes.get_data());
                    if (msg.get_status() !== Soup.Status.OK) {
                        let detail = `HTTP ${msg.get_status()}`;
                        try {
                            const err = JSON.parse(body);
                            if (err?.error?.message)
                                detail = err.error.message.slice(0, 80);
                        } catch { /* keep HTTP status */ }
                        this._setStatus(`API error: ${detail}`);
                        return;
                    }
                    const data = JSON.parse(body);
                    const text = this._cleanCommand(data?.content?.[0]?.text || '');
                    if (!text) {
                        this._setStatus('empty reply — try rephrasing');
                        return;
                    }
                    this._resultLabel.set_text(text);
                    this._resultBtn.visible = true;
                    this._setStatus('click the command to copy it');
                    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                        this._clampToMonitor();
                        return GLib.SOURCE_REMOVE;
                    });
                } catch (e) {
                    logError(e, 'linux-cmd-helper: request failed');
                    this._setStatus('request failed — check network');
                }
            });
    }

    // --- drag / snap / layout ---------------------------------------------

    _attachDrag(handle) {
        handle.connect('button-press-event', (_actor, event) => {
            if (event.get_button() !== 1)
                return Clutter.EVENT_PROPAGATE;
            const [px, py] = event.get_coords();
            this._drag = {
                startX: px, startY: py,
                dx: px - this._card.x, dy: py - this._card.y,
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
            const x = Math.round(px - this._drag.dx);
            const y = Math.round(py - this._drag.dy);
            const [sx, sy] = this._snapClamp(x, y);
            this._card.set_position(sx, sy);
            return Clutter.EVENT_STOP;
        }
        if (t === Clutter.EventType.BUTTON_RELEASE) {
            if (this._drag.moved) {
                const [x, y] = this._snapClamp(this._card.x, this._card.y);
                this._card.set_position(x, y);
                this._layout[CARD_ID] = {x, y};
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

    _snapClamp(x, y) {
        const mon = Main.layoutManager.primaryMonitor;
        if (!mon)
            return [x, y];
        const w = Math.max(this._card.width || CARD_WIDTH, 1);
        const h = Math.max(this._card.height || 80, 1);
        const panel = Main.panel?.height || 32;
        let sx = mon.x + MARGIN + Math.round((x - mon.x - MARGIN) / CELL) * CELL;
        let sy = mon.y + panel + MARGIN +
            Math.round((y - mon.y - panel - MARGIN) / CELL) * CELL;
        sx = Math.max(mon.x + MARGIN, Math.min(sx, mon.x + mon.width - w - MARGIN));
        sy = Math.max(mon.y + panel + MARGIN,
            Math.min(sy, mon.y + mon.height - h - MARGIN));
        sx = mon.x + MARGIN + Math.round((sx - mon.x - MARGIN) / CELL) * CELL;
        sy = mon.y + panel + MARGIN +
            Math.round((sy - mon.y - panel - MARGIN) / CELL) * CELL;
        return [sx, sy];
    }

    _placeCard() {
        const mon = Main.layoutManager.primaryMonitor;
        if (!mon || !this._card)
            return;
        const panel = Main.panel?.height || 32;
        const saved = this._layout[CARD_ID];
        let x, y;
        if (saved) {
            [x, y] = this._snapClamp(saved.x, saved.y);
        } else {
            [x, y] = this._snapClamp(
                mon.x + mon.width - CARD_WIDTH - MARGIN,
                mon.y + panel + MARGIN + CELL);
        }
        this._card.set_position(x, y);
        this._card.visible = true;
    }

    _clampToMonitor() {
        if (!this._card)
            return;
        const [x, y] = this._snapClamp(this._card.x, this._card.y);
        this._card.set_position(x, y);
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
            logError(e, 'linux-cmd-helper: could not save layout');
        }
    }
}
