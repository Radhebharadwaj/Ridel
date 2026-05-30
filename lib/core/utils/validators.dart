// Purana code replace kardo isse:
class AppValidators {
  static final List<String> _blockedDomains = [
    'tempmail.com',
    'mailinator.com',
    '10minutemail.com',
    'yopmail.com',
    'trashmail.com',
    'sharklasers.com',
    'guerrillamail.com',
    'dispostable.com',
  ];

  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';

    final domain = value.split('@').last.toLowerCase();

    // 🛡️ ANTI-BOT: Disposable domain check
    if (_blockedDomains.contains(domain)) {
      return 'Temp-mails are not allowed. Use Gmail/Yahoo.';
    }

    // Standard Email Regex
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email address';

    return null;
  }
}
