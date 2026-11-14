import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/password_policy.dart';

class PasswordPolicyField extends StatefulWidget {
  const PasswordPolicyField({
    super.key,
    required this.controller,
    required this.label,
    this.confirmationOf,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final TextEditingController? confirmationOf;
  final bool enabled;

  @override
  State<PasswordPolicyField> createState() => _PasswordPolicyFieldState();
}

class _PasswordPolicyFieldState extends State<PasswordPolicyField> {
  bool _isVisible = false;

  @override
  Widget build(BuildContext context) {
    final confirmationOf = widget.confirmationOf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: !_isVisible,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) => confirmationOf == null
              ? PasswordPolicy.validate(value)
              : value == null || value.isEmpty
              ? 'Confirm your password'
              : value != confirmationOf.text
              ? 'Passwords do not match'
              : null,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _isVisible ? 'Hide password' : 'Show password',
              onPressed: widget.enabled
                  ? () => setState(() => _isVisible = !_isVisible)
                  : null,
              icon: Icon(_isVisible ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
        if (confirmationOf == null) ...[
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Requirement(
                  label: 'At least 8 characters',
                  isMet: PasswordPolicy.hasMinimumLength(
                    widget.controller.text,
                  ),
                ),
                _Requirement(
                  label: 'One uppercase letter (A–Z)',
                  isMet: PasswordPolicy.hasUppercase(widget.controller.text),
                ),
                _Requirement(
                  label: 'One lowercase letter (a–z)',
                  isMet: PasswordPolicy.hasLowercase(widget.controller.text),
                ),
                _Requirement(
                  label: 'One number (0–9)',
                  isMet: PasswordPolicy.hasNumber(widget.controller.text),
                ),
                _Requirement(
                  label: 'One special symbol',
                  isMet: PasswordPolicy.hasSpecialCharacter(
                    widget.controller.text,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          AnimatedBuilder(
            animation: Listenable.merge([widget.controller, confirmationOf]),
            builder: (context, _) {
              final matches =
                  widget.controller.text.isNotEmpty &&
                  widget.controller.text == confirmationOf.text;
              return Row(
                children: [
                  Icon(
                    matches ? Icons.check_circle : Icons.info_outline,
                    size: 15,
                    color: matches ? AppColors.green : AppColors.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      matches
                          ? 'Passwords match'
                          : 'Enter the same password again',
                      style: TextStyle(
                        color: matches ? AppColors.green : AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _Requirement extends StatelessWidget {
  const _Requirement({required this.label, required this.isMet});

  final String label;
  final bool isMet;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Icon(
          isMet ? Icons.check_circle : Icons.circle_outlined,
          size: 14,
          color: isMet ? AppColors.green : AppColors.muted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            softWrap: true,
            style: TextStyle(
              color: isMet ? AppColors.green : AppColors.muted,
              fontSize: 11,
            ),
          ),
        ),
      ],
    ),
  );
}
