// Click a notification banner → focus/open the app that needs attention.
// GNOME already tries this, but many snaps/apps leave source.app null or set a
// default action that only dismisses the banner. We reinforce activation.
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export default class X47NotifActivateExtension extends Extension {
    enable() {
        this._tray = Main.messageTray;
        this._sourceHandlers = new Map(); // source -> [signal ids]
        // Map, not WeakMap: disable() must be able to walk and disconnect
        // these, otherwise stale handlers fire into a disabled extension.
        this._notifHandlers = new Map(); // notification -> signal id
        this._wrappedSources = [];
        this._trayHandlers = [];

        this._trayHandlers.push(
            this._tray.connect('source-added', (_t, source) => this._hookSource(source)));

        for (const source of this._tray.getSources())
            this._hookSource(source);
    }

    disable() {
        for (const id of this._trayHandlers)
            this._tray.disconnect(id);
        this._trayHandlers = [];

        for (const [source, ids] of this._sourceHandlers) {
            for (const id of ids) {
                try {
                    source.disconnect(id);
                } catch (_e) { /* destroyed */ }
            }
        }
        this._sourceHandlers.clear();

        for (const [notification, id] of this._notifHandlers) {
            try {
                notification.disconnect(id);
            } catch (_e) { /* destroyed */ }
        }
        this._notifHandlers.clear();

        for (const source of this._wrappedSources) {
            try {
                if (source._x47OrigOpenApp) {
                    source.openApp = source._x47OrigOpenApp;
                    delete source._x47OrigOpenApp;
                    delete source._x47OpenAppWrapped;
                }
                if (source._x47OrigOpen) {
                    source.open = source._x47OrigOpen;
                    delete source._x47OrigOpen;
                    delete source._x47OpenWrapped;
                }
            } catch (_e) { /* destroyed */ }
        }
        this._wrappedSources = [];
        this._tray = null;
    }

    _hookSource(source) {
        if (!source || this._sourceHandlers.has(source))
            return;

        const ids = [];
        ids.push(source.connect('notification-added', (_s, notification) => {
            this._hookNotification(notification, source);
        }));
        ids.push(source.connect('destroy', () => {
            this._sourceHandlers.delete(source);
        }));

        for (const notification of source.notifications || [])
            this._hookNotification(notification, source);

        // Reinforce Source.open / openApp when the shell leaves app unset.
        if (typeof source.openApp === 'function' && !source._x47OpenAppWrapped) {
            const orig = source.openApp;
            const bound = orig.bind(source);
            source.openApp = () => {
                bound();
                this._forceActivate(source);
            };
            source._x47OrigOpenApp = orig;
            source._x47OpenAppWrapped = true;
            this._wrappedSources.push(source);
        } else if (typeof source.open === 'function' && !source._x47OpenWrapped) {
            const orig = source.open;
            const bound = orig.bind(source);
            source.open = () => {
                bound();
                this._forceActivate(source);
            };
            source._x47OrigOpen = orig;
            source._x47OpenWrapped = true;
            this._wrappedSources.push(source);
        }

        this._sourceHandlers.set(source, ids);
    }

    _hookNotification(notification, source) {
        if (!notification || this._notifHandlers.has(notification))
            return;

        const id = notification.connect('activated', () => {
            // Run after GNOME's own handlers so we can recover if they no-op.
            GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
                this._forceActivate(source || notification.source);
                return GLib.SOURCE_REMOVE;
            });
        });
        this._notifHandlers.set(notification, id);
        try {
            notification.connect('destroy', () => {
                this._notifHandlers.delete(notification);
            });
        } catch (_e) { /* no destroy signal on this shell version */ }
    }

    _forceActivate(source) {
        if (!source)
            return;

        try {
            Main.overview?.hide?.();
            Main.panel?.closeCalendar?.();
        } catch (_e) { /* ignore */ }

        const appSystem = Shell.AppSystem.get_default();
        let app = source.app ?? source._app ?? null;

        if (!app && source._appId)
            app = appSystem.lookup_app(source._appId);

        // Desktop id variants used by snaps (firefox_firefox.desktop, etc.)
        if (!app && typeof source.appId === 'string')
            app = appSystem.lookup_app(source.appId);

        if (!app && source.title) {
            const want = String(source.title).toLowerCase();
            app = appSystem.get_running().find(a => {
                const name = (a.get_name() || '').toLowerCase();
                const id = (a.get_id() || '').toLowerCase();
                return name === want || id.startsWith(want.replace(/\s+/g, '-')) ||
                    id.includes(want.replace(/\s+/g, ''));
            }) || null;
        }

        if (app) {
            const wins = app.get_windows();
            if (wins.length > 0)
                Main.activateWindow(wins[0]);
            else
                app.activate();
            return;
        }

        // Last resort: raise a window whose title/class matches the source name.
        const needle = String(source.title || source._appName || '').toLowerCase();
        if (!needle)
            return;

        const compact = needle.replace(/\s+/g, '');
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (!win || win.is_skip_taskbar?.())
                continue;
            const title = (win.get_title() || '').toLowerCase();
            const wm = (win.get_wm_class() || '').toLowerCase();
            const instance = (win.get_wm_class_instance?.() || '').toLowerCase();
            if (title.includes(needle) || wm.includes(compact) || instance.includes(compact)) {
                Main.activateWindow(win);
                return;
            }
        }
    }
}
