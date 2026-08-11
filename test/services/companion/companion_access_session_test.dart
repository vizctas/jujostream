import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:jujostream/services/companion/companion_access_session.dart';

void main() {
  test('accepts only exact high-entropy session token', () {
    final session = CompanionAccessSession.create(random: Random(7));

    expect(session.token.length, greaterThanOrEqualTo(40));
    expect(session.accepts(session.token), isTrue);
    expect(session.accepts('${session.token}x'), isFalse);
    expect(session.accepts(session.token.replaceFirst('A', 'B')), isFalse);
  });
}
