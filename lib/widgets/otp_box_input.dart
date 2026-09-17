import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modern box-per-digit OTP field — one digit per box, auto-advancing
/// focus forward as the person types and back on backspace, with support
/// for pasting (or autofilling) a full code in one go.
///
/// Keeps [controller]'s text in sync as the plain joined digit string, so
/// any screen that already reads `otpCtrl.text.trim()` after this field
/// (see ForgotPasswordScreen / account_verify_otp_dialog) doesn't need any
/// other change — this is a drop-in visual replacement for the old single
/// wide TextFormField.
class OtpBoxInput extends StatefulWidget {
  final TextEditingController controller;
  final Color accent;
  final int length;
  final double boxWidth;
  final double boxHeight;
  final ValueChanged<String>? onChanged;
  /// Fired once every box is filled — handy for auto-submitting.
  final ValueChanged<String>? onCompleted;
  final bool autofocus;
  final bool hasError;

  const OtpBoxInput({
    super.key,
    required this.controller,
    required this.accent,
    this.length = 6,
    this.boxWidth = 44,
    this.boxHeight = 54,
    this.onChanged,
    this.onCompleted,
    this.autofocus = true,
    this.hasError = false,
  });

  @override
  State<OtpBoxInput> createState() => _OtpBoxInputState();
}

class _OtpBoxInputState extends State<OtpBoxInput> {
  late final List<TextEditingController> _boxCtrls;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    final initial = widget.controller.text;
    _boxCtrls = List.generate(
      widget.length,
      (i) => TextEditingController(text: i < initial.length ? initial[i] : ''),
    );
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _boxCtrls) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final code = _boxCtrls.map((c) => c.text).join();
    // Keep the external controller (what callers actually read) in sync
    // without re-triggering our own listeners.
    widget.controller.value = TextEditingValue(text: code);
    widget.onChanged?.call(code);
    if (code.length == widget.length) {
      FocusScope.of(context).unfocus();
      widget.onCompleted?.call(code);
    }
  }

  // Spreads a pasted/autofilled multi-digit string across the boxes
  // starting at [startIndex], so pasting the whole code into any one box
  // fills the rest instead of being cut down to a single digit.
  void _spread(String digits, int startIndex) {
    for (var i = 0; i < digits.length && (startIndex + i) < widget.length; i++) {
      _boxCtrls[startIndex + i].text = digits[i];
    }
    final nextEmpty = _boxCtrls.indexWhere((c) => c.text.isEmpty);
    final focusIndex = nextEmpty == -1 ? widget.length - 1 : nextEmpty;
    if (mounted) _focusNodes[focusIndex].requestFocus();
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.hasError ? Colors.red.shade300 : Colors.grey.shade300;
    // AutofillGroup + the oneTimeCode hint on the first box is what lets
    // the OS (Android's SMS Retriever/Autofill framework, or iOS's Messages
    // integration) offer - and on tap, fill - the whole received SMS OTP
    // straight into this field, without any extra plugin. Only the first
    // box gets the hint: the OS always delivers the full code to whichever
    // field it's attached to, and the existing paste-style
    // TextInputFormatter below already spreads that multi-digit value
    // across the remaining boxes, so hinting every box would just cause
    // the same code to be stuffed into each one individually.
    return AutofillGroup(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(widget.length, (i) {
          return SizedBox(
            width: widget.boxWidth,
            height: widget.boxHeight,
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.backspace &&
                    _boxCtrls[i].text.isEmpty &&
                    i > 0) {
                  _boxCtrls[i - 1].clear();
                  _focusNodes[i - 1].requestFocus();
                  _emit();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _boxCtrls[i],
                focusNode: _focusNodes[i],
                autofocus: widget.autofocus && i == 0,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                autofillHints: i == 0 ? const [AutofillHints.oneTimeCode] : null,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  // A paste (or SMS autofill) can land the whole code in one
                  // box before maxLength trims it — catch that here and
                  // spread it across the remaining boxes instead of losing it.
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.length > 1) {
                      final pasted = newValue.text;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _spread(pasted, i);
                      });
                      return oldValue;
                    }
                    return newValue;
                  }),
                ],
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: widget.accent, width: 2)),
                ),
                onTap: () => _boxCtrls[i].selection =
                    TextSelection(baseOffset: 0, extentOffset: _boxCtrls[i].text.length),
                onChanged: (val) {
                  if (val.isNotEmpty && i < widget.length - 1) {
                    _focusNodes[i + 1].requestFocus();
                  }
                  _emit();
                },
              ),
            ),
          );
        }),
      ),
    );
  }
}
