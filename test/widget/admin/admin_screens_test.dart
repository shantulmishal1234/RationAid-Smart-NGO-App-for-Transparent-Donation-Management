import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FamilyReviewScreen — Filtering & List', () {
    testWidgets('renders filter chips: Pending, Approved, Rejected',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockFamilyReviewScreen()),
      );

      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
    });

    testWidgets('renders family list items', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockFamilyReviewScreen()),
      );

      expect(find.byKey(const Key('family_card_0')), findsOneWidget);
      expect(find.byKey(const Key('family_card_1')), findsOneWidget);
    });

    testWidgets('each family card has Approve and Reject buttons',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockFamilyReviewScreen()),
      );

      expect(find.text('Approve'), findsWidgets);
      expect(find.text('Reject'), findsWidgets);
    });

    testWidgets('filtering by Approved shows only approved families',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockFamilyReviewScreen()),
      );

      await tester.tap(find.text('Approved'));
      await tester.pump();

      // Only approved families visible
      expect(find.text('Approved Family'), findsOneWidget);
      expect(find.text('Pending Family'), findsNothing);
    });

    testWidgets('filtering by Pending shows only pending families',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockFamilyReviewScreen()),
      );

      await tester.tap(find.text('Pending'));
      await tester.pump();

      expect(find.text('Pending Family'), findsOneWidget);
      expect(find.text('Approved Family'), findsNothing);
    });

    testWidgets('quorum badge shown when quorum is reached',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockFamilyReviewScreen()),
      );

      expect(find.text('Quorum Reached'), findsOneWidget);
    });
  });

  group('PackManagementScreen — Pack List & Creation', () {
    testWidgets('renders list of assistance packs', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockPackManagementScreen()),
      );

      expect(find.text('Basic Food Pack'), findsOneWidget);
      expect(find.text('Medicine Pack'), findsOneWidget);
    });

    testWidgets('each pack shows budget amount', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockPackManagementScreen()),
      );

      expect(find.text('PKR 15,000'), findsOneWidget);
      expect(find.text('PKR 8,000'), findsOneWidget);
    });

    testWidgets('FAB is present to add new pack', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockPackManagementScreen()),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('tapping FAB opens add pack dialog', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockPackManagementScreen()),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      expect(find.byKey(const Key('pack_form_dialog')), findsOneWidget);
    });

    testWidgets('each pack card shows edit and delete buttons',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockPackManagementScreen()),
      );

      expect(find.byIcon(Icons.edit), findsWidgets);
      expect(find.byIcon(Icons.delete), findsWidgets);
    });

    testWidgets('tapping delete shows confirmation dialog',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockPackManagementScreen()),
      );

      await tester.tap(find.byIcon(Icons.delete).first);
      await tester.pump();

      expect(find.text('Delete Pack?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('AuditTrailScreen — Log Display', () {
    testWidgets('renders audit log entries', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockAuditTrailScreen()),
      );

      expect(find.text('donate'), findsOneWidget);
      expect(find.text('allocate'), findsOneWidget);
    });

    testWidgets('each entry shows action, amount and actor',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockAuditTrailScreen()),
      );

      expect(find.text('PKR 5,000'), findsOneWidget);
      expect(find.text('Admin User'), findsWidgets);
    });

    testWidgets('title shows Audit Trail', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _MockAuditTrailScreen()),
      );

      expect(find.text('Audit Trail'), findsOneWidget);
    });
  });
}

// ─── Mock Widgets ─────────────────────────────────────────────────────────────

class _MockFamilyReviewScreen extends StatefulWidget {
  @override
  State<_MockFamilyReviewScreen> createState() =>
      _MockFamilyReviewScreenState();
}

class _MockFamilyReviewScreenState extends State<_MockFamilyReviewScreen> {
  String _selectedFilter = 'All';

  final _families = [
    {'id': '0', 'name': 'Pending Family', 'status': 'pending', 'quorumReached': false},
    {'id': '1', 'name': 'Approved Family', 'status': 'approved', 'quorumReached': true},
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedFilter == 'All'
        ? _families
        : _families.where((f) {
            if (_selectedFilter == 'Pending') return f['status'] == 'pending';
            if (_selectedFilter == 'Approved') return f['status'] == 'approved';
            if (_selectedFilter == 'Rejected') return f['status'] == 'rejected';
            return true;
          }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Family Review')),
      body: Column(
        children: [
          // Filter chips
          Row(
            children: ['Pending', 'Approved', 'Rejected'].map((filter) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: FilterChip(
                  label: Text(filter),
                  selected: _selectedFilter == filter,
                  onSelected: (_) =>
                      setState(() => _selectedFilter = filter),
                ),
              );
            }).toList(),
          ),

          // Family list
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final family = filtered[index];
                return Card(
                  key: Key('family_card_${family['id']}'),
                  child: ListTile(
                    title: Text(family['name'] as String),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (family['quorumReached'] == true)
                          const Chip(
                            label: Text('Quorum Reached'),
                            backgroundColor: Colors.green,
                          ),
                        Row(
                          children: [
                            TextButton(
                                onPressed: () {}, child: const Text('Approve')),
                            TextButton(
                                onPressed: () {}, child: const Text('Reject')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MockPackManagementScreen extends StatefulWidget {
  @override
  State<_MockPackManagementScreen> createState() =>
      _MockPackManagementScreenState();
}

class _MockPackManagementScreenState extends State<_MockPackManagementScreen> {
  bool _showDialog = false;
  bool _showDeleteDialog = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pack Management')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _showDialog = true),
        child: const Icon(Icons.add),
      ),
      body: Stack(
        children: [
          ListView(
            children: [
              _packCard('Basic Food Pack', 'PKR 15,000'),
              _packCard('Medicine Pack', 'PKR 8,000'),
            ],
          ),
          if (_showDialog)
            Center(
              child: Card(
                key: const Key('pack_form_dialog'),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Add New Pack'),
                      TextButton(
                        onPressed: () => setState(() => _showDialog = false),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_showDeleteDialog)
            AlertDialog(
              title: const Text('Delete Pack?'),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _showDeleteDialog = false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => setState(() => _showDeleteDialog = false),
                  child: const Text('Delete'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _packCard(String name, String budget) {
    return Card(
      child: ListTile(
        title: Text(name),
        subtitle: Text(budget),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => setState(() => _showDeleteDialog = true),
            ),
          ],
        ),
      ),
    );
  }
}

class _MockAuditTrailScreen extends StatelessWidget {
  final _entries = [
    {'action': 'donate', 'amount': 'PKR 5,000', 'actor': 'Admin User'},
    {'action': 'allocate', 'amount': 'PKR 3,000', 'actor': 'Admin User'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Trail')),
      body: ListView.builder(
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return ListTile(
            title: Text(entry['action']!),
            subtitle: Text(entry['actor']!),
            trailing: Text(entry['amount']!),
          );
        },
      ),
    );
  }
}
