import 'package:flutter_test/flutter_test.dart';
// Note: 'india_tour' aapke project ka package name hai, ise change mat karna agar folder name wahi hai
import 'package:ridel/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // 1. Yahan hamne 'MyApp' ko 'RidelApp' kar diya hai
    await tester.pumpWidget(const RidelApp());

    // 2. Hamne counter wala logic hata diya kyunki wo ab exist nahi karta
    // Sirf ye check karega ki app crash to nahi ho rahi
    expect(find.byType(RidelApp), findsOneWidget);
  });
}
