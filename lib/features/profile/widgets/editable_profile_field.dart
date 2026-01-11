import 'package:flutter/material.dart';

class EditableProfileField extends StatefulWidget {
  final String label;
  final String initialValue;
  final IconData icon;
  final String dbKey;
  final bool isReadOnly;
  final bool isEnabled;
  final TextEditingController controller;

  const EditableProfileField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.icon,
    required this.dbKey,
    this.isReadOnly = false,
    required this.isEnabled,
    required this.controller,
  });

  @override
  State<EditableProfileField> createState() => _EditableProfileFieldState();
}

class _EditableProfileFieldState extends State<EditableProfileField> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF131313),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: widget.isEnabled
                    ? Colors.blueAccent
                    : Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: Colors.grey.shade600, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  enabled: widget.isEnabled && !widget.isReadOnly,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 16)),
                ),
              ),
              if (!widget.isReadOnly && widget.isEnabled)
                 Icon(Icons.edit_rounded,
                     color: Colors.blueAccent,
                     size: 18),
            ],
          ),
        ),
      ],
    );
  }
}
