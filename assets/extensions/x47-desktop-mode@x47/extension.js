// Top-bar Visual ↔ Performance toggle (right side of the panel).
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

const REFRESH_SECONDS = 8;

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

function _readMode() {
    try {
        const home = GLib.get_home_dir();
        const conf = Gio.File.new_for_path(`${home}/.config/x47/settings.conf`);
        const [, bytes] = conf.load_contents(null);
        const text = new TextDecoder().decode(bytes);
        for (const line of text.split('\n')) {
            const m = line.match(/^\s*desktop_mode\s*=\s*(\S+)/);
            if (m)
                return m[1].toLowerCase();
        }
    } catch (_e) { /* missing / unreadable */ }
    return 'performance';
}

export default class X47DesktopModeExtension extends Extension {
    enable() {
        this._indicator = new PanelMenu.Button(0.0, 'X47 Desktop Mode', false);
        this._indicator.add_style_class_name('x47-desktop-mode-perf');

        this._label = new St.Label({
            text: 'PERF',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'x47-desktop-mode-label',
        });
        this._indicator.add_child(this._label);

        this._itemPerf = new PopupMenu.PopupMenuItem('Performance — lean (no cube)');
        this._itemVisual = new PopupMenu.PopupMenuItem('Visual — cube, Coverflow, blur');
        this._itemPerf.connect('activate', () => this._apply('performance'));
        this._itemVisual.connect('activate', () => this._apply('visual'));
        this._indicator.menu.addMenuItem(this._itemPerf);
        this._indicator.menu.addMenuItem(this._itemVisual);
        this._indicator.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        const tip = new PopupMenu.PopupMenuItem(
            'Tip: log out once if cube/blur did not load (Wayland)');
        tip.setSensitive(false);
        this._indicator.menu.addMenuItem(tip);

        // Right side of the top bar (system indicators), as in the screenshot.
        Main.panel.addToStatusArea('x47-desktop-mode', this._indicator, 1, 'right');

        this._refresh();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, REFRESH_SECONDS, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = 0;
        }
        this._indicator?.destroy();
        this._indicator = null;
        this._label = null;
        this._itemPerf = null;
        this._itemVisual = null;
    }

    _refresh() {
        const mode = _readMode();
        const visual = mode === 'visual' || mode === 'full' || mode === 'fx';
        if (!this._label || !this._indicator)
            return;
        this._label.set_text(visual ? 'VISUAL' : 'PERF');
        this._indicator.remove_style_class_name('x47-desktop-mode-perf');
        this._indicator.remove_style_class_name('x47-desktop-mode-visual');
        this._indicator.add_style_class_name(
            visual ? 'x47-desktop-mode-visual' : 'x47-desktop-mode-perf');
        if (this._itemPerf)
            this._itemPerf.setOrnament(visual
                ? PopupMenu.Ornament.NONE
                : PopupMenu.Ornament.DOT);
        if (this._itemVisual)
            this._itemVisual.setOrnament(visual
                ? PopupMenu.Ornament.DOT
                : PopupMenu.Ornament.NONE);
    }

    _apply(mode) {
        const bin = _homeBin('x47-desktop-mode');
        try {
            const proc = Gio.Subprocess.new(
                [bin, mode],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
            proc.wait_async(null, () => {
                this._refresh();
            });
        } catch (e) {
            console.error(`x47-desktop-mode: failed to run ${bin}: ${e}`);
            Main.notifyError?.('X47 Desktop', `Could not run ${bin}`);
        }
    }
}
