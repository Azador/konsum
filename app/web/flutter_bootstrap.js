{{flutter_js}}
{{flutter_build_config}}

// Eigener Service Worker statt des (abgekündigten) von Flutter: hält die
// App für den Offline-Betrieb vor, siehe konsum_sw.js.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('konsum_sw.js').catch((e) =>
    console.warn('Service Worker nicht registriert:', e));
}

_flutter.loader.load();
