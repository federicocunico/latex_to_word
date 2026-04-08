import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'services/pandoc_downloader.dart';
import 'services/pandoc_resolver.dart';
import 'services/pipeline.dart';

enum PandocStatus { checking, available, notFound, downloading, downloadFailed }

enum AppStatus { idle, extracting, converting, done, error }

class ConverterState extends ChangeNotifier {
  // ── pandoc availability ───────────────────────────────────────────────────
  PandocStatus _pandocStatus = PandocStatus.checking;
  double _downloadProgress = 0; // 0.0–1.0, or -1 for indeterminate
  String _downloadStatusText = '';
  String _downloadError = '';

  PandocStatus get pandocStatus => _pandocStatus;
  double get downloadProgress => _downloadProgress;
  String get downloadStatusText => _downloadStatusText;
  String get downloadError => _downloadError;

  // ── conversion ────────────────────────────────────────────────────────────
  AppStatus _status = AppStatus.idle;
  String _statusMessage = '';
  String _pandocLog = '';
  String _errorMessage = '';
  File? _resultDocx;
  bool _isDragOver = false;
  String? _selectedCslStyle;

  AppStatus get status => _status;
  String get statusMessage => _statusMessage;
  String get pandocLog => _pandocLog;
  String get errorMessage => _errorMessage;
  File? get resultDocx => _resultDocx;
  bool get isDragOver => _isDragOver;
  String? get selectedCslStyle => _selectedCslStyle;

  bool get isProcessing =>
      _status == AppStatus.extracting || _status == AppStatus.converting;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  /// Call once after the widget tree is built to check pandoc availability.
  Future<void> init() async {
    final appSupport = await getApplicationSupportDirectory();
    PandocResolver.configure(appSupport.path);

    _pandocStatus = PandocDownloader.isAvailable()
        ? PandocStatus.available
        : PandocStatus.notFound;
    notifyListeners();
  }

  /// Download pandoc from GitHub releases into the app support directory.
  Future<void> downloadPandoc() async {
    if (_pandocStatus == PandocStatus.downloading) return;

    _pandocStatus = PandocStatus.downloading;
    _downloadProgress = 0;
    _downloadStatusText = '';
    _downloadError = '';
    notifyListeners();

    try {
      await PandocDownloader.download(
        onStatus: (msg) {
          _downloadStatusText = msg;
          notifyListeners();
        },
        onProgress: (fraction) {
          _downloadProgress = fraction;
          notifyListeners();
        },
      );
      _pandocStatus = PandocStatus.available;
    } catch (e) {
      _pandocStatus = PandocStatus.downloadFailed;
      _downloadError = e.toString();
    }
    notifyListeners();
  }

  // ── conversion ────────────────────────────────────────────────────────────

  void setDragOver(bool value) {
    if (_isDragOver == value) return;
    _isDragOver = value;
    notifyListeners();
  }

  void setCslStyle(String? style) {
    if (_selectedCslStyle == style) return;
    _selectedCslStyle = style;
    notifyListeners();
  }

  Future<void> startConversion(File zipFile) async {
    if (isProcessing) return;

    _status = AppStatus.extracting;
    _statusMessage = 'Extracting ZIP archive…';
    _pandocLog = '';
    _errorMessage = '';
    _resultDocx = null;
    notifyListeners();

    try {
      final output = await ConversionPipeline.run(
        zipFile,
        cslOverride: _selectedCslStyle,
        onProgress: (progress) {
          switch (progress.step) {
            case PipelineStep.extract:
              _status = AppStatus.extracting;
            case PipelineStep.convert:
              _status = AppStatus.converting;
            case PipelineStep.done:
              _status = AppStatus.done;
            case PipelineStep.error:
              _status = AppStatus.error;
          }
          _statusMessage = progress.message;
          notifyListeners();
        },
      );

      _status = AppStatus.done;
      _statusMessage = 'Conversion complete.';
      _pandocLog = output.pandocLog;
      _resultDocx = output.docxFile;
    } catch (e) {
      _status = AppStatus.error;
      _errorMessage = e.toString();
      _statusMessage = 'Conversion failed.';
    }

    notifyListeners();
  }

  Future<void> cleanupResult() async {
    if (_resultDocx != null) {
      await ConversionPipeline.cleanup(_resultDocx!);
      _resultDocx = null;
    }
  }

  void reset() {
    cleanupResult();
    _status = AppStatus.idle;
    _statusMessage = '';
    _pandocLog = '';
    _errorMessage = '';
    _resultDocx = null;
    _isDragOver = false;
    notifyListeners();
  }
}
