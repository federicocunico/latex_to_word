import 'dart:io';
import 'package:path/path.dart' as p;

/// Resolves the path to the pandoc binary.
///
/// Resolution order:
///   1. `<exe_dir>/data/pandoc/pandoc[.exe]`  — bundled at build time
///   2. `<appSupportDir>/pandoc/pandoc[.exe]` — downloaded by the app
///   3. `pandoc` on the system PATH            — convenient for development
class PandocResolver {
  static String? _appSupportDir;

  /// Must be called once at startup with the result of
  /// `getApplicationSupportDirectory().path` before any conversion.
  static void configure(String appSupportDir) {
    _appSupportDir = appSupportDir;
  }

  /// Returns the pandoc binary path, or `null` if not found anywhere.
  static String? resolveOrNull() {
    final bin = Platform.isWindows ? 'pandoc.exe' : 'pandoc';

    // 1. Bundled next to the executable
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final bundled = p.join(exeDir, 'data', 'pandoc', bin);
    if (File(bundled).existsSync()) return bundled;

    // 2. Downloaded into application support directory
    if (_appSupportDir != null) {
      final appBin = p.join(_appSupportDir!, 'pandoc', bin);
      if (File(appBin).existsSync()) return appBin;
    }

    // 3. System PATH (development fallback)
    return _findOnPath(bin);
  }

  /// Returns the pandoc binary path.
  ///
  /// Throws [StateError] if pandoc cannot be found.
  static String resolve() {
    final path = resolveOrNull();
    if (path != null) return path;
    throw StateError(
      'pandoc binary not found. '
      'Launch the app once to download it automatically.',
    );
  }

  /// Path where the app will save the downloaded pandoc binary.
  static String? downloadedBinaryPath() {
    if (_appSupportDir == null) return null;
    final bin = Platform.isWindows ? 'pandoc.exe' : 'pandoc';
    return p.join(_appSupportDir!, 'pandoc', bin);
  }

  static String? _findOnPath(String name) {
    try {
      final result = Process.runSync(
        Platform.isWindows ? 'where' : 'which',
        [name],
      );
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first.trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}
    return null;
  }
}
