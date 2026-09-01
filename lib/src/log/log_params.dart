/// File-logger settings for `MultiAppConfig.logParams`.
///
/// When [enable] is true, diagnostics are appended to `mvd.log`:
///
/// * macOS: `~/Library/Caches/multiview_desktop`
/// * Windows: `%LOCALAPPDATA%/multiview_desktop/logs`
/// * Linux: `${XDG_CACHE_HOME:-~/.cache}/multiview_desktop`
class LogParams {
  /// When false, the file logger is a no-op.
  final bool enable;

  /// Maximum size of `mvd.log` in kilobytes. On overflow the current file is
  /// renamed to `mvd.log.prev` and a new file is started.
  final int sizeKb;

  const LogParams({
    this.enable = false,
    this.sizeKb = 1024,
  });
}
