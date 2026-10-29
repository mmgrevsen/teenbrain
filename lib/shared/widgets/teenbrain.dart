/// TeenBrain's own building blocks, on top of the shared primitives.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import 'primitives.dart';

/// A coloured dot standing in for a subject. Cheaper to scan than a label.
class SubjectDot extends StatelessWidget {
  const SubjectDot({super.key, required this.token, this.size = 8});

  final String token;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.subject(token),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// A small label. `tone` colours it; null leaves it neutral.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.tone, this.filled = false});

  final String text;
  final Color? tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = tone ?? colors.textTertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.12) : Colors.transparent,
        border: filled ? null : Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// A thin horizontal progress bar.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.tone, this.height = 5});

  /// 0..1
  final double value;
  final Color? tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(height: height, color: colors.surfaceHover),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              height: height,
              color: tone ?? colors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's text input. One border, one focus colour, no Material chrome.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.hint,
    this.minLines = 1,
    this.maxLines = 1,
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
    this.textStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.focusNode,
    this.enabled = true,
    this.keyboardType,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String? hint;
  final int minLines;
  final int maxLines;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextStyle? textStyle;
  final EdgeInsets padding;
  final FocusNode? focusNode;
  final bool enabled;
  final TextInputType? keyboardType;
  final bool obscure;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      decoration: BoxDecoration(
        color: widget.enabled ? colors.surface : colors.surfaceHover,
        border: Border.all(
          color: _focused ? colors.accent : colors.border,
          width: _focused ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(Insets.radiusSmall),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        enabled: widget.enabled,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscure,
        style: widget.textStyle ?? Theme.of(context).textTheme.bodyLarge,
        cursorColor: colors.accent,
        cursorWidth: 1.6,
        onSubmitted: widget.onSubmitted,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: Theme.of(context)
              .textTheme
              .bodyLarge!
              .copyWith(color: colors.textTertiary),
          border: InputBorder.none,
          isDense: true,
          contentPadding: widget.padding,
        ),
      ),
    );
  }
}

/// The row used on Settings and Privacy: a label, an explanation and a switch.
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    this.tone,
    this.enabled = true,
    this.disabledNote,
  });

  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? tone;
  final bool enabled;

  /// Shown instead of [description] when the row is disabled, so a switch the
  /// user cannot move always says why.
  final String? disabledNote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final subtitle = enabled ? description : (disabledNote ?? description);

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Hoverable(
        onTap: enabled && onChanged != null ? () => onChanged!(!value) : () {},
        builder: (hovered) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: hovered && enabled ? colors.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(Insets.radiusSmall),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle, style: text.bodyMedium),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AppSwitch(value: value, tone: tone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The switch itself, drawn rather than borrowed from Material.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, this.tone});

  final bool value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOut,
      width: 38,
      height: 22,
      decoration: BoxDecoration(
        color: value ? (tone ?? colors.accent) : colors.borderStrong,
        borderRadius: BorderRadius.circular(11),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.all(2),
          width: 18,
          height: 18,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// A row of pill-shaped choices. Used wherever a segmented control would be.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.wrap = true,
  });

  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final option in options)
        _Choice(
          label: option.label,
          selected: option.value == selected,
          onTap: () => onSelected(option.value),
        ),
    ];

    if (!wrap) {
      return Row(
        children: [
          for (final chip in chips) Padding(padding: const EdgeInsets.only(right: 8), child: chip),
        ],
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Hoverable(
      onTap: onTap,
      builder: (hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent
              : hovered
                  ? colors.surfaceHover
                  : colors.surface,
          border: Border.all(color: selected ? colors.accent : colors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge!.copyWith(
                color: selected ? colors.accentText : colors.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
        ),
      ),
    );
  }
}

/// Three dots, for while the model is thinking.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key});

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colors.textTertiary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
              child: Opacity(
                opacity: 0.3 + 0.7 * _pulse(i),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _pulse(int index) {
    final phase = (_controller.value - index * 0.18) % 1.0;
    return phase < 0.5 ? (1 - (phase * 2 - 0.5).abs() * 2).clamp(0.0, 1.0) : 0.0;
  }
}

/// A grey block standing in for content that has not arrived.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height = 14, this.width, this.radius = 6});

  final double height;
  final double? width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9).animate(_controller),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: colors.surfaceHover,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// The banner shown where a feature exists but cannot work yet.
///
/// Used instead of a button that looks live and does nothing.
class ComingSoon extends StatelessWidget {
  const ComingSoon({
    super.key,
    required this.title,
    required this.explanation,
    this.missing = const [],
  });

  final String title;
  final String explanation;

  /// What specifically is not built. Being concrete is the point.
  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tag('Kommer snart', tone: colors.warning, filled: true),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: 10),
          Text(explanation, style: text.bodyMedium),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Det der mangler:', style: text.labelSmall),
            const SizedBox(height: 6),
            for (final item in missing)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('· $item', style: text.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}

/// Shows an error from the AI layer with the one sentence that explains it.
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message, this.onRetry, this.actionLabel});

  final String message;
  final VoidCallback? onRetry;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.08),
        border: Border.all(color: colors.danger.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(Insets.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium!
                  .copyWith(color: colors.danger),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onRetry,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  actionLabel ?? 'Prøv igen',
                  style: Theme.of(context).textTheme.labelMedium!.copyWith(
                        color: colors.danger,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Copies text to the clipboard and says so.
Future<void> copyToClipboard(BuildContext context, String text, {String? label}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(label ?? 'Kopieret'),
      behavior: SnackBarBehavior.floating,
      width: 200,
      duration: const Duration(seconds: 2),
    ),
  );
}
