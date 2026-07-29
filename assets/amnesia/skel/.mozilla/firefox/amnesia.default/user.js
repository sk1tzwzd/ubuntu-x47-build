// X47 amnesia Firefox — Tor Browser "Safest"-style defaults.
// Traffic is already transparently torified. Do NOT set a SOCKS proxy
// (that would create Tor-over-Tor).

// --- Onion + network (transparent Tor) ---
user_pref("network.dns.blockDotOnion", false);
user_pref("network.dns.disableIPv6", true);
user_pref("network.http.http3.enable", false);
user_pref("network.proxy.type", 0);
user_pref("network.captive-portal-service.enabled", false);
user_pref("network.connectivity-service.enabled", false);
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.predictor.enabled", false);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.IDN_show_punycode", true);

// --- Safest: JavaScript OFF by default ---
user_pref("javascript.enabled", false);

// --- Safest-like: disable active content / rich media ---
user_pref("gfx.font_rendering.opentype_svg.enabled", false);
user_pref("svg.disabled", false); // keep static SVG; no JS anyway
user_pref("mathml.disabled", true);
user_pref("webgl.disabled", true);
user_pref("webgl.enable-webgl2", false);
user_pref("media.webaudio.enabled", false);
user_pref("media.peerconnection.enabled", false);
user_pref("media.autoplay.default", 5); // block all autoplay
user_pref("media.eme.enabled", false);
user_pref("media.gmp-provider.enabled", false);

// --- No service workers / push / caches that look like persistence ---
user_pref("dom.serviceWorkers.enabled", false);
user_pref("dom.push.enabled", false);
user_pref("dom.caches.enabled", false);
user_pref("dom.webnotifications.enabled", false);
user_pref("dom.webnotifications.serviceworker.enabled", false);

// --- Strict privacy / anti-tracking ---
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.pbmode.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
user_pref("privacy.resistFingerprinting", true);
user_pref("privacy.resistFingerprinting.letterboxing", true);
user_pref("privacy.firstparty.isolate", true);
user_pref("privacy.query_stripping.enabled", true);
user_pref("privacy.query_stripping.enabled.pbmode", true);
user_pref("network.cookie.cookieBehavior", 1); // block third-party cookies
user_pref("network.cookie.lifetimePolicy", 2); // expire with session
user_pref("privacy.clearOnShutdown.cookies", true);
user_pref("privacy.clearOnShutdown.cache", true);
user_pref("privacy.clearOnShutdown.downloads", true);
user_pref("privacy.clearOnShutdown.formdata", true);
user_pref("privacy.clearOnShutdown.history", true);
user_pref("privacy.clearOnShutdown.offlineApps", true);
user_pref("privacy.clearOnShutdown.sessions", true);
user_pref("privacy.clearOnShutdown.siteSettings", true);
user_pref("privacy.sanitize.sanitizeOnShutdown", true);
user_pref("browser.cache.disk.enable", false);
user_pref("browser.cache.offline.enable", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.formfill.enable", false);
user_pref("signon.rememberSignons", false);
user_pref("places.history.enabled", false);

// --- HTTPS-only + mixed content ---
user_pref("dom.security.https_only_mode", true);
user_pref("dom.security.https_only_mode_pbm", true);
user_pref("security.mixed_content.block_active_content", true);
user_pref("security.mixed_content.block_display_content", true);

// --- Telemetry / studies off ---
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("browser.discovery.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.ping-centre.telemetry", false);

// --- UI defaults ---
user_pref("browser.startup.homepage", "https://check.torproject.org");
user_pref("startup.homepage_welcome_url", "https://check.torproject.org");
user_pref("browser.startup.page", 1);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("extensions.pocket.enabled", false);
user_pref("geo.enabled", false);
user_pref("browser.geolocation.warning.show", true);
