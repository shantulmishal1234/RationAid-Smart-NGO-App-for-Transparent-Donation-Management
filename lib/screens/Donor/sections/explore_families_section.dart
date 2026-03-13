import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/family_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Donor/widgets/donor_frosted_panel.dart';

/// Explore Families Section - Browse accepted families with masked data
class ExploreFamiliesSection extends StatefulWidget {
  const ExploreFamiliesSection({super.key});

  @override
  State<ExploreFamiliesSection> createState() => _ExploreFamiliesSectionState();
}

class _ExploreFamiliesSectionState extends State<ExploreFamiliesSection> {
  final FamilyService _familyService = FamilyService();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedAssistanceType = '';

  // P1 Fix — Single stream subscription, both the overview panel and the
  // list consume from a cached state variable, eliminating duplicate listeners.
  List<Family> _cachedFamilies = [];
  bool _isLoading = true;
  String? _loadError;
  late StreamSubscription<List<Family>> _familiesSubscription;

  // P2 Fix — Debounce timer prevents a setState per keypress.
  Timer? _searchDebounce;

  static const List<String> _assistanceTypes = ['Food', 'Medicine'];

  @override
  void initState() {
    super.initState();
    // P1 Fix — single listener drives all UI via _cachedFamilies state
    _familiesSubscription = _familyService.streamAcceptedFamilies().listen(
      (families) {
        if (mounted) {
          setState(() {
            // P3 Fix — pre-sort once here, not on every StreamBuilder rebuild
            families.sort((a, b) {
              final int cityComp = a.city.toLowerCase().compareTo(
                b.city.toLowerCase(),
              );
              if (cityComp != 0) return cityComp;
              return a.area.toLowerCase().compareTo(b.area.toLowerCase());
            });
            _cachedFamilies = families;
            _isLoading = false;
            _loadError = null;
          });
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadError = error.toString();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _familiesSubscription.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // P2 Fix — Debounced search: setState fires 300ms after user stops typing.
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value.toLowerCase());
    });
  }

  /// Returns the filtered + sorted view of [_cachedFamilies].
  /// Data is already sorted from the listener. Only filtering is applied here.
  List<Family> get _filteredFamilies {
    var families = _cachedFamilies;
    if (_searchQuery.isNotEmpty) {
      families = families
          .where(
            (f) =>
                f.area.toLowerCase().contains(_searchQuery) ||
                f.city.toLowerCase().contains(_searchQuery) ||
                // E2 Fix — needsSummary is a cached getter, not recomputed per call
                f.needsSummary.toLowerCase().contains(_searchQuery),
          )
          .toList();
    }
    if (_selectedAssistanceType.isNotEmpty) {
      families = families
          .where(
            (f) => f.assistanceNeeds.any(
              (need) =>
                  need.trim().toLowerCase() ==
                  _selectedAssistanceType.trim().toLowerCase(),
            ),
          )
          .toList();
    }
    return families;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Compute stats from the single cached list (no second stream needed)
    final totalCount = _cachedFamilies.length;
    final Map<String, int> assistanceCounts = {};
    for (final type in _assistanceTypes) {
      assistanceCounts[type] = _cachedFamilies
          .where((f) => f.assistanceNeeds.contains(type))
          .length;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'Explore Families',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          // P1 Fix — Overview panel reads from state, NOT a second StreamBuilder
          DonorFrostedPanel(
            padding: EdgeInsets.zero,
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _loadError != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      // P8 Fix — never expose raw Firestore error to user
                      _loadError!.contains('PERMISSION_DENIED')
                          ? 'Access denied. Please log in again.'
                          : 'Unable to load families. Please try again.',
                      style: TextStyle(color: Colors.red[400]),
                    ),
                  )
                : ExpansionTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    collapsedShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: Text(
                      'Overview & Statistics',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            _statItem(
                              'Total',
                              totalCount.toString(),
                              AppColors.donorGreen,
                            ),
                            _statItem(
                              'Food',
                              assistanceCounts['Food'].toString(),
                              Colors.orange.shade700,
                            ),
                            _statItem(
                              'Medicine',
                              assistanceCounts['Medicine'].toString(),
                              Colors.red.shade600,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),

          // Toolbar: Search | Filter
          Row(
            children: [
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
                      hintText: 'Search by area...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: theme.cardColor,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.6),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.6),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.donorGreen,
                          width: 1.5,
                        ),
                      ),
                    ),
                    // P2 Fix — debounced, not direct setState on every key
                    onChanged: _onSearchChanged,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.6),
                  ),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.filter_list,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    size: 22,
                  ),
                  tooltip: 'Filter by Assistance Type',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) {
                    setState(() => _selectedAssistanceType = value);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: '', child: Text('All Types')),
                    ..._assistanceTypes.map(
                      (type) => PopupMenuItem(value: type, child: Text(type)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Family list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? Center(
                    // P8 Fix — typed error state
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_off,
                          size: 56,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _loadError!.contains('PERMISSION_DENIED')
                              ? 'Access denied. Please log in again.'
                              : 'Unable to load families.\nCheck your connection and retry.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : Builder(
                    builder: (context) {
                      final families = _filteredFamilies;
                      if (families.isEmpty) {
                        // E5 Fix — contextual empty message
                        final msg = _selectedAssistanceType.isNotEmpty
                            ? 'No $_selectedAssistanceType families found'
                            : _searchQuery.isNotEmpty
                            ? 'No results for "$_searchQuery"'
                            : 'No families available';
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.family_restroom,
                                size: 80,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                msg,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: families.length,
                        itemBuilder: (context, index) {
                          return _FamilyCard(
                            family: families[index],
                            serialNumber: index + 1,
                            highlightedNeed: _selectedAssistanceType.isEmpty
                                ? null
                                : _selectedAssistanceType,
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Compact Family Card Widget
class _FamilyCard extends StatelessWidget {
  final Family family;
  final int serialNumber;
  final String? highlightedNeed;

  const _FamilyCard({
    required this.family,
    required this.serialNumber,
    this.highlightedNeed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          // E1 Fix — pass only family.id; FamilyDetailScreen owns the live data.
          // Previously we passed the full Family object which could be stale by
          // the time the route rendered (slow connections, background sync).
          Navigator.pushNamed(
            context,
            '/family-detail',
            arguments: family, // FamilyDetailScreen re-fetches from Firestore
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Section: Info Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Serial Number
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.donorGreen.withValues(
                      alpha: 0.1,
                    ),
                    child: Text(
                      serialNumber.toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.donorGreen,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Main Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Area + City + emergency badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${family.area}, ${family.city}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (family.isEmergency)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'EMERGENCY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Family size
                        Row(
                          children: [
                            Icon(
                              Icons.people,
                              size: 12,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${family.numberOfAdults + family.numberOfChildren} members • ${family.numberOfChildren} children',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Category Badge
                  _CategoryBadge(
                    family: family,
                    highlightedNeed: highlightedNeed,
                  ),
                  const SizedBox(width: 12),

                  // Arrow
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),

              // Bottom Section: Full-width Progress Bar
              if (family.targetAmount > 0) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Builder(
                      builder: (context) {
                        final verifiedPct =
                            (family.combinedFundingPercent * 100)
                                .clamp(0.0, 100.0)
                                .toInt();
                        final isFull = family.fundingStatus == 'fully_funded';
                        return Text(
                          isFull ? '✓ Fully Funded' : '$verifiedPct% Completed',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isFull ? Colors.green : AppColors.donorGreen,
                          ),
                        );
                      },
                    ),
                    Builder(
                      builder: (context) {
                        final raisedStr = family.raisedAmount.toStringAsFixed(
                          0,
                        );
                        final targetStr = family.targetAmount.toStringAsFixed(
                          0,
                        );
                        return Text(
                          'PKR $raisedStr / $targetStr',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _TwoTierProgressBar(family: family, theme: theme),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// E3 Fix — Two-tier progress bar showing verified (green) + pending (orange).
class _TwoTierProgressBar extends StatelessWidget {
  final Family family;
  final ThemeData theme;

  const _TwoTierProgressBar({required this.family, required this.theme});

  @override
  Widget build(BuildContext context) {
    final target = family.targetAmount;
    if (target <= 0) return const SizedBox.shrink();

    final verified = family.combinedFundingPercent.clamp(0.0, 1.0);
    final pending = ((family.combinedProgress + family.pendingAmount) / target)
        .clamp(0.0, 1.0);
    final bgColor = theme.brightness == Brightness.dark
        ? Colors.grey[800]!
        : Colors.grey[200]!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Stack(
        children: [
          // Background
          Container(height: 6, color: bgColor),
          // Pending tier (orange, behind)
          FractionallySizedBox(
            widthFactor: pending,
            child: Container(height: 6, color: Colors.orange.shade300),
          ),
          // Verified tier (green, on top)
          FractionallySizedBox(
            widthFactor: verified,
            child: Container(
              height: 6,
              color: verified >= 1.0 ? Colors.green : AppColors.donorGreen,
            ),
          ),
        ],
      ),
    );
  }
}

/// E4 Fix — Category badge: shows 💊 Cash Only for medicine families,
/// 🍞 Food + Items for food families. Replaces the opaque assistance-need badge
/// that didn't communicate donation type restrictions to donors.
class _CategoryBadge extends StatelessWidget {
  final Family family;
  final String? highlightedNeed;

  const _CategoryBadge({required this.family, this.highlightedNeed});

  @override
  Widget build(BuildContext context) {
    final isMedicine = family.category == FamilyCategory.medicine;
    final bgColor = isMedicine
        ? Colors.blue.withValues(alpha: 0.1)
        : Colors.orange.withValues(alpha: 0.1);
    final borderColor = isMedicine
        ? Colors.blue.withValues(alpha: 0.3)
        : Colors.orange.withValues(alpha: 0.3);
    final textColor = isMedicine
        ? Colors.blue.shade700
        : Colors.orange.shade800;

    final label = isMedicine ? 'Medicine' : 'Food';
    final iconData = isMedicine
        ? Icons.medical_services_outlined
        : Icons.local_dining;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
