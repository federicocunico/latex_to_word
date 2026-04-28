import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:latex_to_word_app/services/pdf_image_preprocessor.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pdf_preprocessor_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('PdfImagePreprocessor', () {
    test(
      'rewrites includegraphics path when .pdf extension is explicit',
      () async {
        final imagesDir = Directory(p.join(tempDir.path, 'images'))
          ..createSync();
        final pdf = File(p.join(imagesDir.path, 'figure.pdf'));
        pdf.writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);

        final mainTex = File(p.join(tempDir.path, 'main.tex'));
        mainTex.writeAsStringSync(
          r'\documentclass{article}\begin{document}\includegraphics{images/figure.pdf}\end{document}',
        );

        final result = await PdfImagePreprocessor.prepareForDocx(
          mainTex,
          converter: (inputPdf, outputPng) async {
            await outputPng.writeAsString('PNG');
            return true;
          },
        );

        final rewritten = await mainTex.readAsString();
        expect(rewritten, contains('images/figure__pandoc.png'));
        expect(result.convertedImages, 1);
        expect(result.rewrittenFiles, 1);
        expect(result.warnings, isEmpty);
      },
    );

    test('rewrites includegraphics path when extension is omitted', () async {
      final imagesDir = Directory(p.join(tempDir.path, 'images'))..createSync();
      final pdf = File(p.join(imagesDir.path, 'plot.pdf'));
      pdf.writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);

      final mainTex = File(p.join(tempDir.path, 'main.tex'));
      mainTex.writeAsStringSync(
        r'\includegraphics[width=0.9\textwidth]{images/plot}',
      );

      await PdfImagePreprocessor.prepareForDocx(
        mainTex,
        converter: (inputPdf, outputPng) async {
          await outputPng.writeAsString('PNG');
          return true;
        },
      );

      final rewritten = await mainTex.readAsString();
      expect(rewritten, contains('images/plot__pandoc.png'));
    });

    test('processes nested tex files under the project root', () async {
      final chaptersDir = Directory(p.join(tempDir.path, 'chapters'))
        ..createSync();
      final imagesDir = Directory(p.join(tempDir.path, 'images'))..createSync();
      final pdf = File(p.join(imagesDir.path, 'chapter_fig.pdf'));
      pdf.writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);

      final mainTex = File(p.join(tempDir.path, 'main.tex'));
      mainTex.writeAsStringSync(r'\input{chapters/ch1.tex}');

      final ch1 = File(p.join(chaptersDir.path, 'ch1.tex'));
      ch1.writeAsStringSync(r'\includegraphics{../images/chapter_fig.pdf}');

      final result = await PdfImagePreprocessor.prepareForDocx(
        mainTex,
        converter: (inputPdf, outputPng) async {
          await outputPng.writeAsString('PNG');
          return true;
        },
      );

      final rewrittenChapter = await ch1.readAsString();
      expect(rewrittenChapter, contains('../images/chapter_fig__pandoc.png'));
      expect(result.convertedImages, 1);
      expect(result.rewrittenFiles, 1);
    });

    test(
      'keeps source reference and emits warning when conversion fails',
      () async {
        final imagesDir = Directory(p.join(tempDir.path, 'images'))
          ..createSync();
        final pdf = File(p.join(imagesDir.path, 'broken.pdf'));
        pdf.writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);

        final mainTex = File(p.join(tempDir.path, 'main.tex'));
        mainTex.writeAsStringSync(r'\includegraphics{images/broken.pdf}');

        final result = await PdfImagePreprocessor.prepareForDocx(
          mainTex,
          converter: (inputPdf, outputPng) async => false,
        );

        final content = await mainTex.readAsString();
        expect(content, contains('images/broken.pdf'));
        expect(result.convertedImages, 0);
        expect(result.warnings, isNotEmpty);
      },
    );

    test('ignores includegraphics lines that are commented out', () async {
      final imagesDir = Directory(p.join(tempDir.path, 'images'))..createSync();
      final pdf = File(p.join(imagesDir.path, 'commented.pdf'));
      pdf.writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);

      final mainTex = File(p.join(tempDir.path, 'main.tex'));
      mainTex.writeAsStringSync(r'% \includegraphics{images/commented.pdf}');

      final result = await PdfImagePreprocessor.prepareForDocx(
        mainTex,
        converter: (inputPdf, outputPng) async {
          await outputPng.writeAsString('PNG');
          return true;
        },
      );

      final content = await mainTex.readAsString();
      expect(content, contains('% \\includegraphics{images/commented.pdf}'));
      expect(result.convertedImages, 0);
    });
  });
}
