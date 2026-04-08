import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../converter_state.dart';
import '../widgets/drop_zone.dart';

class ConverterScreen extends StatelessWidget {
  const ConverterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConverterState>();

    Widget body;
    if (state.pandocStatus != PandocStatus.available) {
      body = _pandocSetupBody(context, state);
    } else {
      body = DropZone(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: switch (state.status) {
                AppStatus.idle => _IdleView(),
                AppStatus.extracting ||
                AppStatus.converting =>
                  _ProgressView(),
                AppStatus.done => _DoneView(),
                AppStatus.error => _ErrorView(),
              },
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('LaTeX → Word Converter'),
        centerTitle: true,
        elevation: 0,
      ),
      body: body,
    );
  }

  Widget _pandocSetupBody(BuildContext context, ConverterState state) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: switch (state.pandocStatus) {
            PandocStatus.checking => _CheckingView(),
            PandocStatus.notFound => _NotFoundView(),
            PandocStatus.downloading => _DownloadingView(),
            PandocStatus.downloadFailed => _DownloadFailedView(),
            PandocStatus.available => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

// ── Idle ─────────────────────────────────────────────────────────────────────

class _IdleView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.read<ConverterState>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.upload_file_rounded,
          size: 80,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Convert Overleaf ZIP to Word',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Drop a .zip file here or click the button below.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('Select ZIP File'),
          onPressed: () => _pickAndConvert(context, state),
        ),
      ],
    );
  }

  Future<void> _pickAndConvert(
    BuildContext context,
    ConverterState state,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;
    await state.startConversion(File(result.files.single.path!));
  }
}

// ── Progress ─────────────────────────────────────────────────────────────────

class _ProgressView extends StatelessWidget {
  static const _steps = [
    (AppStatus.extracting, Icons.folder_zip_rounded, 'Extracting archive'),
    (AppStatus.converting, Icons.transform_rounded, 'Running pandoc'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConverterState>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(strokeWidth: 5),
        ),
        const SizedBox(height: 24),
        Text(
          state.statusMessage,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        ..._steps.map((step) {
          final (stepStatus, icon, label) = step;
          final isCurrent = state.status == stepStatus;
          final isDone = _stepIndex(state.status) > _stepIndex(stepStatus);
          return ListTile(
            leading: Icon(
              isDone ? Icons.check_circle_rounded : icon,
              color: isDone
                  ? Colors.green
                  : isCurrent
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(
              label,
              style: TextStyle(
                fontWeight:
                    isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCurrent
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          );
        }),
      ],
    );
  }

  int _stepIndex(AppStatus s) => switch (s) {
        AppStatus.idle => 0,
        AppStatus.extracting => 1,
        AppStatus.converting => 2,
        AppStatus.done || AppStatus.error => 3,
      };
}

// ── Done ─────────────────────────────────────────────────────────────────────

class _DoneView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConverterState>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_rounded,
          size: 80,
          color: Colors.green.shade600,
        ),
        const SizedBox(height: 16),
        Text(
          'Conversion Complete',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.save_alt_rounded),
          label: const Text('Save DOCX…'),
          onPressed: () => _saveDocx(context, state),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Convert Another'),
          onPressed: state.reset,
        ),
        if (state.pandocLog.isNotEmpty) ...[
          const SizedBox(height: 24),
          _LogExpander(log: state.pandocLog),
        ],
      ],
    );
  }

  Future<void> _saveDocx(BuildContext context, ConverterState state) async {
    final docx = state.resultDocx;
    if (docx == null) return;

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save converted document',
      fileName: 'output.docx',
      type: FileType.custom,
      allowedExtensions: ['docx'],
    );

    if (savePath == null) return;

    await docx.copy(savePath);
    await state.cleanupResult();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $savePath')),
      );
    }
  }
}

// ── Error ─────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConverterState>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_rounded,
          size: 80,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          'Conversion Failed',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            state.errorMessage,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try Again'),
          onPressed: state.reset,
        ),
      ],
    );
  }
}

// ── Pandoc setup views ────────────────────────────────────────────────────────

class _CheckingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
        SizedBox(height: 20),
        Text('Checking for pandoc…'),
      ],
    );
  }
}

class _NotFoundView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.read<ConverterState>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.download_rounded,
          size: 80,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'pandoc Required',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'pandoc converts LaTeX to Word and needs to be downloaded once '
          '(~35 MB). It will be stored locally and reused on every run.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download pandoc'),
          onPressed: state.downloadPandoc,
        ),
      ],
    );
  }
}

class _DownloadingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConverterState>();
    final progress = state.downloadProgress;
    final isIndeterminate = progress < 0;
    final percent =
        isIndeterminate ? '' : ' (${(progress * 100).toStringAsFixed(0)}%)';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.download_rounded,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          '${state.downloadStatusText}$percent',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        LinearProgressIndicator(
          value: isIndeterminate ? null : progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 12),
        Text(
          'Do not close the app.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _DownloadFailedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConverterState>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_off_rounded,
          size: 80,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          'Download Failed',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            state.downloadError,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry Download'),
          onPressed: context.read<ConverterState>().downloadPandoc,
        ),
      ],
    );
  }
}

// ── Log expander ─────────────────────────────────────────────────────────────

class _LogExpander extends StatefulWidget {
  final String log;

  const _LogExpander({required this.log});

  @override
  State<_LogExpander> createState() => _LogExpanderState();
}

class _LogExpanderState extends State<_LogExpander> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                'Pandoc log',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              widget.log,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }
}
