import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/models/donation_model.dart';

void main() {
  group('CreateDonationScreen — Form Validation', () {
    testWidgets('renders donation type selector (Cash / In-Kind)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockCreateDonationScreen()),
      );

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('In-Kind'), findsOneWidget);
    });

    testWidgets('Cash type shows amount field', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockCreateDonationScreen()),
      );

      // Cash is selected by default
      expect(find.byKey(const Key('amount_field')), findsOneWidget);
    });

    testWidgets(
        'switching to In-Kind hides amount field and shows item section',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockCreateDonationScreen()),
      );

      await tester.tap(find.text('In-Kind'));
      await tester.pump();

      expect(find.byKey(const Key('amount_field')), findsNothing);
      expect(find.byKey(const Key('items_section')), findsOneWidget);
    });

    testWidgets('submitting empty cash amount shows validation error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockCreateDonationScreen()),
      );

      await tester.tap(find.text('Submit Donation'));
      await tester.pump();

      expect(find.text('Amount is required'), findsOneWidget);
    });

    testWidgets('submitting zero amount shows validation error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockCreateDonationScreen()),
      );

      await tester.enterText(
          find.byKey(const Key('amount_field')), '0');
      await tester.tap(find.text('Submit Donation'));
      await tester.pump();

      expect(find.text('Amount must be greater than 0'), findsOneWidget);
    });

    testWidgets('valid amount passes validation', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockCreateDonationScreen()),
      );

      await tester.enterText(
          find.byKey(const Key('amount_field')), '5000');
      await tester.tap(find.text('Submit Donation'));
      await tester.pump();

      expect(find.text('Amount is required'), findsNothing);
      expect(find.text('Amount must be greater than 0'), findsNothing);
    });

    testWidgets('anonymous donation toggle is present',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockCreateDonationScreen()),
      );

      expect(find.byType(Switch), findsOneWidget);
      expect(find.text('Anonymous'), findsOneWidget);
    });

    testWidgets('anonymous toggle can be switched on/off',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockCreateDonationScreen()),
      );

      final switchFinder = find.byType(Switch);
      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, false); // default off

      await tester.tap(switchFinder);
      await tester.pump();

      final updatedSwitch = tester.widget<Switch>(switchFinder);
      expect(updatedSwitch.value, true); // now on
    });

    testWidgets('optional donation note field is present',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockCreateDonationScreen()),
      );

      expect(find.byKey(const Key('note_field')), findsOneWidget);
    });

    testWidgets('DonationStatus enum covers all 11 states',
        (WidgetTester tester) async {
      // This is a logic test wrapped in a widget test for convenience
      expect(DonationStatus.values.length, 11);
    });
  });

  group('DonationTrackingScreen — Status Stepper', () {
    testWidgets('renders status timeline for a verified donation',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDonationTrackingScreen(
            status: DonationStatus.verified,
          ),
        ),
      );

      expect(find.text('Verified'), findsWidgets);
    });

    testWidgets('renders status timeline for a delivered donation',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDonationTrackingScreen(
            status: DonationStatus.delivered,
          ),
        ),
      );

      expect(find.text('Delivered'), findsWidgets);
    });

    testWidgets('shows rejected badge for rejected donation',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDonationTrackingScreen(
            status: DonationStatus.rejected,
          ),
        ),
      );

      expect(find.text('Rejected'), findsOneWidget);
    });

    testWidgets('shows current status label prominently',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDonationTrackingScreen(
            status: DonationStatus.outForDelivery,
          ),
        ),
      );

      expect(find.text('Current Status'), findsOneWidget);
      expect(find.text('Out for Delivery'), findsWidgets);
    });
  });
}

// ─── Mock Widgets ────────────────────────────────────────────────────────────

class _MockCreateDonationScreen extends StatefulWidget {
  @override
  State<_MockCreateDonationScreen> createState() =>
      _MockCreateDonationScreenState();
}

class _MockCreateDonationScreenState
    extends State<_MockCreateDonationScreen> {
  final _formKey = GlobalKey<FormState>();
  DonationType _selectedType = DonationType.cash;
  bool _isAnonymous = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Donation')),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Donation type selector
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Cash'),
                    selected: _selectedType == DonationType.cash,
                    onSelected: (_) =>
                        setState(() => _selectedType = DonationType.cash),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('In-Kind'),
                    selected: _selectedType == DonationType.inKind,
                    onSelected: (_) =>
                        setState(() => _selectedType = DonationType.inKind),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Cash: Amount field
              if (_selectedType == DonationType.cash)
                TextFormField(
                  key: const Key('amount_field'),
                  decoration: const InputDecoration(labelText: 'Amount (PKR)'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Amount is required';
                    final amount = double.tryParse(v);
                    if (amount == null || amount <= 0) {
                      return 'Amount must be greater than 0';
                    }
                    return null;
                  },
                ),

              // In-Kind: Items section
              if (_selectedType == DonationType.inKind)
                Container(
                  key: const Key('items_section'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Add Items'),
                ),

              const SizedBox(height: 12),

              // Anonymous toggle
              Row(
                children: [
                  const Text('Anonymous'),
                  const SizedBox(width: 8),
                  Switch(
                    value: _isAnonymous,
                    onChanged: (val) => setState(() => _isAnonymous = val),
                  ),
                ],
              ),

              // Optional note
              TextFormField(
                key: const Key('note_field'),
                decoration: const InputDecoration(
                  labelText: 'Donation Note (Optional)',
                ),
              ),

              const SizedBox(height: 16),

              // Submit button
              ElevatedButton(
                onPressed: () => _formKey.currentState!.validate(),
                child: const Text('Submit Donation'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MockDonationTrackingScreen extends StatelessWidget {
  final DonationStatus status;

  const _MockDonationTrackingScreen({required this.status});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Donation Tracking')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            const Text('Current Status',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Chip(
              label: Text(status.displayName),
              backgroundColor: status == DonationStatus.rejected
                  ? Colors.red[100]
                  : status == DonationStatus.delivered
                      ? Colors.green[100]
                      : Colors.blue[100],
            ),
            const SizedBox(height: 24),
            // Status steps
            ...DonationStatus.values
                .where((s) =>
                    s != DonationStatus.rejected &&
                    s != DonationStatus.closed)
                .map((s) => ListTile(
                      leading: Icon(
                        s.index <= status.index
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: s.index <= status.index
                            ? Colors.green
                            : Colors.grey,
                      ),
                      title: Text(s.displayName),
                    )),
          ],
        ),
      ),
      ),
    );
  }
}
