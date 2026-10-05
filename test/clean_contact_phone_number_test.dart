import 'package:flutter_test/flutter_test.dart';
import 'package:vaani/features/customers/screens/customer_list_screen.dart';

/// A phone number picked via the OS contacts picker arrives in whatever
/// format the contact was saved in — this is the normalization that makes
/// it match the bare 10-digit numbers the rest of the app's duplicate-phone
/// checks and OTP flow expect.
void main() {
  test('a bare 10-digit number passes through unchanged', () {
    expect(cleanContactPhoneNumber('9876543210'), '9876543210');
  });

  test('a +91-prefixed number loses the country code', () {
    expect(cleanContactPhoneNumber('+91 98765 43210'), '9876543210');
  });

  test('a number with a leading trunk 0 loses it', () {
    expect(cleanContactPhoneNumber('09876543210'), '9876543210');
  });

  test('punctuation and spaces are stripped regardless of grouping', () {
    expect(cleanContactPhoneNumber('(987) 654-3210'), '9876543210');
  });

  test('91 without a plus sign is still recognized as the country code', () {
    expect(cleanContactPhoneNumber('919876543210'), '9876543210');
  });

  test('an empty or non-numeric string returns null', () {
    expect(cleanContactPhoneNumber(''), isNull);
    expect(cleanContactPhoneNumber('   '), isNull);
  });

  test('an unrecognized length is returned as-is (digits only), never dropped', () {
    expect(cleanContactPhoneNumber('12345'), '12345');
  });
}
