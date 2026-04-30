import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:latex_to_word_app/services/extractor.dart';
import 'package:latex_to_word_app/services/pdf_image_preprocessor.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pdf_e2e_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('PDF image e2e (testlatex.zip)', () {
    test('converts PDF images to PNG using real tools', () async {
      final zipFile = File(p.join(Directory.current.path, 'testlatex.zip'));
      expect(zipFile.existsSync(), isTrue, reason: 'testlatex.zip must exist');

      final extracted = await ZipExtractor.extract(zipFile, tempDir);
      final result = await PdfImagePreprocessor.prepareForDocx(
        extracted.mainTex,
      );

      expect(
        result.convertedImages,
        greaterThan(0),
        reason:
            'Expected at least one PDF converted to PNG. '
            'Warnings: ${result.warnings}',
      );

      // Verify the PNG files actually exist on disk
      final pngFiles = <File>[];
      await for (final entity in tempDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('__pandoc.png')) {
          pngFiles.add(entity);
        }
      }
      expect(
        pngFiles.length,
        equals(result.convertedImages),
        reason: 'Number of PNG files on disk should match convertedImages count',
      );

      // Verify the tex files now reference the PNG paths
      final figureArchTex = File(
        p.join(tempDir.path, 'figures', 'figure_architecture.tex'),
      );
      if (figureArchTex.existsSync()) {
        final content = await figureArchTex.readAsString();
        expect(
          content,
          contains('architecture__pandoc.png'),
          reason: 'figure_architecture.tex should reference the converted PNG',
        );
        expect(
          content,
          isNot(contains('architecture.pdf')),
          reason: 'figure_architecture.tex should no longer reference the original PDF',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
