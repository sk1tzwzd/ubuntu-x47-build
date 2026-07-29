// X47 amnesia Firefox — use with transparent Tor (do NOT set a SOCKS proxy;
// that would create Tor-over-Tor). These prefs make .onion and clearnet work.
user_pref("network.dns.blockDotOnion", false);
user_pref("network.dns.disableIPv6", true);
user_pref("network.http.http3.enable", false);
user_pref("media.peerconnection.enabled", false);
user_pref("network.proxy.type", 0);
user_pref("browser.startup.homepage", "https://check.torproject.org");
user_pref("startup.homepage_welcome_url", "https://check.torproject.org");
user_pref("network.captive-portal-service.enabled", false);
user_pref("network.connectivity-service.enabled", false);
