// Top-bar X47 Sync — open hardened Syncthing GUI / control the service.
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

const REFRESH_SECONDS = 10;

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

function _run(argv, cb) {
    try {
        const proc = Gio.Subprocess.new(
            argv,
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        proc.communicate_utf8_async(null, null, (_p, res) => {
            let stdout = '';
            try {
                const [, out] = proc.communicate_utf8_finish(res);
                stdout = out ?? '';
            } catch (_e) { /* ignore */ }
            cb?.(stdout, proc.get_successful());
        });
    } catch (e) {
        console.error(`x47-syncthing: ${e}`);
        Main.notifyError?.('X47 Sync', String(e));
    }
}

export default class X47SyncthingExtension extends Extension {
    enable() {
        this._running = false;
        this._indicator = new PanelMenu.Button(0.0, 'X47 Sync', false);
        this._indicator.add_style_class_name('x47-syncthing-off');

        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        const iconPath = `${this.path}/icons/x47-syncthing.svg`;
        if (GLib.file_test(iconPath, GLib.FileTest.EXISTS)) {
            this._icon = new St.Icon({
                gicon: Gio.FileIcon.new(Gio.File.new_for_path(iconPath)),
                style_class: 'x47-syncthing-icon system-status-icon',
                icon_size: 18,
            });
        } else {
            this._icon = new St.Icon({
                icon_name: 'folder-sync-symbolic',
                style_class: 'x47-syncthing-icon system-status-icon',
                icon_size: 18,
            });
        }
        this._label = new St.Label({
            text: 'SYNC',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'x47-syncthing-label',
        });
        box.add_child(this._icon);
        box.add_child(this._label);
        this._indicator.add_child(box);

        this._statusItem = new PopupMenu.PopupMenuItem('Status: …');
        this._statusItem.setSensitive(false);
        this._openItem = new PopupMenu.PopupMenuItem('Open Sync GUI');
        this._startItem = new PopupMenu.PopupMenuItem('Start Sync');
        this._stopItem = new PopupMenu.PopupMenuItem('Stop Sync');
        this._shareItem = new PopupMenu.PopupMenuItem('Open X47Share folder');
        this._idItem = new PopupMenu.PopupMenuItem('Copy device ID');

        this._openItem.connect('activate', () => this._openGui());
        this._startItem.connect('activate', () => this._ctl('start'));
        this._stopItem.connect('activate', () => this._ctl('stop'));
        this._shareItem.connect('activate', () => this._openShare());
        this._idItem.connect('activate', () => this._copyId());

        // Left-click opens the GUI immediately; right-click opens the menu.
        this._indicator.connect('button-press-event', (_a, event) => {
            if (event.get_button() === 1) {
                this._openGui();
                return Clutter.EVENT_STOP;
            }
            return Clutter.EVENT_PROPAGATE;
        });

        this._indicator.menu.addMenuItem(this._statusItem);
        this._indicator.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._indicator.menu.addMenuItem(this._openItem);
        this._indicator.menu.addMenuItem(this._startItem);
        this._indicator.menu.addMenuItem(this._stopItem);
        this._indicator.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._indicator.menu.addMenuItem(this._shareItem);
        this._indicator.menu.addMenuItem(this._idItem);
        const tip = new PopupMenu.PopupMenuItem('LAN-only · no relays · localhost GUI');
        tip.setSensitive(false);
        this._indicator.menu.addMenuItem(tip);

        // Right status area — near display / mode chips.
        Main.panel.addToStatusArea('x47-syncthing', this._indicator, 0, 'right');

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
        this._icon = this._label = null;
        this._statusItem = this._openItem = this._startItem = this._stopItem = null;
        this._shareItem = this._idItem = null;
    }

    _bin() {
        return _homeBin('x47-syncthing');
    }

    _refresh() {
        _run([this._bin(), 'status'], stdout => {
            const running = /^running=1$/m.test(stdout || '');
            this._running = running;
            if (!this._label || !this._indicator)
                return;
            this._label.set_text(running ? 'SYNC' : 'OFF');
            this._indicator.remove_style_class_name('x47-syncthing-off');
            if (!running)
                this._indicator.add_style_class_name('x47-syncthing-off');
            if (this._statusItem)
                this._statusItem.label.set_text(
                    running ? 'Status: running (LAN sync)' : 'Status: stopped');
            if (this._startItem)
                this._startItem.visible = !running;
            if (this._stopItem)
                this._stopItem.visible = running;
        });
    }

    _openGui() {
        _run([this._bin(), 'open'], () => this._refresh());
    }

    _ctl(cmd) {
        _run([this._bin(), cmd], () => {
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 600, () => {
                this._refresh();
                return GLib.SOURCE_REMOVE;
            });
        });
    }

    _openShare() {
        const share = `${GLib.get_home_dir()}/X47Share`;
        try {
            Gio.AppInfo.launch_default_for_uri(`file://${share}`, null);
        } catch (e) {
            Main.notifyError?.('X47 Sync', `Could not open ${share}`);
        }
    }

    _copyId() {
        _run([this._bin(), 'id'], (stdout, ok) => {
            const id = (stdout || '').trim().split(/\s+/)[0];
            if (!ok || !id) {
                Main.notifyError?.('X47 Sync', 'Could not read device ID');
                return;
            }
            try {
                const clip = St.Clipboard.get_default();
                clip.set_text(St.ClipboardType.CLIPBOARD, id);
                Main.notify?.('X47 Sync', 'Device ID copied — paste into Android Syncthing');
            } catch (_e) {
                Main.notify?.('X47 Sync', id);
            }
        });
    }
}
