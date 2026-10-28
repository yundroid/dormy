import 'package:dormy/data/repository.dart';
import 'package:dormy/features/auth/auth_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child) => MaterialApp(home: child);

  testWidgets('kayıt kodu ekranı e-postayı sabit gösterir ve kodu doğrular', (tester) async {
    await tester.pumpWidget(app(const VerifyCodePage(purpose: CodePurpose.signup, email: 'a@a.com')));
    expect(find.text('E-postanızı doğrulayın'), findsOneWidget);
    expect(find.text('a@a.com'), findsOneWidget);
    expect(find.text('Kodu tekrar gönder'), findsOneWidget);

    await tester.tap(find.text('Doğrula'));
    await tester.pump();
    expect(find.text('E-postadaki kodu girin'), findsOneWidget);

    // Sadece rakam kabul edilir
    await tester.enterText(find.widgetWithText(TextFormField, 'Kod'), '12ab34');
    expect(find.text('1234'), findsOneWidget);
  });

  testWidgets('davet ekranı e-posta ister, tekrar gönder yerine yöneticiye yönlendirir', (tester) async {
    await tester.pumpWidget(app(const VerifyCodePage(purpose: CodePurpose.invite)));
    expect(find.text('Davet kodu'), findsOneWidget);
    expect(find.text('Kodu tekrar gönder'), findsNothing);
    expect(find.textContaining('yöneticinizden daveti tekrar'), findsOneWidget);

    await tester.tap(find.text('Doğrula'));
    await tester.pump();
    expect(find.text('E-posta zorunlu'), findsOneWidget);
  });
}
