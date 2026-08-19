import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/screen_retriever/screen_retriever.dart';

void main() {
  group('ScreenRetriever', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('getCursorScreenPoint throws when native is unavailable', () {
      expect(
        () => ScreenRetriever.instance.getCursorScreenPoint(),
        throwsA(isA<Exception>()),
      );
    });

    test('getPrimaryDisplay throws when native is unavailable', () {
      expect(
        () => ScreenRetriever.instance.getPrimaryDisplay(),
        throwsA(isA<Exception>()),
      );
    });

    test('getAllDisplays throws when native is unavailable', () {
      expect(
        () => ScreenRetriever.instance.getAllDisplays(),
        throwsA(isA<Exception>()),
      );
    });

    test('addListener and removeListener manage subscription lifecycle', () {
      final listener = _RecordingScreenListener();
      final retriever = ScreenRetriever.instance;

      retriever.addListener(listener);
      expect(retriever.hasListeners, isTrue);

      retriever.removeListener(listener);
      expect(retriever.hasListeners, isFalse);
    });
  });
}

class _RecordingScreenListener with ScreenListener {
  final events = <String>[];

  @override
  void onScreenEvent(String eventName) => events.add(eventName);
}
