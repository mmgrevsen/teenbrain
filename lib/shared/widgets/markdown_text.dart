/// A small markdown renderer.
///
/// `flutter_markdown` is discontinued, and a full CommonMark implementation is
/// far more than the assistant produces. This handles what the prompts actually
/// ask for — headings, lists, bold, italic, code, quotes, rules — renders it in
/// the app's own type scale, and keeps everything selectable.
///
/// Anything it does not recognise is shown as plain text rather than swallowed.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

class MarkdownText extends StatelessWidget {
  const MarkdownText(this.source, {super.key, this.selectable = true});

  final String source;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == blocks.length - 1 ? 0 : 10),
            child: _buildBlock(context, blocks[i]),
          ),
      ],
    );
  }

  Widget _buildBlock(BuildContext context, _Block block) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    switch (block) {
      case _Heading(:final level, :final content):
        return Padding(
          padding: EdgeInsets.only(top: level == 1 ? 6 : 4, bottom: 2),
          child: _rich(
            context,
            content,
            switch (level) {
              1 => text.headlineSmall!,
              2 => text.titleMedium!.copyWith(fontSize: 16),
              _ => text.titleMedium!,
            },
          ),
        );

      case _Paragraph(:final content):
        return _rich(context, content, text.bodyLarge!);

      case _Bullet(:final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 10, left: 2),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration:
                            BoxDecoration(color: colors.textTertiary, shape: BoxShape.circle),
                      ),
                    ),
                    Expanded(child: _rich(context, item, text.bodyLarge!)),
                  ],
                ),
              ),
          ],
        );

      case _Numbered(:final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}.',
                        style: text.bodyLarge!.copyWith(color: colors.textTertiary),
                      ),
                    ),
                    Expanded(child: _rich(context, items[i], text.bodyLarge!)),
                  ],
                ),
              ),
          ],
        );

      case _Code(:final content, :final language):
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surfaceHover,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(Insets.radiusSmall),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (language != null && language.isNotEmpty) ...[
                Text(language, style: text.labelSmall),
                const SizedBox(height: 8),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  content,
                  style: text.bodyMedium!.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
                    color: colors.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        );

      case _Quote(:final content):
        return Container(
          padding: const EdgeInsets.only(left: 14),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colors.borderStrong, width: 2)),
          ),
          child: _rich(
            context,
            content,
            text.bodyLarge!.copyWith(color: colors.textSecondary),
          ),
        );

      case _Rule():
        return Container(height: 1, color: colors.border);
    }
  }

  Widget _rich(BuildContext context, String content, TextStyle base) {
    final spans = _parseInline(context, content, base);
    if (selectable) {
      return SelectableText.rich(TextSpan(children: spans, style: base));
    }
    return Text.rich(TextSpan(children: spans, style: base));
  }

  // ------------------------------------------------------------- block pass

  static List<_Block> _parseBlocks(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_Block>[];

    var paragraph = <String>[];
    var bullets = <String>[];
    var numbers = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(_Paragraph(paragraph.join(' ').trim()));
      paragraph = [];
    }

    void flushBullets() {
      if (bullets.isEmpty) return;
      blocks.add(_Bullet(List.of(bullets)));
      bullets = [];
    }

    void flushNumbers() {
      if (numbers.isEmpty) return;
      blocks.add(_Numbered(List.of(numbers)));
      numbers = [];
    }

    void flushAll() {
      flushParagraph();
      flushBullets();
      flushNumbers();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        flushAll();
        final language = trimmed.substring(3).trim();
        final body = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          body.add(lines[i]);
          i++;
        }
        blocks.add(_Code(body.join('\n'), language.isEmpty ? null : language));
        continue;
      }

      if (trimmed.isEmpty) {
        flushAll();
        continue;
      }

      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
        flushAll();
        blocks.add(const _Rule());
        continue;
      }

      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flushAll();
        blocks.add(_Heading(heading.group(1)!.length, heading.group(2)!.trim()));
        continue;
      }

      if (trimmed.startsWith('> ')) {
        flushAll();
        blocks.add(_Quote(trimmed.substring(2).trim()));
        continue;
      }

      final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        flushParagraph();
        flushNumbers();
        bullets.add(bullet.group(1)!.trim());
        continue;
      }

      final numbered = RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(trimmed);
      if (numbered != null) {
        flushParagraph();
        flushBullets();
        numbers.add(numbered.group(1)!.trim());
        continue;
      }

      flushBullets();
      flushNumbers();
      paragraph.add(trimmed);
    }

    flushAll();
    return blocks;
  }

  // ------------------------------------------------------------ inline pass

  /// Handles `**bold**`, `*italic*`, `` `code` `` and `[text](url)`.
  ///
  /// Links are rendered as text, not tapped: nothing in this app should open a
  /// URL a model wrote without the user deciding to.
  static List<InlineSpan> _parseInline(
    BuildContext context,
    String source,
    TextStyle base,
  ) {
    final colors = context.colors;
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(\*\*[^*]+\*\*)|(__[^_]+__)|(\*[^*\n]+\*)|(`[^`\n]+`)|(\[[^\]]+\]\([^)]*\))',
    );

    var index = 0;
    for (final match in pattern.allMatches(source)) {
      if (match.start > index) {
        spans.add(TextSpan(text: source.substring(index, match.start)));
      }
      final token = match.group(0)!;

      if (token.startsWith('**') || token.startsWith('__')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: base.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary),
        ));
      } else if (token.startsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: base.copyWith(
            fontFamily: 'monospace',
            fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
            fontSize: (base.fontSize ?? 14) - 1,
            backgroundColor: colors.surfaceHover,
          ),
        ));
      } else if (token.startsWith('[')) {
        final label = RegExp(r'^\[([^\]]+)\]').firstMatch(token)?.group(1) ?? token;
        spans.add(TextSpan(
          text: label,
          style: base.copyWith(color: colors.accent),
        ));
      } else {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
      }

      index = match.end;
    }

    if (index < source.length) {
      spans.add(TextSpan(text: source.substring(index)));
    }
    return spans;
  }
}

sealed class _Block {
  const _Block();
}

class _Heading extends _Block {
  const _Heading(this.level, this.content);
  final int level;
  final String content;
}

class _Paragraph extends _Block {
  const _Paragraph(this.content);
  final String content;
}

class _Bullet extends _Block {
  const _Bullet(this.items);
  final List<String> items;
}

class _Numbered extends _Block {
  const _Numbered(this.items);
  final List<String> items;
}

class _Code extends _Block {
  const _Code(this.content, this.language);
  final String content;
  final String? language;
}

class _Quote extends _Block {
  const _Quote(this.content);
  final String content;
}

class _Rule extends _Block {
  const _Rule();
}
