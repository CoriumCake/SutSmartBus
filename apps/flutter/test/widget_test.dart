import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sut_smart_bus/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows consent gate for a first-time user',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(
        child: SutSmartBusApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('ข้อกำหนดการใช้บริการ'), findsOneWidget);
    expect(find.text('ยินยอม'), findsOneWidget);
    expect(find.text('ปฏิเสธ'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsNothing);
    expect(find.text('Read the Terms of Service to continue.'), findsNothing);
    expect(find.textContaining('Effective date'), findsNothing);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Accept Terms'), findsOneWidget);

    await tester.ensureVisible(find.text('Accept Terms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept Terms'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
  });
}
