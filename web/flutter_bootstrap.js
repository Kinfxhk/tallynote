{{flutter_js}}
{{flutter_build_config}}

// Flutter's generated service worker unregisters itself on activate, which
// would leave the app needing the network on every open. Tallynote registers
// its own worker in index.html, so the loader must not install a second one.
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: null,
  },
});
