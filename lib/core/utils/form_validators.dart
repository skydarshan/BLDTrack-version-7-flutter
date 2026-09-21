class FormValidators {
  FormValidators._();

  static String? requiredField(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? email(String? value) {
    final required = requiredField(value, 'Email');
    if (required != null) return required;
    final email = value!.trim();
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!ok) return 'Enter a valid email';
    if (email.length > 254) return 'Email is too long';
    return null;
  }

  static String? password(String? value) {
    final required = requiredField(value, 'Password');
    if (required != null) return required;
    if (value!.length > 128) return 'Password is too long';
    return null;
  }

  static String? strongPassword(String? value) {
    final required = requiredField(value, 'Password');
    if (required != null) return required;
    if (value!.length < 8) return 'Password must be at least 8 characters';
    if (value.length > 128) return 'Password is too long';
    final ok = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(value);
    if (!ok) {
      return 'Use upper, lower, and a number';
    }
    return null;
  }

  static String? minLength(String? value, int min, String label) {
    final required = requiredField(value, label);
    if (required != null) return required;
    if (value!.trim().length < min) {
      return '$label must be at least $min characters';
    }
    return null;
  }

  static String? maxLength(String? value, int max, String label) {
    if (value == null) return null;
    if (value.trim().length > max) {
      return '$label must be at most $max characters';
    }
    return null;
  }
}
