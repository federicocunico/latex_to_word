import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'extractor.dart';
import 'converter.dart';

enum PipelineStep { extract, convert, done, error }

class PipelineProgress {
  final PipelineStep step;
  final String message;

  const PipelineProgress(this.step, this.message);
}

class PipelineOutput {
  final File docxFile;
  final String pandocLog;

  const PipelineOutput({required this.docxFile, required this.pandocLog});
}

/// Orchestrates the end-to-end conversion:
///   ZIP → extract main.tex → pandoc → DOCX
///
/// Ports logic from backend/services/pipeline.py (simplified: no LaTeX
/// compilation, no LibreOffice conversion, no similarity checking).
class ConversionPipeline {
  /// Runs the full pipeline on [zipFile].
  ///
  /// Emits [PipelineProgress] updates via [onProgress].
  /// Returns a [PipelineOutput] on success.
  /// Always cleans up the temporary work directory.
  static Future<PipelineOutput> run(
    File zipFile, {
    void Function(PipelineProgress)? onProgress,
  }) async {
    final tempBase = await getTemporaryDirectory();
    final jobId = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final workDir = Directory(p.join(tempBase.path, 'latex_convert_$jobId'));
    final outDir = Directory(p.join(tempBase.path, 'latex_out_$jobId'));

    void progress(PipelineStep step, String message) {
      onProgress?.call(PipelineProgress(step, message));
    }

    try {
      progress(PipelineStep.extract, 'Extracting ZIP archive…');
      final extracted = await ZipExtractor.extract(zipFile, workDir);

      progress(PipelineStep.convert, 'Converting LaTeX → DOCX with pandoc…');
      final converted = await PandocConverter.convert(
        extracted.mainTex,
        outDir,
      );

      progress(PipelineStep.done, 'Conversion complete.');
      return PipelineOutput(
        docxFile: converted.docxFile,
        pandocLog: converted.log,
      );
    } finally {
      // Clean up temp work dir; keep outDir until caller saves the file
      if (await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
    }
  }

  /// Cleans up the output directory after the caller has saved the DOCX.
  static Future<void> cleanup(File docxFile) async {
    final outDir = docxFile.parent;
    if (await outDir.exists()) {
      await outDir.delete(recursive: true);
    }
  }
}
