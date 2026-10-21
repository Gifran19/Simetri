import 'package:flutter/material.dart';
import '../services/security_service.dart';

/// Dialog input PIN Keamanan 4 Digit untuk otorisasi aksi kritis
class SecurityPinDialog extends StatefulWidget {
  final String actionTitle;
  final String actionDescription;
  final bool canUseBiometric;
  final VoidCallback? onBiometricTap;

  const SecurityPinDialog({
    super.key,
    required this.actionTitle,
    required this.actionDescription,
    this.canUseBiometric = false,
    this.onBiometricTap,
  });

  @override
  State<SecurityPinDialog> createState() => _SecurityPinDialogState();
}

class _SecurityPinDialogState extends State<SecurityPinDialog> {
  String _pin = '';
  bool _isError = false;
  String _errorMessage = '';

  void _onKeyTap(String value) async {
    if (_pin.length >= 4) return;

    setState(() {
      _pin += value;
      _isError = false;
    });

    if (_pin.length == 4) {
      final isValid = await SecurityService.verifyPin(_pin);
      if (isValid) {
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        if (!mounted) return;
        setState(() {
          _isError = true;
          _errorMessage = 'PIN Salah! Default PIN: 1234';
          _pin = '';
        });
      }
    }
  }

  void _onBackspace() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _isError = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xff0D1F3C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xff00D9A6).withValues(alpha: 0.3),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon Lock Shield
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xff00D9A6).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Color(0xff00D9A6),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 14),

                // Title & Action
                Text(
                  widget.actionTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.actionDescription,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 20),

                // 4 PIN Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final isFilled = index < _pin.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _isError
                            ? Colors.redAccent
                            : (isFilled ? const Color(0xff00D9A6) : Colors.white12),
                        shape: BoxShape.circle,
                        boxShadow: isFilled && !_isError
                            ? [
                                const BoxShadow(
                                  color: Color(0xff00D9A6),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    );
                  }),
                ),

                if (_isError) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Masukkan 4 digit PIN (Default: 1234)',
                    style: TextStyle(color: Colors.white38, fontSize: 10.5),
                  ),
                ],

                const SizedBox(height: 20),

                // Number Pad (1-9)
                _buildKeypad(),

                const SizedBox(height: 12),

                // Cancel Button
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'Batal',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _numButton('1'),
            _numButton('2'),
            _numButton('3'),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _numButton('4'),
            _numButton('5'),
            _numButton('6'),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _numButton('7'),
            _numButton('8'),
            _numButton('9'),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Biometric button if available
            if (widget.canUseBiometric)
              IconButton(
                onPressed: widget.onBiometricTap,
                icon: const Icon(Icons.fingerprint_rounded, color: Color(0xff00D9A6), size: 28),
                tooltip: 'Gunakan Biometrik',
              )
            else
              const SizedBox(width: 52, height: 52),
            _numButton('0'),
            IconButton(
              onPressed: _onBackspace,
              icon: const Icon(Icons.backspace_outlined, color: Colors.white60, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  Widget _numButton(String text) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onKeyTap(text),
        borderRadius: BorderRadius.circular(26),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xff10233F),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Center(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
