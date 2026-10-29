import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The one input the whole app is built around.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onSubmit,
    this.controller,
    this.hint = 'Hvad leder du efter?',
    this.autofocus = false,
    this.large = false,
    this.onChanged,
  });

  final ValueChanged<String> onSubmit;
  final TextEditingController? controller;
  final String hint;
  final bool autofocus;
  final bool large;
  final ValueChanged<String>? onChanged;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = widget.large ? 17.0 : 14.5;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: widget.large ? 15 : 11),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Insets.radius),
        border: Border.all(color: _focused ? colors.accent : colors.border),
        boxShadow: _focused
            ? [BoxShadow(color: colors.accent.withValues(alpha: 0.12), blurRadius: 0, spreadRadius: 3)]
            : null,
      ),
      child: Row(
        children: [
          Text('⌕', style: TextStyle(fontSize: size + 2, color: colors.textTertiary)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmit,
              textInputAction: TextInputAction.search,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: size),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: Theme.of(context)
                    .textTheme
                    .bodyLarge!
                    .copyWith(fontSize: size, color: colors.textTertiary),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            _MiniAction(
              glyph: '✕',
              onTap: () {
                _controller.clear();
                widget.onChanged?.call('');
                setState(() {});
              },
            )
          else
            Text(
              '↵',
              style: TextStyle(fontSize: size - 2, color: colors.textTertiary),
            ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.glyph, required this.onTap});
  final String glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(glyph, style: TextStyle(fontSize: 12, color: context.colors.textTertiary)),
      ),
    );
  }
}
