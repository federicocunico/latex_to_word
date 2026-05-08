import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'lib/services/latex_preprocessor.dart';

void main() async {
  final destDir = Directory('C:/Users/User/AppData/Local/Temp/test_debug');
  if (await destDir.exists()) await destDir.delete(recursive: true);
  await destDir.create();

  final zipBytes = await File('C:/Users/User/github/latex_to_word/data/test.zip').readAsBytes();
  final archive = ZipDecoder().decodeBytes(zipBytes);
  for (final entry in archive) {
    final path = 'C:/Users/User/AppData/Local/Temp/test_debug/${entry.name}';
    if (entry.isFile) {
      final f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(entry.content as Uint8List);
    }
  }

  final mainTex = File('C:/Users/User/AppData/Local/Temp/test_debug/main.tex');
  
  // Check table files BEFORE preprocessing
  final tableDir = Directory('C:/Users/User/AppData/Local/Temp/test_debug/tables');
  print('=== TABLE FILES BEFORE ===');
  await for (final f in tableDir.list()) {
    if (f is File && f.path.endsWith('.tex')) {
      final content = await f.readAsString();
      print('--- ${f.path} ---');
      print(content.substring(0, content.length.clamp(0, 400)));
      print("---");
    }
  }
  
  // Check where tables are referenced in main.tex
  final mainContent = await mainTex.readAsString();
  final tableRefs = RegExp(r'\input\{tables[^}]+\}').allMatches(mainContent);
  print('=== TABLE \input references in main.tex ===');
  for (final m in tableRefs) print(m.group(0));
  
  // Also check for direct \begin{table} in main.tex
  final directTables = RegExp(r'\begin\{table').allMatches(mainContent);
  print('\nDirect \begin{table} in main.tex: ${directTables.length}');

  final result = await LatexPreprocessor.preprocess(mainTex);
  print('\nCaptions numbered: ${result.captionsNumbered}');
  
  print('\n=== TABLE FILES AFTER ===');
  await for (final f in tableDir.list()) {
    if (f is File && f.path.endsWith('.tex')) {
      final content = await f.readAsString();
      print('--- ${f.path} ---');
      print(content.substring(0, content.length.clamp(0, 400)));
      print("---");
    }
  }
}
