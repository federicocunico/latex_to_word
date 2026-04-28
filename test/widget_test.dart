import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:latex_to_word_app/converter_state.dart';
import 'package:latex_to_word_app/main.dart';

void main() {
  testWidgets('App renders converter screen shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ConverterState(),
        child: const App(),
      ),
    );

    expect(find.text('LaTeX → Word Converter'), findsOneWidget);
  });
}
