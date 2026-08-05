// X47 Workspace Walls — every desktop gets its own coloured wallpaper.
//
// GNOME has only ONE global wallpaper, so out of the box the desktop cube
// faces and the overview all show the same image until you land somewhere.
// This extension fixes that everywhere it matters:
//   1. the global wallpaper follows the active workspace,
//   2. each face of the workspace-switch animation (Desktop Cube drag)
//      shows its own workspace's wallpaper,
//   3. the overview's big workspace previews show their own wallpaper,
//   4. the small workspace selector tabs get a CSS cover wallpaper that
//      does NOT expand the bar or steal clicks (GNOME 50-safe),
//   5. a "+" control on the selector bar adds a desktop (random colourway).
//
// Workspaces 1-4 are preset colours; extras pick randomly from EXTRA and
// remember the choice. Uses static workspaces so empty faces stay put.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import St from 'gi://St';
import Clutter from 'gi://Clutter';
import GDesktopEnums from 'gi://GDesktopEnums';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as WorkspaceAnimation from 'resource:///org/gnome/shell/ui/workspaceAnimation.js';
import * as Workspace from 'resource:///org/gnome/shell/ui/workspace.js';
import * as WorkspaceThumbnail from 'resource:///org/gnome/shell/ui/workspaceThumbnail.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const PRESET = [
    'x47-circuit.png',        // workspace 1 — teal duster on dark circuit
    'x47-circuit-pink.png',   // workspace 2 — pink duster on white circuit
    'x47-circuit-carbon.png', // workspace 3 — silver duster on carbon circuit
    'x47-circuit-green.png',  // workspace 4 — white duster on green circuit
];
const EXTRA = [
    'x47-circuit-orange.png',
    'x47-circuit-purple.png',
    'x47-circuit-yellow.png',
    'x47-circuit-red.png',
    'x47-circuit-cyan.png',
    'x47-circuit-lime.png',
    'x47-circuit-magenta.png',
    'x47-circuit-slate.png',
];
const FLOOR = 4;
const MAX_WORKSPACES = 16;

export default class X47WsWallsExtension extends Extension {
    enable() {
        this._settings = new Gio.Settings({schema_id: 'org.gnome.desktop.background'});
        this._wmSettings = new Gio.Settings({schema_id: 'org.gnome.desktop.wm.preferences'});
        this._mutterSettings = new Gio.Settings({schema_id: 'org.gnome.mutter'});
        this._bgDir = GLib.build_filenamev([GLib.get_user_data_dir(), 'backgrounds']);
        this._assignments = this._loadAssignments();
        this._addBtn = null;
        this._posIdle = 0;
        this._overviewSignals = [];

        this._ensureFloor();

        const self = this;

        // 1. Global wallpaper follows the landed workspace.
        this._wsId = global.workspace_manager.connect(
            'active-workspace-changed', () => this._applyGlobal());
        this._nWsId = global.workspace_manager.connect(
            'notify::n-workspaces', () => this._queuePositionAddBtn());

        // 2. Workspace-switch animation faces (Desktop Cube reuses these).
        this._origAnimCreateBg =
            WorkspaceAnimation.WorkspaceBackground.prototype._createBackground;
        WorkspaceAnimation.WorkspaceBackground.prototype._createBackground = function () {
            self._origAnimCreateBg.call(this);
            self._retarget(this._bgManager, this._workspace?.index());
        };

        // 2b. Stock-shell fix: _syncStacking assumes every currently-showing
        // window has a clone record, but windows can start showing mid-switch
        // (map/unminimize) — then `record.clone` throws. Same loop, guarded.
        this._origSyncStacking =
            WorkspaceAnimation.WorkspaceGroup.prototype._syncStacking;
        WorkspaceAnimation.WorkspaceGroup.prototype._syncStacking = function () {
            const windowActors = global.get_window_actors().filter(w =>
                this._shouldShowWindow(w.meta_window));
            let lastRecord;
            const bottomActor = this._background ?? null;
            for (const windowActor of windowActors) {
                const record = this._windowRecords.find(
                    r => r.windowActor === windowActor);
                if (!record)
                    continue; // appeared after this group was built
                this.set_child_above_sibling(record.clone,
                    lastRecord ? lastRecord.clone : bottomActor);
                lastRecord = record;
            }
        };

        // 3. Overview big workspace previews.
        this._origWsInit = Workspace.Workspace.prototype._init;
        Workspace.Workspace.prototype._init = function (metaWorkspace, ...args) {
            self._origWsInit.call(this, metaWorkspace, ...args);
            if (metaWorkspace)
                self._retarget(this._background?._bgManager, metaWorkspace.index());
        };

        // 4. Selector tabs — CSS cover background, non-reactive, expands with
        // the thumb only. A full-monitor Meta.BackgroundActor was stretching
        // the bar and eating clicks on GNOME 50.
        this._origThumbInit = WorkspaceThumbnail.WorkspaceThumbnail.prototype._init;
        WorkspaceThumbnail.WorkspaceThumbnail.prototype._init =
        function (metaWorkspace, monitorIndex) {
            self._origThumbInit.call(this, metaWorkspace, monitorIndex);
            try {
                if (!this._contents || !metaWorkspace)
                    return;
                const path = self._pathFor(metaWorkspace.index());
                const uri = GLib.filename_to_uri(path, null);
                const bg = new St.Widget({
                    reactive: false,
                    track_hover: false,
                    can_focus: false,
                    x_expand: true,
                    y_expand: true,
                    x_align: Clutter.ActorAlign.FILL,
                    y_align: Clutter.ActorAlign.FILL,
                });
                bg.set_style(
                    `background-image: url("${uri}");` +
                    'background-size: cover;' +
                    'background-position: center;');
                this._contents.insert_child_below(bg, null);
            } catch (e) {
                console.warn(`x47-ws-walls: thumbnail wallpaper failed: ${e}`);
            }
        };

        // 5. "+" on the workspace selector bar.
        this._createAddButton();
        this._overviewSignals.push(
            Main.overview.connect('showing', () => this._queuePositionAddBtn()));
        this._overviewSignals.push(
            Main.overview.connect('shown', () => this._queuePositionAddBtn()));
        this._overviewSignals.push(
            Main.overview.connect('hiding', () => {
                if (this._addBtn)
                    this._addBtn.hide();
            }));

        // First apply once the session settles.
        this._idle = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._ensureFloor();
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
        if (this._nWsId) {
            global.workspace_manager.disconnect(this._nWsId);
            this._nWsId = 0;
        }
        if (this._idle) {
            GLib.source_remove(this._idle);
            this._idle = 0;
        }
        if (this._posIdle) {
            GLib.source_remove(this._posIdle);
            this._posIdle = 0;
        }
        for (const id of this._overviewSignals)
            Main.overview.disconnect(id);
        this._overviewSignals = [];
        this._destroyAddButton();
        if (this._origAnimCreateBg) {
            WorkspaceAnimation.WorkspaceBackground.prototype._createBackground =
                this._origAnimCreateBg;
            this._origAnimCreateBg = null;
        }
        if (this._origSyncStacking) {
            WorkspaceAnimation.WorkspaceGroup.prototype._syncStacking =
                this._origSyncStacking;
            this._origSyncStacking = null;
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
        this._wmSettings = null;
        this._mutterSettings = null;
    }

    _ensureFloor() {
        try {
            if (this._mutterSettings.get_boolean('dynamic-workspaces'))
                this._mutterSettings.set_boolean('dynamic-workspaces', false);
            const n = this._wmSettings.get_int('num-workspaces');
            if (n < FLOOR)
                this._wmSettings.set_int('num-workspaces', FLOOR);
        } catch (e) {
            console.warn(`x47-ws-walls: ensureFloor failed: ${e}`);
        }
    }

    _createAddButton() {
        if (this._addBtn)
            return;
        const btn = new St.Button({
            style_class: 'x47-add-workspace',
            reactive: true,
            can_focus: true,
            track_hover: true,
            visible: false,
        });
        btn.child = new St.Label({
            text: '+',
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER,
        });
        btn.connect('clicked', () => this._addDesktop());
        // overviewGroup: above wallpaper, aligned with the selector bar.
        Main.layoutManager.overviewGroup.add_child(btn);
        this._addBtn = btn;
    }

    _destroyAddButton() {
        if (!this._addBtn)
            return;
        try {
            Main.layoutManager.overviewGroup.remove_child(this._addBtn);
        } catch (_e) { /* already gone */ }
        this._addBtn.destroy();
        this._addBtn = null;
    }

    _thumbnailsBox() {
        const overview = Main.overview;
        const controls =
            overview?.controls ??
            overview?._overview?.controls ??
            overview?._overview?._controls;
        return controls?._thumbnailsBox ?? null;
    }

    _queuePositionAddBtn() {
        if (this._posIdle)
            return;
        this._posIdle = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._posIdle = 0;
            this._positionAddBtn();
            return GLib.SOURCE_REMOVE;
        });
    }

    _positionAddBtn() {
        if (!this._addBtn)
            return;
        if (!Main.overview.visible) {
            this._addBtn.hide();
            return;
        }
        const box = this._thumbnailsBox();
        if (!box || !box.visible || box.width < 8 || box.height < 8) {
            this._addBtn.hide();
            return;
        }
        try {
            const [bx, by] = box.get_transformed_position();
            const bw = box.get_transformed_size()[0];
            const bh = box.get_transformed_size()[1];
            const size = Math.max(28, Math.min(48, Math.round(bh)));
            const gap = 8;
            this._addBtn.set_size(size, size);
            this._addBtn.set_position(
                Math.round(bx + bw + gap),
                Math.round(by + (bh - size) / 2));
            this._addBtn.show();
            this._addBtn.raise_top();
        } catch (e) {
            console.warn(`x47-ws-walls: position + failed: ${e}`);
            this._addBtn.hide();
        }
    }

    _addDesktop() {
        try {
            this._ensureFloor();
            const n = this._wmSettings.get_int('num-workspaces');
            if (n >= MAX_WORKSPACES)
                return;
            const next = n; // new index after bump
            // Pick a random colourway for the new desktop and remember it.
            this._assignments[String(next)] =
                EXTRA[Math.floor(Math.random() * EXTRA.length)];
            this._saveAssignments();
            this._wmSettings.set_int('num-workspaces', n + 1);
            GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                const wm = global.workspace_manager;
                const idx = wm.n_workspaces - 1;
                const ws = wm.get_workspace_by_index(idx);
                if (ws)
                    ws.activate(global.get_current_time());
                this._applyGlobal();
                this._queuePositionAddBtn();
                return GLib.SOURCE_REMOVE;
            });
        } catch (e) {
            logError(e, 'x47-ws-walls: add desktop failed');
        }
    }

    _pathFor(idx) {
        let name;
        if (idx < PRESET.length) {
            name = PRESET[idx];
        } else {
            const key = String(idx);
            if (!this._assignments[key] || !EXTRA.includes(this._assignments[key])) {
                this._assignments[key] =
                    EXTRA[((idx * 2654435761) >>> 16) % EXTRA.length];
                this._saveAssignments();
            }
            name = this._assignments[key];
        }
        const p = GLib.build_filenamev([this._bgDir, name]);
        return GLib.file_test(p, GLib.FileTest.IS_REGULAR)
            ? p
            : GLib.build_filenamev([this._bgDir, PRESET[0]]);
    }

    _assignmentsFile() {
        return GLib.build_filenamev(
            [GLib.get_user_config_dir(), 'x47-widgets', 'ws-walls.json']);
    }

    _loadAssignments() {
        try {
            const [ok, bytes] = GLib.file_get_contents(this._assignmentsFile());
            if (ok)
                return JSON.parse(new TextDecoder().decode(bytes)) || {};
        } catch (_e) { /* missing / corrupt */ }
        return {};
    }

    _saveAssignments() {
        try {
            const dir = GLib.build_filenamev(
                [GLib.get_user_config_dir(), 'x47-widgets']);
            GLib.mkdir_with_parents(dir, 0o755);
            GLib.file_set_contents(
                this._assignmentsFile(), JSON.stringify(this._assignments));
        } catch (e) {
            console.warn(`x47-ws-walls: save assignments failed: ${e}`);
        }
    }

    _makeBackground(idx) {
        const bg = new Meta.Background({meta_display: global.display});
        bg.set_file(Gio.File.new_for_path(this._pathFor(idx)),
            GDesktopEnums.BackgroundStyle.ZOOM);
        return bg;
    }

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
