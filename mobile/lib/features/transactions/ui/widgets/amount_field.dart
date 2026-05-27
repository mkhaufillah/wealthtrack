import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Extracts raw digits from text, stripping any non-digit characters.
String _extractDigits(String text) => text.replaceAll(RegExp(r'[^\d]'), '');

/// Formats raw digits with "Rp" prefix and Indonesian thousand separator (period).
/// "50000" -> "Rp 50.000"
String _formatAmount(String text) {
  final digits = _extractDigits(text);
  if (digits.isEmpty) return '';
  final buf = StringBuffer();
  int count = 0;
  for (int i = digits.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) buf.write('.');
    buf.write(digits[i]);
    count++;
  }
  return 'Rp ${buf.toString().split('').reversed.join('')}';
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
      // Initial value: format it for display (unfocused state)
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
    final raw = _extractDigits(widget.controller.text);
    widget.controller.value = TextEditingValue(
      text: raw,
      selection: TextSelection.collapsed(offset: raw.length),
    );
    _updating = false;
  }

  void _onFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      // Gained focus → strip formatting, show raw digits only
      if (_hasText) _applyRaw();
    } else {
      // Lost focus → format with "Rp" prefix and thousand separators
      if (_hasText) _applyFormatted();
    }
  }

  void _onTextChange() {
    if (_updating) return;
    // When focused, strip any non-digit characters that may have been pasted
    if (_isFocused) {
      final raw = _extractDigits(widget.controller.text);
      if (raw != widget.controller.text) {
        _updating = true;
        widget.controller.value = TextEditingValue(
          text: raw,
          selection: TextSelection.collapsed(offset: raw.length),
        );
        _updating = false;
      }
    }
    final text = widget.controller.text;
    final hasText = text.isNotEmpty;
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
