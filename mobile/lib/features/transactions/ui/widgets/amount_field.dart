import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Formats raw digits with Indonesian thousand separator (period).
/// "50000" -> "50.000". Returns empty string for empty input.
String _formatAmount(String raw) {
  if (raw.isEmpty) return '';
  final digits = raw.replaceAll('.', '');
  if (digits.isEmpty) return '';
  final buf = StringBuffer();
  int count = 0;
  for (int i = digits.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) buf.write('.');
    buf.write(digits[i]);
    count++;
  }
  return buf.toString().split('').reversed.join('');
}

/// Strips thousand separators (periods).
/// "50.000" -> "50000"
String _unformatAmount(String formatted) {
  return formatted.replaceAll('.', '');
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
  // Track whether we're programmatically updating to avoid loops
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    // If there's initial text, format it immediately
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
    final raw = _unformatAmount(widget.controller.text);
    widget.controller.value = TextEditingValue(
      text: _formatAmount(raw),
      selection: TextSelection.collapsed(offset: _formatAmount(raw).length),
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
      // Gained focus → show raw digits for editing
      if (_hasText) _applyRaw();
    } else {
      // Lost focus → format with thousand separators
      if (_hasText) _applyFormatted();
    }
  }

  void _onTextChange() {
    if (_updating) return;
    final text = widget.controller.text;
    final hasText = text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show hint '0' only when field is NOT focused AND empty
    final showHint = !_isFocused && !_hasText;

    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        prefix: const Text('Rp ',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            )),
        hintText: showHint ? '0' : null,
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
