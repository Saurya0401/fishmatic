import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

import 'package:fishmatic/account.dart';

void main() {
  testWidgets('Sign In Test', (tester) async {
    MockFirebaseAuth testAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'test_user', email: 'test@test.com'));
    await tester.pumpWidget(MaterialApp(home: LoginPage(testAuth: testAuth)));
    await tester.enterText(
        find.byKey(Key('login_email_field')), 'test@test.com');
    await tester.enterText(find.byKey(Key('login_password_field')), 'test');
    await tester.tap(find.widgetWithText(ElevatedButton, ' Login '));
    await tester.pumpAndSettle();
    expect(testAuth.currentUser.runtimeType, MockUser);
    expect(testAuth.currentUser!.uid, 'test_user');
  });
}
