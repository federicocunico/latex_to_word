import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'pandoc_resolver.dart';

/// Downloads and extracts the pandoc binary from the official GitHub releases.
///
/// The binary is stored at the path returned by
/// [PandocResolver.downloadedBinaryPath].
class PandocDownloader {
  static const _apiUrl =
      'https://api.github.com/repos/jgm/pandoc/releases/latest';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns `true` if pandoc is already available (bundled or downloaded).
  static bool isAvailable() => PandocResolver.resolveOrNull() != null;

  /// Downloads pandoc, reporting progress and status through the callbacks.
  ///
  /// [onStatus]   — short human-readable status string.
  /// [onProgress] — 0.0–1.0 download fraction; -1 if content-length unknown.
  ///
  /// Returns the path to the extracted binary on success.
  /// Throws on network failure or extraction errors.
  static Future<String> download({
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    final destPath = PandocResolver.downloadedBinaryPath();
    if (destPath == null) {
      throw StateError(
        'PandocResolver not configured. Call PandocResolver.configure() first.',
      );
    }

    onStatus?.call('Fetching latest pandoc version…');
    final version = await _fetchLatestVersion();

    final url = _releaseUrl(version);
    final baseDir = File(destPath).parent;
    await baseDir.create(recursive: true);

    final tmpFile = File(p.join(baseDir.path, '_pandoc_download_tmp'));

    try {
      onStatus?.call('Downloading pandoc $version…');
      await _downloadFile(url, tmpFile, onProgress);

      onStatus?.call('Extracting…');
      await _extract(tmpFile, destPath);

      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', destPath]);
      }

      onStatus?.call('pandoc $version ready.');
      return destPath;
    } finally {
      if (tmpFile.existsSync()) await tmpFile.delete();
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  static Future<String> _fetchLatestVersion() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

    try {
      final request = await client.getUrl(Uri.parse(_apiUrl));
      request.headers
        ..set('Accept', 'application/vnd.github+json')
        ..set('User-Agent', 'latex-to-word-app');

      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception(
          'GitHub API error: HTTP ${response.statusCode}',
        );
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tagName = json['tag_name'] as String?;
      if (tagName == null || tagName.isEmpty) {
        throw Exception('Could not parse pandoc version from GitHub API.');
      }
      return tagName;
    } finally {
      client.close();
    }
  }

  static String _releaseUrl(String version) {
    if (Platform.isWindows) {
      return 'https://github.com/jgm/pandoc/releases/download/'
          '$version/pandoc-$version-windows-x86_64.zip';
    }
    if (Platform.isMacOS) {
      final arch = _macArch();
      final suffix = arch == 'arm64'
          ? 'arm64-macOS.zip'
          : 'x86_64-macOS.zip';
      return 'https://github.com/jgm/pandoc/releases/download/'
          '$version/pandoc-$version-$suffix';
    }
    // Linux
    return 'https://github.com/jgm/pandoc/releases/download/'
        '$version/pandoc-$version-linux-amd64.tar.gz';
  }

  static String _macArch() {
    try {
      final r = Process.runSync('uname', ['-m']);
      return (r.stdout as String).trim();
    } catch (_) {
      return 'x86_64';
    }
  }

  static Future<void> _downloadFile(
    String url,
    File dest,
    void Function(double)? onProgress,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'latex-to-word-app');
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      final total = response.contentLength; // -1 if unknown
      var received = 0;
      final sink = dest.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call(received / total);
        } else {
          onProgress?.call(-1);
        }
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  static Future<void> _extract(File archive, String outBinaryPath) async {
    final binaryName = p.basename(outBinaryPath); // pandoc or pandoc.exe

    final bytes = await archive.readAsBytes();
    final Archive decoded;

    if (archive.path.endsWith('.tar.gz')) {
      decoded = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    } else {
      decoded = ZipDecoder().decodeBytes(bytes);
    }

    for (final entry in decoded) {
      if (entry.isFile && p.basename(entry.name) == binaryName) {
        await File(outBinaryPath).writeAsBytes(entry.content as List<int>);
        return;
      }
    }

    throw Exception(
      'pandoc binary ("$binaryName") not found in the downloaded archive.',
    );
  }
}
