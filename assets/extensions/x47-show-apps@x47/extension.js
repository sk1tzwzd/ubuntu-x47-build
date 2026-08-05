// Top-bar green Ubuntu circle → application grid (no dock required).
import GLib from 'gi://GLib';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export default class X47ShowAppsExtension extends Extension {
    enable() {
        this._button = new St.Button({
            name: 'x47ShowApps',
            style_class: 'panel-button',
            reactive: true,
            can_focus: true,
            track_hover: true,
        });

        const icon = new St.Icon({
            icon_name: 'view-app-grid-symbolic',
            style_class: 'x47-show-apps-icon',
            icon_size: 40,
        });
        this._button.set_child(icon);
        this._button.connect('clicked', () => this._toggleApps());

        // Far left of the top bar.
        Main.panel._leftBox.insert_child_at_index(this._button, 0);
    }

    disable() {
        this._button?.destroy();
        this._button = null;
    }

    _toggleApps() {
        try {
            const overview = Main.overview;
            const controls = overview?._overview?.controls;
            const appsVisible = overview?.visible &&
                controls?.appDisplay?.visible === true;

            if (appsVisible) {
                overview.hide();
                return;
            }

            if (typeof overview.showApps === 'function') {
                overview.showApps();
                return;
            }

            // Fallback for shells without showApps().
            overview.show();
            GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                try {
                    if (controls?.dash?.showAppsButton)
                        controls.dash.showAppsButton.checked = true;
                } catch (_e) { /* ignore */ }
                return GLib.SOURCE_REMOVE;
            });
        } catch (e) {
            console.error(`x47-show-apps: ${e}`);
        }
    }
}
