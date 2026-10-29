/// Small building blocks shared across pages, so the app looks like one thing.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/models/detection.dart';

/// A quiet container with a hairline border — the app's only surface treatment.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.card),
    this.onTap,
    this.accent = false,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool accent;

  /// Adds the theme's one shadow. Used for cards that sit on the canvas rather
  /// than inside another surface.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: padding,
      decoration: BoxDecoration(
        color: accent ? colors.accentSoft : colors.surface,
        border: Border.all(color: accent ? colors.accent.withValues(alpha: 0.25) : colors.border),
        borderRadius: BorderRadius.circular(Insets.radius),
        boxShadow: elevated ? colors.elevation : null,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Hoverable(onTap: onTap!, builder: (hovered) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: padding,
        decoration: BoxDecoration(
          color: hovered ? colors.surfaceHover : colors.surface,
          border: Border.all(color: hovered ? colors.borderStrong : colors.border),
          borderRadius: BorderRadius.circular(Insets.radius),
          boxShadow: elevated ? colors.elevation : null,
        ),
        child: child,
      );
    });
  }
}

class Hoverable extends StatefulWidget {
  const Hoverable({super.key, required this.onTap, required this.builder});
  final VoidCallback onTap;
  final Widget Function(bool hovered) builder;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(_hovered),
      ),
    );
  }
}

enum ButtonTone { primary, neutral, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.tone = ButtonTone.neutral,
    this.icon,
    this.iconData,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonTone tone;

  /// A glyph, for GlemtDet's pages which were written against one.
  final String? icon;

  /// A real icon. Preferred — a glyph is only as good as the system font.
  final IconData? iconData;

  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null;

    final (bg, fg, border) = switch (tone) {
      ButtonTone.primary => (colors.accent, colors.accentText, colors.accent),
      ButtonTone.neutral => (colors.surface, colors.textPrimary, colors.borderStrong),
      ButtonTone.danger => (colors.surface, colors.danger, colors.danger.withValues(alpha: 0.4)),
    };

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Hoverable(
        onTap: enabled ? onPressed! : () {},
        builder: (hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: hovered && enabled
                ? (tone == ButtonTone.primary ? bg.withValues(alpha: 0.88) : colors.surfaceHover)
                : bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(Insets.radiusSmall),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (iconData != null) ...[
                Icon(iconData, color: fg, size: 16),
                const SizedBox(width: 8),
              ] else if (icon != null) ...[
                Text(icon!, style: TextStyle(color: fg, fontSize: 13)),
                const SizedBox(width: 8),
              ],
              // Flexible inside a min-size row: natural width when there is
              // room, ellipsis when a long label meets a narrow column. Labels
              // built from user data — a subject name — make this necessary.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge!
                      .copyWith(color: fg, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "94 %" with a colour that reflects how much to trust it.
class ConfidencePill extends StatelessWidget {
  const ConfidencePill({super.key, required this.confidence, this.label});

  final double confidence;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pct = (confidence * 100).round();
    final tone = confidence >= 0.6
        ? colors.positive
        : confidence >= 0.35
            ? colors.warning
            : colors.textTertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label == null ? '$pct %' : '${label!} $pct %',
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall!.copyWith(letterSpacing: 0.9),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.glyph = '◌',
    this.icon,
    this.action,
  });

  final String title;
  final String message;

  /// A glyph, for GlemtDet's pages. [icon] wins when both are given.
  final String glyph;
  final IconData? icon;

  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 38, color: colors.textTertiary)
            else
              Text(glyph, style: TextStyle(fontSize: 34, color: colors.textTertiary)),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// A stored reference frame, optionally with the detection box drawn on it.
class FrameThumbnail extends StatelessWidget {
  const FrameThumbnail({
    super.key,
    required this.path,
    this.bounds,
    this.width = 96,
    this.height = 64,
    this.radius = Insets.radiusSmall,
  });

  final String? path;
  final NormRect? bounds;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final file = path == null ? null : File(path!);
    final exists = file != null && file.existsSync();

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: height,
        color: colors.surfaceHover,
        child: exists
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(file, fit: BoxFit.cover, gaplessPlayback: true),
                  if (bounds != null)
                    CustomPaint(painter: _BoxPainter(bounds!, colors.accent)),
                ],
              )
            : Center(
                child: Text(
                  path == null ? '—' : '⌧',
                  style: TextStyle(color: colors.textTertiary, fontSize: 14),
                ),
              ),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.rect, this.color);
  final NormRect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      rect.left * size.width,
      rect.top * size.height,
      rect.width * size.width,
      rect.height * size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(3)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.rect != rect || old.color != color;
}

/// One line of history: time, object, place.
class ObservationRow extends StatelessWidget {
  const ObservationRow({
    super.key,
    required this.time,
    required this.objectLabel,
    required this.icon,
    this.placeLabel,
    this.confidence,
    this.imagePath,
    this.bounds,
    this.onTap,
    this.merged = false,
  });

  final DateTime time;
  final String objectLabel;
  final String icon;
  final String? placeLabel;
  final double? confidence;
  final String? imagePath;
  final NormRect? bounds;
  final VoidCallback? onTap;
  final bool merged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Hoverable(
      onTap: onTap ?? () {},
      builder: (hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hovered ? colors.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(Insets.radiusSmall),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(
                clockOf(time),
                style: text.bodyMedium!.copyWith(
                  color: colors.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            FrameThumbnail(path: imagePath, bounds: bounds, width: 54, height: 36),
            const SizedBox(width: 14),
            SizedBox(
              width: 26,
              child: Text(icon, style: TextStyle(fontSize: 15, color: colors.textSecondary)),
            ),
            Expanded(
              child: Text(objectLabel, style: text.bodyLarge),
            ),
            Expanded(
              child: Text(
                placeLabel ?? 'Ukendt placering',
                style: text.bodyMedium!.copyWith(
                  color: placeLabel == null ? colors.textTertiary : colors.textSecondary,
                  fontStyle: placeLabel == null ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
            if (confidence != null) ConfidencePill(confidence: confidence!),
          ],
        ),
      ),
    );
  }
}
