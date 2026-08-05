// X47 amnesia Firefox — Tor Browser "Safest"-style defaults.
// System nftables already kill-switches / transparently torifies anon's UID.
// SOCKS here points at the *local* Tor SOCKSPort (127.0.0.1:9050). Localhost
// is exempt from the TransPort redirect, so this is NOT Tor-over-Tor — it
// makes Settings → Network show a Tor proxy and sends DNS through SOCKS.

// --- Onion + network (local Tor SOCKS + transparent fallback for other apps) ---
user_pref("network.dns.blockDotOnion", false);
user_pref("network.dns.disableIPv6", true);
user_pref("network.http.http3.enable", false);
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "127.0.0.1");
user_pref("network.proxy.socks_port", 9050);
user_pref("network.proxy.socks_remote_dns", true);
user_pref("network.proxy.socks_version", 5);
user_pref("network.proxy.no_proxies_on", "localhost, 127.0.0.1");
user_pref("network.proxy.share_proxy_settings", false);
// Do not fall back to direct clearnet if Tor SOCKS blips.
user_pref("network.proxy.failover_direct", false);
// Empty HTTP/SSL proxy fields — SOCKS handles every protocol (incl. .onion).
user_pref("network.proxy.http", "");
user_pref("network.proxy.http_port", 0);
user_pref("network.proxy.ssl", "");
user_pref("network.proxy.ssl_port", 0);
user_pref("network.captive-portal-service.enabled", false);
user_pref("network.connectivity-service.enabled", false);
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.predictor.enabled", false);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.IDN_show_punycode", true);
// DoH hard-off: DNS MUST resolve through Tor, never a direct HTTPS resolver.
user_pref("network.trr.mode", 5);
user_pref("network.trr.uri", "");

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

// --- HTTPS / mixed content ---
// HTTPS-Only + javascript.enabled=false traps HTTP .onion sites: the
// "Continue to HTTP site" interstitial needs JS, so onions look dead.
// Prefer allowing plain HTTP onions; mixed active content stays blocked.
user_pref("dom.security.https_only_mode", false);
user_pref("dom.security.https_only_mode_pbm", false);
user_pref("dom.security.https_only_mode_ever_enabled", false);
user_pref("dom.security.https_only_mode_ever_enabled_pbm", false);
user_pref("security.mixed_content.block_active_content", true);
user_pref("security.mixed_content.block_display_content", true);
// Many onion TLS stacks fail "safe negotiation"; Tor Browser does not force this.
user_pref("security.ssl.require_safe_negotiation", false);

// --- Extra leak / fingerprint surface reduction ---
user_pref("beacon.enabled", false);
user_pref("dom.battery.enabled", false);
user_pref("network.http.referer.XOriginPolicy", 2);
user_pref("network.http.referer.XOriginTrimmingPolicy", 2);

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
// API JSON works with JS disabled (Safest); the HTML check page does not.
user_pref("browser.startup.homepage", "https://check.torproject.org/api/ip");
user_pref("startup.homepage_welcome_url", "https://check.torproject.org/api/ip");
user_pref("browser.startup.page", 1);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("extensions.pocket.enabled", false);
user_pref("geo.enabled", false);
user_pref("browser.geolocation.warning.show", true);
