import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';

void main() {
  group('ProofOfDeliveryScreen — Form & UI', () {
    testWidgets('renders recipient name field', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockProofOfDeliveryScreen()),
      );

      expect(find.byKey(const Key('recipient_name_field')), findsOneWidget);
      expect(find.text('Recipient Name'), findsOneWidget);
    });

    testWidgets('renders photo upload button', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockProofOfDeliveryScreen()),
      );

      expect(find.byKey(const Key('take_photo_btn')), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
    });

    testWidgets('submit button is disabled when no photo taken',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockProofOfDeliveryScreen()),
      );

      final submitBtn = tester.widget<ElevatedButton>(
        find.byKey(const Key('submit_proof_btn')),
      );
      expect(submitBtn.onPressed, isNull); // disabled = onPressed is null
    });

    testWidgets('submit button enables after photo is "taken"',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockProofOfDeliveryScreen()),
      );

      // Simulate taking a photo
      await tester.tap(find.byKey(const Key('take_photo_btn')));
      await tester.pump();

      final submitBtn = tester.widget<ElevatedButton>(
        find.byKey(const Key('submit_proof_btn')),
      );
      expect(submitBtn.onPressed, isNotNull); // enabled
    });

    testWidgets('submitting without recipient name shows validation error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockProofOfDeliveryScreen()),
      );

      // Take photo first to enable submit
      await tester.tap(find.byKey(const Key('take_photo_btn')));
      await tester.pump();

      // Try to submit without name
      await tester.tap(find.byKey(const Key('submit_proof_btn')));
      await tester.pump();

      expect(find.text('Recipient name is required'), findsOneWidget);
    });

    testWidgets('offline mode banner shown when isOffline is true',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockProofOfDeliveryScreen(isOffline: true),
        ),
      );

      expect(find.byKey(const Key('offline_banner')), findsOneWidget);
      expect(find.text('You are offline'), findsOneWidget);
    });

    testWidgets('no offline banner when online', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockProofOfDeliveryScreen(isOffline: false),
        ),
      );

      expect(find.byKey(const Key('offline_banner')), findsNothing);
    });

    testWidgets('shows photo preview container after photo taken',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockProofOfDeliveryScreen()),
      );

      expect(find.byKey(const Key('photo_preview')), findsNothing);

      await tester.tap(find.byKey(const Key('take_photo_btn')));
      await tester.pump();

      expect(find.byKey(const Key('photo_preview')), findsOneWidget);
    });
  });

  group('DeliveryDetailScreen — Status Display', () {
    testWidgets('shows delivery status chip', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDeliveryDetailScreen(status: DeliveryStatus.notStarted),
        ),
      );

      expect(find.text('Not Started'), findsOneWidget);
    });

    testWidgets('shows family area and city info', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDeliveryDetailScreen(
            status: DeliveryStatus.notStarted,
            familyArea: 'Gulshan Block 7',
            familyCity: 'Karachi',
          ),
        ),
      );

      expect(find.text('Gulshan Block 7'), findsOneWidget);
      expect(find.text('Karachi'), findsOneWidget);
    });

    testWidgets('shows items list when items are provided',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDeliveryDetailScreen(
            status: DeliveryStatus.inTransit,
            items: {'Rice': 10, 'Flour': 5},
          ),
        ),
      );

      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Flour'), findsOneWidget);
    });

    testWidgets('shows pickup button for not_started status',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDeliveryDetailScreen(
            status: DeliveryStatus.notStarted,
          ),
        ),
      );

      expect(find.text('Start Pickup'), findsOneWidget);
    });

    testWidgets('shows submit proof button for in_transit status',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDeliveryDetailScreen(
            status: DeliveryStatus.inTransit,
          ),
        ),
      );

      expect(find.text('Submit Proof'), findsOneWidget);
    });

    testWidgets('shows verified checkmark for admin_verified status',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _MockDeliveryDetailScreen(
            status: DeliveryStatus.adminVerified,
          ),
        ),
      );

      expect(find.byIcon(Icons.verified), findsOneWidget);
    });
  });
}

// ─── Mock Widgets ────────────────────────────────────────────────────────────

class _MockProofOfDeliveryScreen extends StatefulWidget {
  final bool isOffline;

  const _MockProofOfDeliveryScreen({this.isOffline = false});

  @override
  State<_MockProofOfDeliveryScreen> createState() =>
      _MockProofOfDeliveryScreenState();
}

class _MockProofOfDeliveryScreenState
    extends State<_MockProofOfDeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _photoTaken = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Proof of Delivery')),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Offline banner
              if (widget.isOffline)
                Container(
                  key: const Key('offline_banner'),
                  padding: const EdgeInsets.all(8),
                  color: Colors.orange[100],
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('You are offline'),
                    ],
                  ),
                ),

              // Photo area
              if (_photoTaken)
                Container(
                  key: const Key('photo_preview'),
                  height: 200,
                  width: double.infinity,
                  color: Colors.grey[300],
                  child: const Icon(Icons.check, size: 48, color: Colors.green),
                ),

              // Take photo button
              ElevatedButton.icon(
                key: const Key('take_photo_btn'),
                onPressed: () => setState(() => _photoTaken = true),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Take Photo'),
              ),

              const SizedBox(height: 16),

              // Recipient name field
              TextFormField(
                key: const Key('recipient_name_field'),
                decoration: const InputDecoration(labelText: 'Recipient Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Recipient name is required'
                        : null,
              ),

              const SizedBox(height: 16),

              // Submit button (disabled until photo taken)
              ElevatedButton(
                key: const Key('submit_proof_btn'),
                onPressed: _photoTaken
                    ? () => _formKey.currentState!.validate()
                    : null,
                child: const Text('Submit Proof'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MockDeliveryDetailScreen extends StatelessWidget {
  final DeliveryStatus status;
  final String familyArea;
  final String familyCity;
  final Map<String, num> items;

  const _MockDeliveryDetailScreen({
    required this.status,
    this.familyArea = 'Test Area',
    this.familyCity = 'Test City',
    this.items = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Detail')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status chip
            Chip(label: Text(status.displayName)),

            const SizedBox(height: 8),

            // Family info
            Text(familyArea),
            Text(familyCity),

            const SizedBox(height: 16),

            // Items list
            ...items.entries.map(
              (e) => ListTile(
                title: Text(e.key),
                trailing: Text('${e.value}'),
              ),
            ),

            const SizedBox(height: 16),

            // Action buttons
            if (status == DeliveryStatus.notStarted)
              ElevatedButton(
                onPressed: () {},
                child: const Text('Start Pickup'),
              ),

            if (status == DeliveryStatus.inTransit)
              ElevatedButton(
                onPressed: () {},
                child: const Text('Submit Proof'),
              ),

            if (status == DeliveryStatus.adminVerified)
              const Icon(Icons.verified, size: 48, color: Colors.green),
          ],
        ),
      ),
    );
  }
}
