import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0.3.8's installed web app came up blank with the network unplugged: Chrome
/// loads `canvaskit/chromium/*`, and the precache list only had the plain
/// canvaskit pair, so the cold boot failed on a module it never stored. Keep the
/// files a cold offline boot needs pinned to the worker's precache list.
void main() {
  test('the service worker precaches what a cold offline boot needs', () {
    final worker = File('web/service_worker.js').readAsStringSync();
    const required = [
      './index.html',
      './manifest.json',
      './version.json',
      './flutter_bootstrap.js',
      './main.dart.js',
      './canvaskit/canvaskit.js',
      './canvaskit/canvaskit.wasm',
      './canvaskit/chromium/canvaskit.js',
      './canvaskit/chromium/canvaskit.wasm',
      './assets/AssetManifest.bin.json',
      './assets/FontManifest.json',
      './assets/fonts/MaterialIcons-Regular.otf',
    ];
    for (final file in required) {
      expect(worker, contains("'$file'"), reason: '$file must be precached');
    }
  });
}
