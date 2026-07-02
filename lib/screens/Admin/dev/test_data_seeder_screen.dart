// ════════════════════════════════════════════════════════════════════════════
// 🧪 TEST DATA SEEDER  —  DEBUG ONLY (kDebugMode)
// Invisible in production / release builds.
// ════════════════════════════════════════════════════════════════════════════
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:ration_aid/theme/app_colors.dart';

class TestDataSeederScreen extends StatefulWidget {
  const TestDataSeederScreen({super.key});

  @override
  State<TestDataSeederScreen> createState() => _TestDataSeederScreenState();
}

class _TestDataSeederScreenState extends State<TestDataSeederScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  LatLng? _pickedLocation;
  bool _gettingGps = false;
  bool _isSeeding = false;
  bool _isDeleting = false;
  int _testDocCount = 0;
  String _log = '';

  List<Map<String, String>> _distributors = [];
  String? _selectedDistributorId;
  String? _selectedDistributorName;
  bool _loadingDistributors = true;

  static const _testTag = 'isTestData';

  @override
  void initState() {
    super.initState();
    _loadDistributors();
    _countTestDocs();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _log_(String msg) {
    if (mounted) setState(() => _log = msg);
  }

  Future<void> _loadDistributors() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('roles', arrayContains: 'distributor')
          .get();
      if (!mounted) return;
      setState(() {
        _distributors = snap.docs
            .map((d) => {
                  'id': d.id,
                  'name': (d.data()['name'] ??
                          d.data()['display_name'] ??
                          d.data()['email'] ??
                          'Unknown')
                      .toString(),
                })
            .toList();
        _loadingDistributors = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingDistributors = false);
      _log_('⚠️ Failed to load distributors: $e');
    }
  }

  Future<void> _countTestDocs() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('delivery_assignments')
          .where(_testTag, isEqualTo: true)
          .get();
      if (mounted) setState(() => _testDocCount = snap.docs.length);
    } catch (_) {}
  }

  Future<void> _getGps() async {
    setState(() => _gettingGps = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _log_('❌ Location permission permanently denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() => _pickedLocation = LatLng(pos.latitude, pos.longitude));
        _log_('📍 Current GPS set as family location');
      }
    } catch (e) {
      _log_('⚠️ GPS error: $e');
    } finally {
      if (mounted) setState(() => _gettingGps = false);
    }
  }

  Future<void> _openMapPicker() async {
    final initial = _pickedLocation ?? const LatLng(31.5204, 74.3587);
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => _MapPickerPage(initialCenter: initial),
      ),
    );
    if (result != null && mounted) {
      setState(() => _pickedLocation = result);
      _log_(
        '📍 Family location set:\n'
        '${result.latitude.toStringAsFixed(6)}, '
        '${result.longitude.toStringAsFixed(6)}',
      );
    }
  }

  // ── Seeding ────────────────────────────────────────────────────────────────

  Future<void> _seed(_Scenario scenario) async {
    if (_pickedLocation == null) {
      _log_('⚠️ Pick a family location first (Step 1)');
      return;
    }
    if (_selectedDistributorId == null) {
      _log_('⚠️ Select a distributor first (Step 2)');
      return;
    }

    setState(() {
      _isSeeding = true;
      _log = '⏳ Seeding "${scenario.label}"…';
    });

    try {
      final db = FirebaseFirestore.instance;
      final now = DateTime.now();
      final ts = Timestamp.fromDate(now);
      final epoch = now.millisecondsSinceEpoch;

      final familyId = 'TEST_family_${scenario.key}_$epoch';
      final procId = 'TEST_proc_${scenario.key}_$epoch';
      final donationId = 'TEST_donation_${scenario.key}_$epoch';
      final assignId = 'TEST_assign_${scenario.key}_$epoch';

      // 1. Family
      await db.collection('families').doc(familyId).set({
        'familyId': familyId,
        'familyArea': '[TEST] ${scenario.area}',
        'familyCity': scenario.city,
        'familyAddress': '${scenario.area}, ${scenario.city}',
        'familyPhone': '03001234567',
        'familySize': 5,
        'familyGeoLat': _pickedLocation!.latitude,
        'familyGeoLng': _pickedLocation!.longitude,
        'familyLocationVerified': true,
        'fulfillmentStatus': scenario.familyStatus,
        _testTag: true,
        'createdAt': ts,
        'updatedAt': ts,
      });

      // 2. Procurement
      await db.collection('procurement_requests').doc(procId).set({
        'status': 'in_transit',
        _testTag: true,
        'createdAt': ts,
        'updatedAt': ts,
      });

      // 3. Donation
      await db.collection('donations').doc(donationId).set({
        'familyId': familyId,
        'donorId': 'test_donor_uid',
        'status': 'out_for_delivery',
        'amount': 5000,
        _testTag: true,
        'createdAt': ts,
        'updatedAt': ts,
      });

      // 4. Delivery assignment
      final Map<String, dynamic> aData = {
        'familyId': familyId,
        'familyArea': '[TEST] ${scenario.area}',
        'familyCity': scenario.city,
        'familyAddress': '${scenario.area}, ${scenario.city}',
        'familyPhone': '03001234567',
        'familySize': 5,
        'familyGeoLat': _pickedLocation!.latitude,
        'familyGeoLng': _pickedLocation!.longitude,
        'familyLocationVerified': true,
        'assignedDistributorId': scenario.preAssign ? _selectedDistributorId : null,
        'assignedDistributorName': scenario.preAssign ? _selectedDistributorName : null,
        'assignedPackName': '[TEST] Standard Ration Pack',
        'items': const {'Rice': 10, 'Sugar': 5, 'Flour': 20, 'Oil': 4},
        'itemUnits': const {'Rice': 'kg', 'Sugar': 'kg', 'Flour': 'kg', 'Oil': 'L'},
        'inKindCoveredItems': <String>[],
        'status': scenario.status,
        'procurementRequestId': procId,
        'donationIds': [donationId],
        'adminVerified': false,
        'adminNote': '🧪 TEST assignment — delete via Dev Tools when done.',
        _testTag: true,
        'createdAt': ts,
        'updatedAt': ts,
      };

      if (scenario.addPickedUpAt) {
        aData['pickedUpAt'] = Timestamp.fromDate(now.subtract(const Duration(hours: 2)));
      }
      if (scenario.addInTransitAt) {
        aData['inTransitAt'] = Timestamp.fromDate(now.subtract(const Duration(hours: 1)));
      }
      if (scenario.addFailedAt) {
        aData['failedAt'] = ts;
        aData['failureReason'] = 'other';
        aData['failureNotes'] =
            'Proof rejected by Administrator (test@admin.com). [TEST]';
      }
      if (scenario.addDeliveredAt) {
        aData['deliveredAt'] =
            Timestamp.fromDate(now.subtract(const Duration(minutes: 30)));
        aData['proofPhotoUrl'] =
            'https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/'
            'PNG_transparency_demonstration_1.png/280px-PNG_transparency_demonstration_1.png';
        aData['proofGeoLat'] = _pickedLocation!.latitude;
        aData['proofGeoLng'] = _pickedLocation!.longitude;
        aData['proofTimestamp'] =
            Timestamp.fromDate(now.subtract(const Duration(minutes: 30)));
        aData['proofAddress'] = '${scenario.area}, ${scenario.city}';
      }

      await db.collection('delivery_assignments').doc(assignId).set(aData);
      await _countTestDocs();

      _log_(
        '✅ Seeded "${scenario.label}"\n'
        'Assignment ID: $assignId\n'
        'Family GPS: ${_pickedLocation!.latitude.toStringAsFixed(5)}, '
        '${_pickedLocation!.longitude.toStringAsFixed(5)}\n'
        '\n'
        'Now log in as distributor to test.',
      );
    } catch (e) {
      _log_('❌ Seed failed: $e');
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  Future<void> _seedAll() async {
    for (final s in _Scenario.all) {
      await _seed(s);
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🗑️ Delete All Test Data'),
        content: const Text(
          'Deletes every document with isTestData==true from:\n'
          '• delivery_assignments\n'
          '• families\n'
          '• donations\n'
          '• procurement_requests\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _isDeleting = true;
      _log = '⏳ Deleting test data…';
    });

    try {
      final db = FirebaseFirestore.instance;
      int total = 0;
      for (final col in [
        'delivery_assignments',
        'families',
        'donations',
        'procurement_requests',
      ]) {
        final snap =
            await db.collection(col).where(_testTag, isEqualTo: true).get();
        if (snap.docs.isNotEmpty) {
          final batch = db.batch();
          for (final d in snap.docs) {
            batch.delete(d.reference);
          }
          await batch.commit();
        }
        total += snap.docs.length;
      }
      _log_('🗑️ Deleted $total test documents.');
      await _countTestDocs();
    } catch (e) {
      _log_('❌ Cleanup failed: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('Available in debug builds only.')),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          '🧪 Test Data Seeder',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (_testDocCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_testDocCount test docs',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Debug banner ─────────────────────────────────────────────
            _infoBanner(
              icon: Icons.warning_amber_rounded,
              color: Colors.orange,
              title: 'DEBUG MODE ONLY',
              body: 'This screen is invisible in production. All seeded '
                  'documents have [TEST] prefix and can be deleted below.',
              isDark: isDark,
            ),
            const SizedBox(height: 20),

            // ── Step 1: Location ─────────────────────────────────────────
            _heading('Step 1 — Set Family Location', isDark),
            const SizedBox(height: 4),
            Text(
              'Choose a real location in your city you can walk/drive to. '
              'The cyan circle on the map shows the 50 m geofence boundary.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),

            // Map preview
            if (_pickedLocation != null) _mapPreview() else _mapPlaceholder(isDark),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _gettingGps ? null : _getGps,
                    icon: _gettingGps
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.gps_fixed, size: 16),
                    label: const Text('Use My GPS'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.volunteerBlue,
                      side: const BorderSide(color: AppColors.volunteerBlue),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _openMapPicker,
                    icon: const Icon(Icons.map, size: 16),
                    label: Text(
                      _pickedLocation == null ? 'Pick on Map' : 'Change Location',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Step 2: Distributor ──────────────────────────────────────
            _heading('Step 2 — Select Distributor', isDark),
            const SizedBox(height: 4),
            Text(
              'Pick the distributor account you will log into for testing.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),

            if (_loadingDistributors)
              const Center(child: CircularProgressIndicator())
            else if (_distributors.isEmpty)
              _infoBanner(
                icon: Icons.person_off,
                color: Colors.red,
                title: 'No Distributors Found',
                body: 'Add a user with the "distributor" role in HRM first.',
                isDark: isDark,
              )
            else
              DropdownButtonFormField<String>(
                value: _selectedDistributorId,
                decoration: InputDecoration(
                  labelText: 'Distributor Account',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.local_shipping_outlined),
                ),
                items: _distributors
                    .map(
                      (d) => DropdownMenuItem<String>(
                        value: d['id'],
                        child: Text(d['name']!),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  final dist = _distributors.firstWhere((d) => d['id'] == v);
                  setState(() {
                    _selectedDistributorId = v;
                    _selectedDistributorName = dist['name'];
                  });
                },
                hint: const Text('Select distributor…'),
              ),

            const SizedBox(height: 24),

            // ── Step 3: Seed ─────────────────────────────────────────────
            _heading('Step 3 — Seed a Scenario', isDark),
            const SizedBox(height: 4),
            Text(
              'Each button seeds one complete delivery assignment in the given '
              'state. Log out → log in as distributor to test it.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),

            ..._Scenario.all.map((s) => _scenarioBtn(s)),

            const SizedBox(height: 6),

            // Seed all button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    (_isSeeding || _pickedLocation == null || _selectedDistributorId == null)
                        ? null
                        : _seedAll,
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text(
                  'Seed ALL 4 Scenarios at Once',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Cleanup ──────────────────────────────────────────────────
            _heading('Cleanup', isDark),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isDeleting ? null : _deleteAll,
                icon: _isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.red,
                        ),
                      )
                    : const Icon(Icons.delete_forever, size: 18),
                label: Text(
                  _testDocCount > 0
                      ? '🗑️ Delete All $_testDocCount Test Documents'
                      : '🗑️ Delete All Test Data',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            // ── Status log ───────────────────────────────────────────────
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.deepPurple.withValues(alpha: 0.12)
                      : Colors.deepPurple.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.deepPurple.withValues(alpha: 0.25)),
                ),
                child: Text(
                  _log,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.deepPurple[200] : Colors.deepPurple[900],
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],

            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  // ── Sub-widgets ────────────────────────────────────────────────────────────

  Widget _heading(String text, bool isDark) => Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.deepPurple[800],
        ),
      );

  Widget _infoBanner({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body,
                    style: TextStyle(
                        fontSize: 12, color: color.withValues(alpha: 0.75))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapPlaceholder(bool isDark) {
    return GestureDetector(
      onTap: _openMapPicker,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.deepPurple.withValues(alpha: 0.1)
              : Colors.deepPurple.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.25)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_location_alt_outlined,
                  size: 36, color: Colors.deepPurple.withValues(alpha: 0.45)),
              const SizedBox(height: 8),
              Text(
                'Tap "Pick on Map" to set the family location',
                style: TextStyle(
                    fontSize: 12, color: Colors.deepPurple.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapPreview() {
    final loc = _pickedLocation!;
    return GestureDetector(
      onTap: _openMapPicker,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 175,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: loc,
              initialZoom: 17,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rationaid.app',
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: loc,
                    radius: 50,
                    useRadiusInMeter: true,
                    color: Colors.cyan.withValues(alpha: 0.15),
                    borderColor: Colors.cyan,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: loc,
                    width: 36,
                    height: 36,
                    child: const Icon(Icons.location_pin,
                        color: Colors.red, size: 36),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scenarioBtn(_Scenario s) {
    final disabled =
        _isSeeding || _pickedLocation == null || _selectedDistributorId == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: disabled ? null : () => _seed(s),
          style: ElevatedButton.styleFrom(
            backgroundColor: s.color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: s.color.withValues(alpha: 0.4),
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
            alignment: Alignment.centerLeft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            children: [
              Icon(s.icon, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(s.desc,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
              ),
              if (_isSeeding)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Map Picker Page ───────────────────────────────────────────────────────────

class _MapPickerPage extends StatefulWidget {
  final LatLng initialCenter;
  const _MapPickerPage({required this.initialCenter});

  @override
  State<_MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<_MapPickerPage> {
  late final MapController _ctrl;
  LatLng? _pin;
  bool _getting = false;

  @override
  void initState() {
    super.initState();
    _ctrl = MapController();
    _pin = widget.initialCenter;
  }

  Future<void> _myLocation() async {
    setState(() => _getting = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final ll = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _pin = ll);
        _ctrl.move(ll, 17);
      }
    } finally {
      if (mounted) setState(() => _getting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Family Location',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed:
                _pin == null ? null : () => Navigator.pop(context, _pin),
            child: const Text('Use This',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _ctrl,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: 16,
              onTap: (_, ll) => setState(() => _pin = ll),
              onLongPress: (_, ll) => setState(() => _pin = ll),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rationaid.app',
              ),
              if (_pin != null) ...[
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _pin!,
                      radius: 50,
                      useRadiusInMeter: true,
                      color: Colors.cyan.withValues(alpha: 0.15),
                      borderColor: Colors.cyan,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pin!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_pin,
                          color: Colors.red, size: 40),
                    ),
                  ],
                ),
              ],
            ],
          ),
          // Instruction
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.touch_app, color: Colors.white70, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap or long-press to drop pin  •  Cyan circle = 50 m fence',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Coordinates
          if (_pin != null)
            Positioned(
              bottom: 90,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_pin!.latitude.toStringAsFixed(6)}, '
                  '${_pin!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          // FAB
          Positioned(
            bottom: 24,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: _getting ? null : _myLocation,
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              icon: _getting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.my_location, size: 18),
              label: const Text('My Location'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scenarios ─────────────────────────────────────────────────────────────────

class _Scenario {
  final String key;
  final String label;
  final String desc;
  final String status;
  final String familyStatus;
  final Color color;
  final IconData icon;
  final String area;
  final String city;
  final bool preAssign;
  final bool addPickedUpAt;
  final bool addInTransitAt;
  final bool addFailedAt;
  final bool addDeliveredAt;

  const _Scenario({
    required this.key,
    required this.label,
    required this.desc,
    required this.status,
    required this.familyStatus,
    required this.color,
    required this.icon,
    required this.area,
    required this.city,
    this.preAssign = true,
    this.addPickedUpAt = false,
    this.addInTransitAt = false,
    this.addFailedAt = false,
    this.addDeliveredAt = false,
  });

  static const all = [
    _Scenario(
      key: 'pool',
      label: 'Seed: Available Pool (Not Started)',
      desc: 'Appears in "🔓 Available Pool" tab — test Claim flow',
      status: 'not_started',
      familyStatus: 'ready_for_delivery',
      color: Colors.grey,
      icon: Icons.hourglass_empty,
      area: 'Gulberg III',
      city: 'Lahore',
      preAssign: false, // no distributor pre-assigned = visible in pool
    ),
    _Scenario(
      key: 'transit',
      label: 'Seed: In Transit 🚚',
      desc: 'In "My Deliveries" — test 50 m fence, offline sync, photo upload',
      status: 'in_transit',
      familyStatus: 'in_transit',
      color: AppColors.volunteerBlue,
      icon: Icons.local_shipping,
      area: 'DHA Phase 5',
      city: 'Lahore',
      addPickedUpAt: true,
      addInTransitAt: true,
    ),
    _Scenario(
      key: 'failed',
      label: 'Seed: Failed (Proof Rejected) ❌',
      desc: 'In "My Deliveries" — test Re-Attempt Delivery button',
      status: 'failed',
      familyStatus: 'issue_reported',
      color: Colors.red,
      icon: Icons.cancel_outlined,
      area: 'Model Town',
      city: 'Lahore',
      addPickedUpAt: true,
      addInTransitAt: true,
      addFailedAt: true,
    ),
    _Scenario(
      key: 'verify',
      label: 'Seed: Awaiting Admin Verify 🟣',
      desc: 'In admin "To Verify" tab — test Verify / Reject dialog',
      status: 'delivered',
      familyStatus: 'delivered',
      color: Colors.purple,
      icon: Icons.hourglass_top,
      area: 'Johar Town',
      city: 'Lahore',
      addPickedUpAt: true,
      addInTransitAt: true,
      addDeliveredAt: true,
    ),
  ];
}
