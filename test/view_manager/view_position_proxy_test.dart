import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lifecycle/lifecycle_test_harness.dart';

void main() {
  group('ViewPositionProxy size guards', () {
    late LifecycleTestHarness harness;

    setUp(() {
      harness = LifecycleTestHarness();
      harness.seedWindow(1);
      harness.ffi.frames[1] = const Rect.fromLTWH(10, 20, 800, 450);
      harness.ffi.setMinSize(1, size: const Size(200, 200));
      harness.ffi.setMaxSize(1, size: const Size(2000, 2000));
    });

    test('setPhysicalBounds writes device-pixel frame and rejects empty rects', () {
      harness.ffi.physicalFrames[1] = const Rect.fromLTWH(10, 20, 800, 450);

      expect(harness.proxies.position.setPhysicalBounds(1, Rect.zero), isFalse);
      expect(
        harness.proxies.position.setPhysicalBounds(1, const Rect.fromLTWH(1920, 0, 2560, 1440)),
        isTrue,
      );
      expect(harness.proxies.position.getPhysicalBounds(1), const Rect.fromLTWH(1920, 0, 2560, 1440));
    });

    test('setSize / setFrameBounds reject a size that breaks only one axis', () async {
      expect(await harness.proxies.position.setSize(1, const Size(100, 500)), isFalse);
      expect(harness.proxies.position.setFrameBounds(1, const Rect.fromLTWH(0, 0, 100, 500)), isFalse);
      expect(await harness.proxies.position.setSize(1, const Size(400, 400)), isTrue);
    });

    test('setMinimumSize rejects a min that exceeds max on one axis', () {
      expect(harness.proxies.position.setMinimumSize(1, const Size(2500, 100)), isFalse);
      expect(harness.ffi.getMinSize(1), const Size(200, 200));
    });

    test('setMin / setMax are locked while aspect ratio is set and restore after clear', () async {
      expect(harness.proxies.position.getAspectRatio(1), 0);
      expect(await harness.proxies.position.setAspectRatio(1, 16 / 9), isTrue);
      expect(harness.proxies.position.getAspectRatio(1), 16 / 9);

      expect(harness.proxies.position.setMinimumSize(1, const Size(300, 300)), isFalse);
      expect(harness.proxies.position.setMaximumSize(1, const Size(1800, 1800)), isFalse);

      expect(await harness.proxies.position.setAspectRatio(1, 0), isTrue);
      expect(harness.proxies.position.getAspectRatio(1), 0);

      expect(harness.ffi.getMinSize(1), const Size(200, 200));
      expect(harness.ffi.getMaxSize(1), const Size(2000, 2000));
      expect(harness.proxies.position.setMinimumSize(1, const Size(300, 300)), isTrue);
      expect(harness.ffi.getMinSize(1), const Size(300, 300));
    });
  });
}
