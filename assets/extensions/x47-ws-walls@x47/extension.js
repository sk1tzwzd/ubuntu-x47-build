// X47 Workspace Walls — change the ASCII duster wallpaper colour when the
// active GNOME workspace changes (desktop cube). Files live in
// ~/.local/share/backgrounds/x47-circuit{,-green,-red,-purple}.png.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const FILES = [
    'x47-circuit.png',         // workspace 1 — teal
    'x47-circuit-pink.png',    // workspace 2 — pink on white
    'x47-circuit-blue.png',    // workspace 3 — white on light blue
    'x47-circuit-lime.png',    // workspace 4 — white on lime
];

export default class X47WsWallsExtension extends Extension {
    enable() {
        this._settings = new Gio.Settings({schema_id: 'org.gnome.desktop.background'});
        this._bgDir = GLib.build_filenamev(
            [GLib.get_user_data_dir(), 'backgrounds']);
        this._wsId = global.workspace_manager.connect(
            'active-workspace-changed', () => this._apply());
        // Delay first apply slightly so the session finishes coming up.
        this._idle = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._apply();
            this._idle = 0;
            return GLib.SOURCE_REMOVE;
        });
    }

    disable() {
        if (this._wsId) {
            global.workspace_manager.disconnect(this._wsId);
            this._wsId = 0;
        }
        if (this._idle) {
            GLib.source_remove(this._idle);
            this._idle = 0;
        }
        this._settings = null;
    }

    _apply() {
        if (!this._settings)
            return;
        const n = global.workspace_manager.n_workspaces;
        let idx = global.workspace_manager.get_active_workspace_index();
        if (idx < 0)
            idx = 0;
        if (idx >= FILES.length)
            idx = FILES.length - 1;
        // If fewer than 4 workspaces, still map by index into the palette.
        if (idx >= n)
            idx = n - 1;

        const file = FILES[idx];
        console.log(`x47-ws-walls: workspace ${idx + 1} -> ${file}`);
        const path = GLib.build_filenamev([this._bgDir, file]);
        if (!GLib.file_test(path, GLib.FileTest.IS_REGULAR)) {
            // Fall back to teal if a colour variant is missing.
            const fallback = GLib.build_filenamev([this._bgDir, FILES[0]]);
            if (!GLib.file_test(fallback, GLib.FileTest.IS_REGULAR))
                return;
            this._setUri(`file://${fallback}`);
            return;
        }
        this._setUri(`file://${path}`);
    }

    _setUri(uri) {
        try {
            this._settings.set_string('picture-uri', uri);
            this._settings.set_string('picture-uri-dark', uri);
            this._settings.set_string('picture-options', 'zoom');
        } catch (e) {
            logError(e, 'x47-ws-walls: failed to set wallpaper');
        }
    }
}
