// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';

/// Native view creation failure codes mirrored from the embedder.
@internal
enum CreateViewError {
  timeout(code: -1),
  forceClose(code: -2),
  unhandled(code: null);

  final int? code;

  const CreateViewError({required this.code});

  String message(int token) => switch (this) {
        CreateViewError.timeout => 'Failed to create view, tokenId: $token. Error: timeout',
        CreateViewError.forceClose => 'Failed to create view, tokenId: $token. Error: force close',
        CreateViewError.unhandled => 'Failed to create view, tokenId: $token. Unhandled error',
      };

  static bool isErrorCode(int? viewId) => values.any((e) => e.code == viewId);

  static CreateViewError fromCode(int? code) =>
      values.firstWhere((e) => e.code == code, orElse: () => CreateViewError.unhandled);
}
