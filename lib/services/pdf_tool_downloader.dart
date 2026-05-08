import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Downloads poppler for Windows (pdftoppm + required DLLs) from the
/// oschwartz10612/poppler-windows GitHub releases into the app support dir.
///
/// On macOS / Linux poppler is expected to be installed via the system package
/// manager; this class is a no-op on those platforms.
class PdfToolDownloader {
  static const _apiUrl =
      'https://api.github.com/repos/oschwartz10612/poppler-windows/releases/latest';

  static String? _appSupportDir;

  static void configure(String appSupportDir) {
    _appSupportDir = appSupportDir;
  }

  /// Returns `true` if a downloaded pdftoppm binary is already present.
  static bool isAvailable() => resolvedBinDir() != null;

  /// Returns the path to the poppler `bin/` directory if it was already
  /// downloaded, or `null` if the download has not happened yet.
  static String? resolvedBinDir() {
    if (_appSupportDir == null) return null;
    final dir = Directory(p.join(_appSupportDir!, 'poppler', 'bin'));
    final exe = Platform.isWindows ? 'pdftoppm.exe' : 'pdftoppm';
    if (File(p.join(dir.path, exe)).existsSync()) return dir.path;
    return null;
  }

  /// Downloads the latest poppler-windows release and extracts it.
  ///
  /// [onStatus]   — short human-readable message.
  /// [onProgress] — 0.0–1.0 fraction; -1 when content-length is unknown.
  ///
  /// Returns the path to the populated `bin/` directory.
  /// Throws on network failure or extraction errors.
  static Future<String> download({
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Auto-download is only supported on Windows. '
        'Install poppler (pdftoppm) via your system package manager.',
      );
    }

    final dir = _appSupportDir;
    if (dir == null) {
      throw StateError(
        'PdfToolDownloader not configured — call configure() first.',
      );
    }

    onStatus?.call('Fetching latest poppler release info…');
    final (version, assetUrl) = await _fetchLatestRelease();

    final binDir = Directory(p.join(dir, 'poppler', 'bin'));
    await binDir.create(recursive: true);

    final tmpFile = File(p.join(dir, '_poppler_tmp.zip'));
    try {
      onStatus?.call('Downloading poppler $version (~25 MB)…');
      await _downloadFile(assetUrl, tmpFile, onProgress);

      onStatus?.call('Extracting poppler…');
      await _extract(tmpFile, binDir.path);

      onStatus?.call('poppler ready.');
      return binDir.path;
    } finally {
      if (tmpFile.existsSync()) await tmpFile.delete();
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  static Future<(String version, String assetUrl)> _fetchLatestRelease() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(_apiUrl));
      request.headers
        ..set('Accept', 'application/vnd.github+json')
        ..set('User-Agent', 'latex-to-word-app');

      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('GitHub API error: HTTP ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tagName = json['tag_name'] as String? ?? 'unknown';
      final assets = json['assets'] as List<dynamic>? ?? [];

      for (final asset in assets) {
        final name = (asset as Map<String, dynamic>)['name'] as String? ?? '';
        final url = asset['browser_download_url'] as String? ?? '';
        if (name.endsWith('.zip') && url.isNotEmpty) {
          return (tagName, url);
        }
      }
      throw Exception('No ZIP asset found in poppler-windows release.');
    } finally {
      client.close();
    }
  }

  static Future<void> _downloadFile(
    String url,
    File dest,
    void Function(double)? onProgress,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'latex-to-word-app');
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      final total = response.contentLength;
      var received = 0;
      final sink = dest.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total > 0 ? received / total : -1);
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// Extracts all files from `*/Library/bin/*` inside the ZIP to [binDirPath].
  static Future<void> _extract(File archive, String binDirPath) async {
    final bytes = await archive.readAsBytes();
    final decoded = ZipDecoder().decodeBytes(bytes);

    var count = 0;
    for (final entry in decoded) {
      if (!entry.isFile) continue;

      // Normalise path separators
      final normalized = entry.name.replaceAll('\\', '/');
      // Match entries inside a Library/bin/ directory
      final binMarker = '/Library/bin/';
      final idx = normalized.indexOf(binMarker);
      if (idx == -1) continue;

      final fileName = normalized.substring(idx + binMarker.length);
      if (fileName.isEmpty || fileName.contains('/')) continue; // skip nested

      final dest = File(p.join(binDirPath, fileName));
      await dest.writeAsBytes(entry.content as List<int>);
      count++;
    }

    if (count == 0) {
      throw Exception(
        'No files found in Library/bin/ inside the poppler archive. '
        'The release format may have changed.',
      );
    }
  }
}
