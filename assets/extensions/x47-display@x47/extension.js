// Top-bar display comfort: brightness, blue-light, glare, adaptive (Visual).
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as Slider from 'resource:///org/gnome/shell/ui/slider.js';

const REFRESH_SECONDS = 6;

function _homeBin(name) {
    const home = GLib.get_home_dir();
    const candidates = [
        `${home}/.local/bin/${name}`,
        `${home}/.local/share/ubuntu-x47-build/bin/${name}`,
    ];
    for (const p of candidates) {
        if (GLib.file_test(p, GLib.FileTest.IS_EXECUTABLE))
            return p;
    }
    return name;
}

function _readKvFile(path, out) {
    try {
        const conf = Gio.File.new_for_path(path);
        const [, bytes] = conf.load_contents(null);
        const text = new TextDecoder().decode(bytes);
        for (const line of text.split('\n')) {
            const m = line.match(/^\s*([a-z_]+)\s*=\s*(\S+)/);
            if (!m)
                continue;
            out[m[1]] = m[2];
        }
    } catch (_e) { /* missing */ }
    return out;
}

function _readConf() {
    const raw = _readKvFile(`${GLib.get_home_dir()}/.config/x47/display.conf`, {});
    const num = (k, d) => {
        const n = parseInt(raw[k] ?? String(d), 10);
        return Number.isFinite(n) ? Math.max(0, Math.min(100, n)) : d;
    };
    const on = v => v === '1' || v === 'true' || v === 'on';
    return {
        brightness: num('brightness', 100),
        blue_light: on(raw.blue_light) ? 1 : 0,
        warmth: num('warmth', 40),
        glare: num('glare', 0),
        adaptive: on(raw.adaptive) ? 1 : 0,
        adaptive_phase: raw.adaptive_phase || 'none',
    };
}

function _visualStackAvailable() {
    // Visual stack is retired (Performance-only build) — adaptive stays hidden
    // unless an old settings file still says a visual-capable stack exists.
    const raw = _readKvFile(
        `${GLib.get_home_dir()}/.config/x47/settings.conf`, {});
    const installed = (raw.desktop_modes_installed || 'performance').toLowerCase();
    return installed === 'visual' || installed === 'both' ||
        installed === 'full' || installed === 'fx' || installed === 'all';
}

// Must registerClass — plain ES6 extends breaks on GNOME Shell 45+ ("no GType").
const SliderRow = GObject.registerClass(
class SliderRow extends PopupMenu.PopupBaseMenuItem {
    _init(labelText, iconName, initial01) {
        super._init({activate: false, can_focus: false});

        this._box = new St.BoxLayout({
            style_class: 'x47-display-row',
            x_expand: true,
        });
        this.add_child(this._box);

        this._icon = new St.Icon({
            icon_name: iconName,
            style_class: 'popup-menu-icon',
            icon_size: 16,
        });
        this._box.add_child(this._icon);

        this._name = new St.Label({
            text: labelText,
            style_class: 'x47-display-row-label',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._box.add_child(this._name);

        this.slider = new Slider.Slider(initial01);
        this.slider.add_style_class_name('x47-display-slider');
        this.slider.x_expand = true;
        this._box.add_child(this.slider);

        this._value = new St.Label({
            text: `${Math.round(initial01 * 100)}%`,
            style_class: 'x47-display-value',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this._box.add_child(this._value);

        this.slider.connect('notify::value', () => {
            this._value.set_text(`${Math.round(this.slider.value * 100)}%`);
        });
    }

    setValue01(v) {
        const clamped = Math.max(0, Math.min(1, v));
        if (Math.abs(this.slider.value - clamped) < 0.005)
            return;
        this.slider.value = clamped;
        this._value.set_text(`${Math.round(clamped * 100)}%`);
    }
});

export default class X47DisplayExtension extends Extension {
    enable() {
        this._busy = false;
        this._visualOk = _visualStackAvailable();
        this._indicator = new PanelMenu.Button(0.0, 'X47 Display', false);

        this._icon = new St.Icon({
            icon_name: 'display-brightness-symbolic',
            style_class: 'system-status-icon',
        });
        this._label = new St.Label({
            text: 'EYE',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'x47-display-label',
        });
        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        box.add_child(this._icon);
        box.add_child(this._label);
        this._indicator.add_child(box);

        const conf = _readConf();

        this._bright = new SliderRow(
            'Brightness', 'display-brightness-symbolic', conf.brightness / 100);
        this._warmth = new SliderRow(
            'Warmth', 'night-light-symbolic', conf.warmth / 100);
        this._glare = new SliderRow(
            'Glare cut', 'weather-fog-symbolic', conf.glare / 100);

        this._blue = new PopupMenu.PopupSwitchMenuItem(
            'Blue-light filter', conf.blue_light === 1);

        this._indicator.menu.addMenuItem(this._bright);
        this._indicator.menu.addMenuItem(this._blue);
        this._indicator.menu.addMenuItem(this._warmth);
        this._indicator.menu.addMenuItem(this._glare);

        if (this._visualOk) {
            this._adaptive = new PopupMenu.PopupSwitchMenuItem(
                'Adaptive (time / light)', conf.adaptive === 1);
            this._phaseItem = new PopupMenu.PopupMenuItem(
                `Phase: ${conf.adaptive_phase}`);
            this._phaseItem.setSensitive(false);
            this._indicator.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
            this._indicator.menu.addMenuItem(this._adaptive);
            this._indicator.menu.addMenuItem(this._phaseItem);
            this._adaptive.connect('toggled', (_item, state) => {
                if (this._busy)
                    return;
                this._run(['adaptive', state ? 'on' : 'off']);
            });
        } else {
            this._adaptive = null;
            this._phaseItem = null;
        }

        this._indicator.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const comfort = new PopupMenu.PopupMenuItem('Apply comfort defaults');
        comfort.connect('activate', () => this._run(['comfort']));
        this._indicator.menu.addMenuItem(comfort);

        const tip = new PopupMenu.PopupMenuItem(
            this._visualOk
                ? 'Adaptive: time/light. Blue-light off sticks; Adaptive on clears that lock'
                : 'Adaptive display retired with the Visual stack');
        tip.setSensitive(false);
        this._indicator.menu.addMenuItem(tip);

        this._bright.slider.connect('drag-end', () => this._commitBrightness());
        this._warmth.slider.connect('drag-end', () => this._commitWarmth());
        this._glare.slider.connect('drag-end', () => this._commitGlare());
        this._bright.slider.connect('notify::value', () => this._queueBright());
        this._warmth.slider.connect('notify::value', () => this._queueWarmth());
        this._glare.slider.connect('notify::value', () => this._queueGlare());
        this._blue.connect('toggled', (_item, state) => {
            if (this._busy)
                return;
            this._run(['blue-light', state ? 'on' : 'off']);
        });

        Main.panel.addToStatusArea('x47-display', this._indicator, 2, 'right');

        this._refresh();
        this._timer = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, REFRESH_SECONDS, () => {
                if (!this._indicator?.menu?.isOpen)
                    this._refresh();
                return GLib.SOURCE_CONTINUE;
            });
    }

    disable() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = 0;
        }
        for (const id of [this._brightDebounce, this._warmthDebounce, this._glareDebounce]) {
            if (id)
                GLib.source_remove(id);
        }
        this._brightDebounce = this._warmthDebounce = this._glareDebounce = 0;
        this._indicator?.destroy();
        this._indicator = null;
        this._bright = this._warmth = this._glare = this._blue = null;
        this._adaptive = this._phaseItem = null;
        this._icon = this._label = null;
    }

    _queueBright() {
        if (this._busy)
            return;
        if (this._brightDebounce)
            GLib.source_remove(this._brightDebounce);
        this._brightDebounce = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 180, () => {
            this._brightDebounce = 0;
            this._commitBrightness();
            return GLib.SOURCE_REMOVE;
        });
    }

    _queueWarmth() {
        if (this._busy)
            return;
        if (this._warmthDebounce)
            GLib.source_remove(this._warmthDebounce);
        this._warmthDebounce = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 180, () => {
            this._warmthDebounce = 0;
            this._commitWarmth();
            return GLib.SOURCE_REMOVE;
        });
    }

    _queueGlare() {
        if (this._busy)
            return;
        if (this._glareDebounce)
            GLib.source_remove(this._glareDebounce);
        this._glareDebounce = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 180, () => {
            this._glareDebounce = 0;
            this._commitGlare();
            return GLib.SOURCE_REMOVE;
        });
    }

    _commitBrightness() {
        if (!this._bright || this._busy)
            return;
        this._run(['brightness', String(Math.round(this._bright.slider.value * 100))]);
    }

    _commitWarmth() {
        if (!this._warmth || this._busy)
            return;
        this._run(['warmth', String(Math.round(this._warmth.slider.value * 100))]);
    }

    _commitGlare() {
        if (!this._glare || this._busy)
            return;
        this._run(['glare', String(Math.round(this._glare.slider.value * 100))]);
    }

    _refresh() {
        if (this._busy || !this._bright)
            return;
        this._visualOk = _visualStackAvailable();
        const conf = _readConf();
        this._busy = true;
        try {
            this._bright.setValue01(conf.brightness / 100);
            this._warmth.setValue01(conf.warmth / 100);
            this._glare.setValue01(conf.glare / 100);
            if (this._blue && this._blue.state !== (conf.blue_light === 1))
                this._blue.setToggleState(conf.blue_light === 1);
            if (this._adaptive && this._adaptive.state !== (conf.adaptive === 1))
                this._adaptive.setToggleState(conf.adaptive === 1);
            if (this._phaseItem)
                this._phaseItem.label.set_text(`Phase: ${conf.adaptive_phase}`);
            if (this._label) {
                if (conf.adaptive === 1)
                    this._label.set_text('AUTO');
                else
                    this._label.set_text(conf.blue_light === 1 ? 'EYE' : 'DISP');
            }
        } finally {
            this._busy = false;
        }
    }

    _run(args) {
        const bin = _homeBin('x47-display');
        try {
            const proc = Gio.Subprocess.new(
                [bin, ...args],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
            proc.wait_async(null, () => {
                this._refresh();
            });
        } catch (e) {
            console.error(`x47-display: failed to run ${bin}: ${e}`);
            Main.notifyError?.('X47 Display', `Could not run ${bin}`);
        }
    }
}
