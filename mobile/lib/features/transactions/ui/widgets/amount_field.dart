import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

const _rpPrefix = 'Rp ';

/// Formats raw digits with Indonesian thousand separator (period).
/// "Rp 50000" -> "Rp 50.000".
String _formatAmount(String text) {
  final withoutRp = text.startsWith('Rp ') ? text.substring(3) : text;
  if (withoutRp.isEmpty) return _rpPrefix;
  final digits = withoutRp.replaceAll('.', '');
  if (digits.isEmpty) return _rpPrefix;
  final buf = StringBuffer();
  int count = 0;
  for (int i = digits.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) buf.write('.');
    buf.write(digits[i]);
    count++;
  }
  return '$_rpPrefix${buf.toString().split('').reversed.join('')}';
}

/// Strips thousand separators, keeps "Rp " prefix.
/// "Rp 50.000" -> "Rp 50000"
String _unformatAmount(String text) {
  final withoutRp = text.startsWith('Rp ') ? text.substring(3) : text;
  return '$_rpPrefix${withoutRp.replaceAll('.', '')}';
}

/// Extracts raw integer digits from text that may have "Rp" and separators.
/// "Rp 50.000" -> "50000"
String _stripFormatting(String text) {
  return text.replaceAll('Rp', '').replaceAll('.', '').replaceAll(',', '').trim();
}

class AmountField extends StatefulWidget {
  final TextEditingController controller;
  const AmountField({super.key, required this.controller});

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _isFocused = false;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    if (_hasText) {
      _applyFormatted();
    }
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onTextChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _applyFormatted() {
    _updating = true;
    final formatted = _formatAmount(widget.controller.text);
    widget.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _updating = false;
  }

  void _applyRaw() {
    _updating = true;
    final raw = _unformatAmount(widget.controller.text);
    widget.controller.value = TextEditingValue(
      text: raw,
      selection: TextSelection.collapsed(offset: raw.length),
    );
    _updating = false;
  }

  void _onFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      // Gained focus → show raw digits for editing (keep "Rp " prefix)
      if (_hasText) _applyRaw();
    } else {
      // Lost focus → format with thousand separators
      if (_hasText) _applyFormatted();
    }
  }

  void _onTextChange() {
    if (_updating) return;
    final text = widget.controller.text;
    // Strip out periods while user is typing to keep it clean
    final clean = text.replaceAll('.', '');
    if (clean != text) {
      _updating = true;
      widget.controller.value = TextEditingValue(
        text: clean,
        selection: TextSelection.collapsed(offset: clean.length),
      );
      _updating = false;
    }
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showHint = !_isFocused && !_hasText;

    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        hintText: showHint ? 'Rp 0' : null,
        hintStyle: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
        ),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
      ),
      style: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }
}
