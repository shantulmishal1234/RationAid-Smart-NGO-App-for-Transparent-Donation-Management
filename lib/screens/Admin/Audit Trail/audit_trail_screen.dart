import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/theme/app_colors.dart';

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
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Audit trail',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: [
              const SizedBox(height: 4),
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(color: cs.outline.withOpacity(0.06)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by action, user, or details...',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary.withOpacity(0.7),
                      ),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      prefixIconColor: AppColors.textSecondary,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value.toLowerCase());
                    },
                  ),
                ),
              ),
              // Filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _filterChip('all', 'All'),
                    _filterChip('family', 'Families'),
                    _filterChip('donation', 'Donations'),
                    _filterChip('user', 'Users'),
                    _filterChip('system', 'System'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getAuditLogs(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                  const SizedBox(height: 8),
                  Text(
                    'Error loading audit logs',
                    style: TextStyle(color: Colors.red[400]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${snapshot.error}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
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
              final action = (data['action'] ?? '').toString().toLowerCase();
              final details = (data['details'] ?? '').toString().toLowerCase();
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    _selectedEntityType == 'all'
                        ? 'No audit logs found'
                        : 'No $_selectedEntityType logs found',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  if (_selectedEntityType != 'all') ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() => _selectedEntityType = 'all');
                      },
                      child: const Text('View all logs'),
                    ),
                  ],
                ],
              ),
            );
          }

          return Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.96),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final data = docs[index].data();
                return _AuditLogCard(data: data);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final isSelected = _selectedEntityType == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() => _selectedEntityType = value);
        },
        selectedColor: AppColors.primaryBlue.withOpacity(0.16),
        labelStyle: TextStyle(
          color: isSelected ? AppColors.primaryBlue : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
        side: BorderSide(
          color: isSelected ? AppColors.primaryBlue : Colors.grey[300]!,
        ),
      ),
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

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon bubble
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_getEntityIcon(entityType), color: color, size: 20),
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          entityType,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (entityName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entityName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[800],
                      ),
                    ),
                  ],
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.person, size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          performedBy,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
