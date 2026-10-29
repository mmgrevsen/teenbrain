import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Consistent page chrome: generous margins, a capped content width so text
/// never runs the full width of a 32" display, and a scroll view by default.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.scrollable = true,
    this.maxWidth = Insets.maxContent,
    this.padding,
  });

  final List<Widget> children;
  final bool scrollable;
  final double maxWidth;

  /// Null means the responsive default: generous on a desktop, tight on a
  /// phone, with room at the bottom for the navigation bar.
  final EdgeInsets? padding;

  EdgeInsets _resolvePadding(BuildContext context) {
    if (padding != null) return padding!;
    final inset = context.pageInset;
    return EdgeInsets.fromLTRB(
      inset,
      context.isCompact ? 16 : 8,
      inset,
      context.isCompact ? 32 : 56,
    );
  }

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    final constrained = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: _resolvePadding(context), child: column),
      ),
    );

    if (!scrollable) return constrained;
    return SingleChildScrollView(child: constrained);
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );

    // Actions sit beside the title on a desktop and under it on a phone —
    // two buttons and a heading do not fit across 390 points.
    if (context.isCompact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            if (trailing != null) ...[
              const SizedBox(height: 14),
              trailing!,
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: heading),
          ?trailing,
        ],
      ),
    );
  }
}
