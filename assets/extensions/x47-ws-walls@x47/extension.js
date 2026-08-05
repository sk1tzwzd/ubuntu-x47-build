// X47 Workspace Walls — every desktop gets its own coloured wallpaper.
//
// GNOME has only ONE global wallpaper, so out of the box the desktop cube
// faces and the overview all show the same image until you land somewhere.
// This extension fixes that everywhere it matters:
//   1. the global wallpaper follows the active workspace,
//   2. each face of the workspace-switch animation (Desktop Cube drag)
//      shows its own workspace's wallpaper,
//   3. the overview's big workspace previews show their own wallpaper,
//   4. the small workspace thumbnails ("tabs" in the selector) are painted
//      with their workspace's wallpaper behind the window clones.
//
// Workspaces 1-4 are preset: teal / pink-on-white / dark-red-on-baby-blue /
// white-on-green. Any workspace beyond 4 gets a stable pseudo-random pick
// from the extra colourways.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import GDesktopEnums from 'gi://GDesktopEnums';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as WorkspaceAnimation from 'resource:///org/gnome/shell/ui/workspaceAnimation.js';
import * as Workspace from 'resource:///org/gnome/shell/ui/workspace.js';
import * as WorkspaceThumbnail from 'resource:///org/gnome/shell/ui/workspaceThumbnail.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const PRESET = [
    'x47-circuit.png',        // workspace 1 — teal duster on dark circuit
    'x47-circuit-pink.png',   // workspace 2 — pink duster on white circuit
    'x47-circuit-blue.png',   // workspace 3 — dark red duster on baby blue
    'x47-circuit-green.png',  // workspace 4 — white duster on green circuit
];
const EXTRA = [
    'x47-circuit-orange.png',
    'x47-circuit-purple.png',
    'x47-circuit-yellow.png',
    'x47-circuit-red.png',
];

export default class X47WsWallsExtension extends Extension {
    enable() {
        this._settings = new Gio.Settings({schema_id: 'org.gnome.desktop.background'});
        this._bgDir = GLib.build_filenamev([GLib.get_user_data_dir(), 'backgrounds']);

        const self = this;

        // 1. Global wallpaper follows the landed workspace.
        this._wsId = global.workspace_manager.connect(
            'active-workspace-changed', () => this._applyGlobal());

        // 2. Workspace-switch animation faces (Desktop Cube reuses these).
        this._origAnimCreateBg =
            WorkspaceAnimation.WorkspaceBackground.prototype._createBackground;
        WorkspaceAnimation.WorkspaceBackground.prototype._createBackground = function () {
            self._origAnimCreateBg.call(this);
            self._retarget(this._bgManager, this._workspace?.index());
        };

        // 3. Overview big workspace previews.
        this._origWsInit = Workspace.Workspace.prototype._init;
        Workspace.Workspace.prototype._init = function (metaWorkspace, ...args) {
            self._origWsInit.call(this, metaWorkspace, ...args);
            if (metaWorkspace)
                self._retarget(this._background?._bgManager, metaWorkspace.index());
        };

        // 4. Small selector thumbnails have no wallpaper at all by default —
        //    paint one under the window clones.
        this._origThumbInit = WorkspaceThumbnail.WorkspaceThumbnail.prototype._init;
        WorkspaceThumbnail.WorkspaceThumbnail.prototype._init =
        function (metaWorkspace, monitorIndex) {
            self._origThumbInit.call(this, metaWorkspace, monitorIndex);
            try {
                const monitor = Main.layoutManager.monitors[monitorIndex];
                const bgActor = new Meta.BackgroundActor({
                    meta_display: global.display,
                    monitor: monitorIndex,
                });
                bgActor.set_size(monitor.width, monitor.height);
                bgActor.content.background =
                    self._makeBackground(metaWorkspace.index());
                this._contents.insert_child_below(bgActor, null);
            } catch (e) {
                console.warn(`x47-ws-walls: thumbnail wallpaper failed: ${e}`);
            }
        };

        // First apply once the session settles.
        this._idle = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._applyGlobal();
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
        if (this._origAnimCreateBg) {
            WorkspaceAnimation.WorkspaceBackground.prototype._createBackground =
                this._origAnimCreateBg;
            this._origAnimCreateBg = null;
        }
        if (this._origWsInit) {
            Workspace.Workspace.prototype._init = this._origWsInit;
            this._origWsInit = null;
        }
        if (this._origThumbInit) {
            WorkspaceThumbnail.WorkspaceThumbnail.prototype._init = this._origThumbInit;
            this._origThumbInit = null;
        }
        this._settings = null;
    }

    // Wallpaper file for a workspace index; extras hashed so each spawned
    // workspace keeps a stable "random" colour.
    _pathFor(idx) {
        let name;
        if (idx < PRESET.length)
            name = PRESET[idx];
        else
            name = EXTRA[((idx * 2654435761) >>> 16) % EXTRA.length];
        const p = GLib.build_filenamev([this._bgDir, name]);
        return GLib.file_test(p, GLib.FileTest.IS_REGULAR)
            ? p
            : GLib.build_filenamev([this._bgDir, PRESET[0]]);
    }

    _makeBackground(idx) {
        const bg = new Meta.Background({meta_display: global.display});
        bg.set_file(Gio.File.new_for_path(this._pathFor(idx)),
            GDesktopEnums.BackgroundStyle.ZOOM);
        return bg;
    }

    // Point an existing BackgroundManager's actor at the workspace's file,
    // and keep it pointed there if the manager swaps actors (it does when the
    // global wallpaper changes mid-animation on landing).
    _retarget(mgr, idx) {
        if (!mgr || idx === undefined || idx === null || idx < 0)
            return;
        const apply = () => {
            const actor = mgr.backgroundActor;
            if (actor?.content)
                actor.content.background = this._makeBackground(idx);
        };
        apply();
        mgr.connect('changed', apply);
    }

    _applyGlobal() {
        if (!this._settings)
            return;
        const idx = global.workspace_manager.get_active_workspace_index();
        const uri = `file://${this._pathFor(Math.max(idx, 0))}`;
        console.log(`x47-ws-walls: workspace ${idx + 1} -> ${uri}`);
        try {
            this._settings.set_string('picture-uri', uri);
            this._settings.set_string('picture-uri-dark', uri);
            this._settings.set_string('picture-options', 'zoom');
        } catch (e) {
            logError(e, 'x47-ws-walls: failed to set wallpaper');
        }
    }
}
