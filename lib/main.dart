import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'converter_state.dart';
import 'screens/converter_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final state = ConverterState();

  // Check pandoc availability asynchronously; UI shows a spinner until done.
  state.init();

  runApp(
    ChangeNotifierProvider<ConverterState>.value(
      value: state,
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LaTeX to Word Converter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ConverterScreen(),
    );
  }
}
