import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../converter_state.dart';

class DropZone extends StatelessWidget {
  final Widget child;

  const DropZone({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConverterState>();

    return DropTarget(
      onDragEntered: (_) => state.setDragOver(true),
      onDragExited: (_) => state.setDragOver(false),
      onDragDone: (details) {
        state.setDragOver(false);
        final files = details.files
            .where((f) => f.path.toLowerCase().endsWith('.zip'))
            .toList();
        if (files.isNotEmpty) {
          state.startConversion(File(files.first.path));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please drop a .zip file.')),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          border: Border.all(
            color: state.isDragOver
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
          color: state.isDragOver
              ? Theme.of(context).colorScheme.primaryContainer.withAlpha(180)
              : Colors.transparent,
        ),
        child: child,
      ),
    );
  }
}
