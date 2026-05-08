import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:latex_to_word_app/services/latex_preprocessor.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('latex_preprocessor_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<File> writeMain(String content) async {
    final f = File(p.join(tempDir.path, 'main.tex'));
    await f.writeAsString(content);
    return f;
  }

  group('affiliation preprocessing', () {
    test('extracts authblk authors with superscripts', () async {
      final mainTex = await writeMain(r'''
\documentclass{article}
\author[2,*]{Alice Smith\orcid{0000-0001-1234-5678}}
\author[1]{Bob Jones}
\affil[1]{University of Foo}
\affil[2]{University of Bar}
\affil[*]{Equal contribution.}
\correspondingauthor{alice@foo.edu}
\begin{document}
\maketitle
Hello world.
\end{document}
''');

      final result = await LatexPreprocessor.preprocess(mainTex);
      expect(result.affiliationsPreprocessed, isTrue);

      final out = await mainTex.readAsString();
      // New \author{} line present with superscripts
      expect(out, contains(r'\author{Alice Smith\textsuperscript{2,*}, Bob Jones\textsuperscript{1}}'));
      // Affiliation lines injected after \maketitle
      expect(out, contains(r'\textsuperscript{1}\,University of Foo'));
      expect(out, contains(r'\textsuperscript{2}\,University of Bar'));
      expect(out, contains(r'\textsuperscript{*}\,Equal contribution.'));
      expect(out, contains('Corresponding author:'));
      expect(out, contains('alice@foo.edu'));
      // Original commands removed
      expect(out, isNot(contains(r'\affil[')));
      expect(out, isNot(contains(r'\correspondingauthor{')));
    });

    test('strips \\orcid from author names', () async {
      final mainTex = await writeMain(r'''
\documentclass{article}
\author[1]{Jane Doe\orcid{0009-1234-5678-0000}}
\affil[1]{Some University}
\begin{document}
\maketitle
Body.
\end{document}
''');

      await LatexPreprocessor.preprocess(mainTex);
      final out = await mainTex.readAsString();
      expect(out, contains(r'\author{Jane Doe\textsuperscript{1}}'));
      expect(out, isNot(contains(r'\orcid')));
    });

    test('does nothing when no authblk commands present', () async {
      const src = r'''
\documentclass{article}
\author{Alice}
\begin{document}
\maketitle
Body.
\end{document}
''';
      final mainTex = await writeMain(src);
      final result = await LatexPreprocessor.preprocess(mainTex);
      expect(result.affiliationsPreprocessed, isFalse);
      // File unchanged
      expect(await mainTex.readAsString(), equals(src));
    });

    test('author without marks gets no superscript', () async {
      final mainTex = await writeMain(r'''
\documentclass{article}
\author{Plain Author}
\affil[1]{Plain Uni}
\begin{document}
\maketitle
Body.
\end{document}
''');

      await LatexPreprocessor.preprocess(mainTex);
      final out = await mainTex.readAsString();
      // No superscript added because \author has no [marks]
      expect(out, contains(r'\author{Plain Author}'));
    });
  });

  group('caption numbering', () {
    test('numbers figures and tables sequentially', () async {
      final mainTex = await writeMain(r'''
\documentclass{article}
\begin{document}
\begin{figure}
  \includegraphics{img.png}
  \caption{A nice figure.}
\end{figure}
\begin{table}
  \caption{A nice table.}
\end{table}
\begin{figure}
  \includegraphics{img2.png}
  \caption{Second figure.}
\end{figure}
\end{document}
''');

      final result = await LatexPreprocessor.preprocess(mainTex);
      expect(result.captionsNumbered, equals(3));

      final out = await mainTex.readAsString();
      expect(out, contains(r'\caption{Figure 1. A nice figure.}'));
      expect(out, contains(r'\caption{Table 1. A nice table.}'));
      expect(out, contains(r'\caption{Figure 2. Second figure.}'));
    });

    test('numbers captions in \\input{} included files in document order', () async {
      final figFile = File(p.join(tempDir.path, 'fig1.tex'));
      await figFile.writeAsString(r'''
\begin{figure}
  \includegraphics{a.png}
  \caption{Included figure.}
\end{figure}
''');

      final mainTex = await writeMain(r'''
\documentclass{article}
\begin{document}
\input{fig1}
\begin{figure}
  \includegraphics{b.png}
  \caption{Inline figure.}
\end{figure}
\end{document}
''');

      final result = await LatexPreprocessor.preprocess(mainTex);
      expect(result.captionsNumbered, equals(2));

      final figOut = await figFile.readAsString();
      expect(figOut, contains(r'\caption{Figure 1. Included figure.}'));

      final mainOut = await mainTex.readAsString();
      expect(mainOut, contains(r'\caption{Figure 2. Inline figure.}'));
    });

    test('does not double-number already-prefixed captions', () async {
      final mainTex = await writeMain(r'''
\documentclass{article}
\begin{document}
\begin{figure}
  \caption{Figure 1. Already numbered.}
\end{figure}
\end{document}
''');

      final result = await LatexPreprocessor.preprocess(mainTex);
      expect(result.captionsNumbered, equals(0));
      final out = await mainTex.readAsString();
      expect(out, contains(r'\caption{Figure 1. Already numbered.}'));
    });

    test('skips commented-out environments', () async {
      final mainTex = await writeMain(r'''
\documentclass{article}
\begin{document}
% \begin{figure}
%   \caption{Commented out.}
% \end{figure}
\begin{figure}
  \caption{Active figure.}
\end{figure}
\end{document}
''');

      final result = await LatexPreprocessor.preprocess(mainTex);
      expect(result.captionsNumbered, equals(1));
      final out = await mainTex.readAsString();
      expect(out, contains(r'\caption{Figure 1. Active figure.}'));
      expect(out, contains('% \\begin{figure}'));
    });

    test('handles figure* (two-column) environments', () async {
      final mainTex = await writeMain(r'''
\documentclass{article}
\begin{document}
\begin{figure*}
  \caption{Wide figure.}
\end{figure*}
\end{document}
''');

      final result = await LatexPreprocessor.preprocess(mainTex);
      expect(result.captionsNumbered, equals(1));
      final out = await mainTex.readAsString();
      expect(out, contains(r'\caption{Figure 1. Wide figure.}'));
    });
  });
}
