import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/lifecycle/create_view_error.dart';
import 'package:multiview_desktop/src/lifecycle/view_create_completer.dart';

void main() {
  group('CreateViewError', () {
    test('codes and messages', () {
      expect(CreateViewError.timeout.code, -1);
      expect(CreateViewError.forceClose.code, -2);
      expect(CreateViewError.unhandled.code, isNull);

      expect(CreateViewError.isErrorCode(-1), isTrue);
      expect(CreateViewError.isErrorCode(-2), isTrue);
      expect(CreateViewError.isErrorCode(5), isFalse);
      // `unhandled.code` is null, so null matches that sentinel.
      expect(CreateViewError.isErrorCode(null), isTrue);

      expect(CreateViewError.fromCode(-1), CreateViewError.timeout);
      expect(CreateViewError.fromCode(-2), CreateViewError.forceClose);
      expect(CreateViewError.fromCode(99), CreateViewError.unhandled);

      expect(CreateViewError.timeout.message(3), contains('tokenId: 3'));
      expect(CreateViewError.timeout.message(3), contains('timeout'));
      expect(CreateViewError.forceClose.message(1), contains('force close'));
      expect(CreateViewError.unhandled.message(2), contains('Unhandled'));
    });
  });

  group('ViewCreateCompleter', () {
    test('window and dialog factories', () async {
      final window = ViewCreateCompleter.window(1, parentId: null);
      expect(window.token, 1);
      expect(window.isDialog, isFalse);
      expect(window.parentId, isNull);
      expect(window.isCompleted, isFalse);

      final dialog = ViewCreateCompleter.dialog(2, parentId: 1);
      expect(dialog.isDialog, isTrue);
      expect(dialog.parentId, 1);

      window.complete(42);
      expect(window.isCompleted, isTrue);
      expect(await window.future, 42);
    });
  });
}
