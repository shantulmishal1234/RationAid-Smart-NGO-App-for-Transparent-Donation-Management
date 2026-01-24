import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';

class AuditTrailScreen extends StatefulWidget {
  const AuditTrailScreen({super.key});

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  String _selectedEntityType = 'all';
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getAuditLogs() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(200);

    return query.snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header Row (Matches HRM Section)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              'Audit Trail',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

        // Toolbar: Search | Filter
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Search Bar
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search logs...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      filled: true,
                      fillColor: theme.cardColor,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withOpacity(0.6),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withOpacity(0.6),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value.toLowerCase());
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Filter Menu
              SizedBox(
                width: 48,
                height: 48,
                child: FrostedPanel(
                  padding: EdgeInsets.zero,
                  child: PopupMenuButton<String>(
                    icon: Icon(
                      Icons.filter_list,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      size: 22,
                    ),
                    tooltip: 'Filter by Type',
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (v) => setState(() => _selectedEntityType = v),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'all',
                        child: Text('All Logs'),
                      ),
                      const PopupMenuItem(
                        value: 'family',
                        child: Text('Families'),
                      ),
                      const PopupMenuItem(
                        value: 'donation',
                        child: Text('Donations'),
                      ),
                      const PopupMenuItem(value: 'user', child: Text('Users')),
                      const PopupMenuItem(
                        value: 'system',
                        child: Text('System'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // List container
        Expanded(
          child: FrostedPanel(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: EdgeInsets.zero,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _getAuditLogs(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading logs',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  );
                }

                var docs = snapshot.data?.docs ?? [];

                // Client-side filter by entity type
                if (_selectedEntityType != 'all') {
                  docs = docs.where((doc) {
                    final data = doc.data();
                    return data['entityType'] == _selectedEntityType;
                  }).toList();
                }

                // Client-side search filter
                if (_searchQuery.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data();
                    final action = (data['action'] ?? '')
                        .toString()
                        .toLowerCase();
                    final details = (data['details'] ?? '')
                        .toString()
                        .toLowerCase();
                    final email = (data['performedByEmail'] ?? '')
                        .toString()
                        .toLowerCase();
                    return action.contains(_searchQuery) ||
                        details.contains(_searchQuery) ||
                        email.contains(_searchQuery);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No audit logs found.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    return _AuditLogCard(data: data);
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditLogCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _AuditLogCard({required this.data});

  Color _getEntityColor(String entityType) {
    switch (entityType) {
      case 'family':
        return Colors.blue;
      case 'donation':
        return Colors.green;
      case 'user':
        return Colors.orange;
      case 'system':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getEntityIcon(String entityType) {
    switch (entityType) {
      case 'family':
        return Icons.family_restroom;
      case 'donation':
        return Icons.volunteer_activism;
      case 'user':
        return Icons.person;
      case 'system':
        return Icons.settings;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final action = data['action'] ?? 'Unknown action';
    final entityType = data['entityType'] ?? 'unknown';
    final details = data['details'] ?? '';
    final performedBy =
        data['performedByName'] ?? data['performedByEmail'] ?? 'Unknown user';
    final timestamp = data['timestamp'] as Timestamp?;
    final timeStr = timestamp != null
        ? DateFormat('MMM dd, yyyy hh:mm a').format(timestamp.toDate())
        : 'Unknown time';

    final metadata = data['metadata'] as Map<String, dynamic>?;
    final entityName =
        metadata?['familyName'] ??
        metadata?['donorName'] ??
        metadata?['userName'] ??
        '';

    final color = _getEntityColor(entityType);

    return RepaintBoundary(
      child: FrostedPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon bubble
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_getEntityIcon(entityType), color: color, size: 18),
            ),
            const SizedBox(width: 10),
            // Main content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action + chip
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          action,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: color.withOpacity(0.2)),
                        ),
                        child: Text(
                          entityType,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (entityName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entityName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface.withOpacity(0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(0.6),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 12,
                        color: cs.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          performedBy,
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurface.withOpacity(0.5),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: cs.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
