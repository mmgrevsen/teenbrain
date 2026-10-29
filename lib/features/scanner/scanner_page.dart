import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/services/detection_services.dart';
import '../../domain/services/memory_service.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';

/// The live camera, what GlemtDet currently believes it is looking at, and an
/// honest read-out of how hard it is working.
class ScannerPage extends ConsumerStatefulWidget {
  const ScannerPage({super.key});

  @override
  ConsumerState<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends ConsumerState<ScannerPage> {
  @override
  void initState() {
    super.initState();
    // Opening the scanner while the memory switch is on should show a picture,
    // not a dead panel — so make sure capture is actually running.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = ref.read(settingsProvider);
      final service = ref.read(memoryServiceProvider);
      if (settings.memoryActive && !service.state.isRunning) {
        service.storeImages = settings.storeImages;
        await service.start(deviceId: settings.cameraDeviceId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final memory = ref.watch(currentMemoryStateProvider);
    final settings = ref.watch(settingsProvider);
    final stack = ref.watch(visionStackProvider);
    final service = ref.read(memoryServiceProvider);
    final colors = context.colors;

    return PageBody(
      maxWidth: 960,
      padding: const EdgeInsets.fromLTRB(Insets.page, 16, Insets.page, 56),
      children: [
        PageTitle(
          'Scanner',
          subtitle: stack.analyzer.backendDescription,
          trailing: Row(
            children: [
              AppButton(
                label: 'Scan nu',
                onPressed: memory.isRunning ? service.analyzeNow : null,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: memory.isRunning ? 'Stop' : 'Start',
                tone: memory.isRunning ? ButtonTone.neutral : ButtonTone.primary,
                onPressed: () async {
                  if (memory.isRunning) {
                    await service.stop();
                    ref.read(settingsProvider.notifier).setMemoryActive(false);
                  } else {
                    service.storeImages = settings.storeImages;
                    service.setRecording(true);
                    ref.read(settingsProvider.notifier).setMemoryActive(true);
                    await service.start(deviceId: settings.cameraDeviceId);
                  }
                },
              ),
            ],
          ),
        ),
        _Viewport(state: memory),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _DetectionPanel(state: memory)),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: _SamplingPanel(state: memory)),
          ],
        ),
        const SizedBox(height: 20),
        Panel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gem observationer', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      memory.status == MemoryStatus.paused
                          ? 'Scanneren kører, men der bliver ikke skrevet noget ned.'
                          : 'Nye observationer bliver gemt lokalt på denne computer.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Switch(
                value: memory.status != MemoryStatus.paused,
                activeThumbColor: colors.accent,
                onChanged: memory.isRunning ? service.setRecording : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The live preview. When there is nothing to show, it says why rather than
/// leaving a black rectangle.
class _Viewport extends ConsumerWidget {
  const _Viewport({required this.state});
  final MemoryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final nav = ref.read(navigationProvider.notifier);

    Widget content;
    if (state.status == MemoryStatus.error) {
      content = _ViewportMessage(
        glyph: '⚠',
        title: 'Kameraet kunne ikke startes',
        message: state.error ?? 'Ukendt fejl.',
        action: AppButton(
          label: 'Åbn indstillinger',
          onPressed: () => nav.go(const SettingsRoute()),
        ),
      );
    } else if (state.status == MemoryStatus.starting) {
      content = const _ViewportMessage(
        glyph: '◌',
        title: 'Starter kamera…',
        message: 'macOS spørger om tilladelse første gang.',
      );
    } else if (state.textureId == null) {
      content = const _ViewportMessage(
        glyph: '◉',
        title: 'Scanneren er slukket',
        message: 'Slå “Hukommelse aktiv” til, eller tryk Start.',
      );
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          Texture(textureId: state.textureId!, filterQuality: FilterQuality.medium),
          CustomPaint(painter: _OverlayPainter(state.lastObjects, colors.accent)),
          Positioned(
            left: 12,
            top: 12,
            child: _SceneBadge(state: state),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(Insets.radius),
      child: Container(
        height: 380,
        decoration: BoxDecoration(
          color: colors.surfaceHover,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(Insets.radius),
        ),
        child: content,
      ),
    );
  }
}

class _SceneBadge extends StatelessWidget {
  const _SceneBadge({required this.state});
  final MemoryState state;

  @override
  Widget build(BuildContext context) {
    final scene = state.lastScene;
    final label = scene.isKnown
        ? (scene.isSpecific ? scene.label! : '${scene.label!} (upræcist)')
        : 'Placering ukendt';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.objects, this.color);
  final List<DetectedObject> objects;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final object in objects) {
      final b = object.bounds;
      if (b == null) continue;
      final rect = Rect.fromLTWH(
        b.left * size.width,
        b.top * size.height,
        b.width * size.width,
        b.height * size.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      final painter = TextPainter(
        text: TextSpan(
          text: ' ${object.label} · ${(object.confidence * 100).round()} % ',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelRect = Rect.fromLTWH(
        rect.left,
        (rect.top - painter.height - 4).clamp(0, size.height),
        painter.width,
        painter.height + 3,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(3)),
        Paint()..color = color,
      );
      painter.paint(canvas, Offset(labelRect.left, labelRect.top + 1));
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.objects != objects;
}

class _ViewportMessage extends StatelessWidget {
  const _ViewportMessage({
    required this.glyph,
    required this.title,
    required this.message,
    this.action,
  });

  final String glyph;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: EmptyState(glyph: glyph, title: title, message: message, action: action),
    );
  }
}

class _DetectionPanel extends StatelessWidget {
  const _DetectionPanel({required this.state});
  final MemoryState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final objects = state.lastObjects;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading('Set lige nu'),
          if (objects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                state.lastAnalysisAt == null
                    ? 'Ingen analyse kørt endnu.'
                    : 'Ingen genkendte objekter i det seneste billede.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (final object in objects)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(child: Text(object.label, style: Theme.of(context).textTheme.bodyLarge)),
                    ConfidencePill(confidence: object.confidence),
                  ],
                ),
              ),
          const SizedBox(height: 14),
          Container(height: 1, color: colors.border),
          const SizedBox(height: 12),
          Text('Placering', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            state.lastScene.isKnown
                ? state.lastScene.isSpecific
                    ? state.lastScene.label!
                    : '${state.lastScene.label!} — for upræcist til at sige hvilket rum'
                : 'Kunne ikke bestemmes',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (state.lastScene.alternatives.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Kunne også være: ${state.lastScene.alternatives.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows that the app really is sampling intelligently rather than grinding
/// through every frame.
class _SamplingPanel extends ConsumerWidget {
  const _SamplingPanel({required this.state});
  final MemoryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sampler = ref.read(memoryServiceProvider).sampler;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading('Belastning'),
          _Stat(label: 'Billeder modtaget', value: '${state.framesSeen}'),
          _Stat(label: 'Analyser kørt', value: '${state.analysisCount}'),
          _Stat(label: 'Seneste analyse', value: '${state.analysisMillis} ms'),
          _Stat(label: 'Observationer gemt', value: '${state.observationCount}'),
          _Stat(label: 'Dubletter slået sammen', value: '${state.duplicatesMerged}'),
          _Stat(
            label: 'Interval nu',
            value: '${(sampler.effectiveIdleInterval.inMilliseconds / 1000).toStringAsFixed(1)} s',
          ),
          if (state.lastAnalysisAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Sidst analyseret ${shortAgo(state.lastAnalysisAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: context.colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}
