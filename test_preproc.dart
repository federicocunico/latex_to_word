import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'lib/services/latex_preprocessor.dart';

void main() async {
  final destDir = Directory('C:/Users/User/AppData/Local/Temp/test_conv2');
  if (await destDir.exists()) await destDir.delete(recursive: true);
  await destDir.create();

  final zipBytes = await File('C:/Users/User/github/latex_to_word/data/test.zip').readAsBytes();
  final archive = ZipDecoder().decodeBytes(zipBytes);
  for (final entry in archive) {
    final path = '/tmp/test_conv2/${entry.name}';
    if (entry.isFile) {
      final f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(entry.content as Uint8List);
    }
  }
  print('Extracted ${archive.length} entries');

  final mainTex = File('/tmp/test_conv2/main.tex');
  final before = await mainTex.readAsString();
  print('Before: ${before.length} chars, ${before.split("\n").length} lines');

  final result = await LatexPreprocessor.preprocess(mainTex);

  final after = await mainTex.readAsString();
  print('After: ${after.length} chars, ${after.split("\n").length} lines');
  print('Affiliations preprocessed: ${result.affiliationsPreprocessed}');
  print('Captions numbered: ${result.captionsNumbered}');

  final authorIdx = after.indexOf(r'\author');
  if (authorIdx != -1) {
    print('\n--- \author area ---');
    print(after.substring(authorIdx, authorIdx + 300));
  }

  final mkIdx = after.indexOf(r'\maketitle');
  if (mkIdx != -1) {
    print('\n--- \maketitle area (500 chars) ---');
    print(after.substring(mkIdx, mkIdx + 600));
  }

  final bodyStart = after.indexOf(r'\begin{abstract}');
  print('\n--- abstract present: ${bodyStart != -1} ---');
  
  // Show a snippet from the middle of the document
  print('\n--- middle of document (char 30000-30200) ---');
  if (after.length > 30200) print(after.substring(30000, 30200));
  
  // Show figure captions
  for (final m in RegExp(r'\caption\{[^}]{0,80}').allMatches(after)) {
    print('Caption: ${m.group(0)}');
  }
}
