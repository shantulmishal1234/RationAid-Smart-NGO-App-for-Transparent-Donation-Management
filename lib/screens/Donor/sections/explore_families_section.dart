import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/family_service.dart';
import 'package:ration_aid/services/favorites_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Explore Families Section - Browse accepted families with masked data
class ExploreFamiliesSection extends StatefulWidget {
  const ExploreFamiliesSection({super.key});

  @override
  State<ExploreFamiliesSection> createState() => _ExploreFamiliesSectionState();
}

class _ExploreFamiliesSectionState extends State<ExploreFamiliesSection> {
  final FamilyService _familyService = FamilyService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  String? _selectedAssistanceType; // Filter by assistance type
  bool _isIndexVisible = false;
  Timer? _hideTimer;

  // Available assistance types for filtering
  static const List<String> _assistanceTypes = [
    'Food Ration',
    'Medical Aid',
    'Education Support',
    'Shelter',
    'Clothing',
    'Emergency Relief',
  ];

  late Stream<List<Family>> _familiesStream;

  @override
  void initState() {
    super.initState();
    _familiesStream = _familyService.streamAcceptedFamilies();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_isIndexVisible) {
      setState(() => _isIndexVisible = true);
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _isIndexVisible = false);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
              : [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Explore Families',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Browse families seeking support',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),

            // Search Bar
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withOpacity(0.3)
                        : Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search by Area (e.g. Johar Town)',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Assistance Type Filter Chips
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // "All" chip
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: _selectedAssistanceType == null,
                      onSelected: (_) {
                        setState(() => _selectedAssistanceType = null);
                      },
                      selectedColor: AppColors.donorGreen.withOpacity(0.2),
                      checkmarkColor: AppColors.donorGreen,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: _selectedAssistanceType == null
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: _selectedAssistanceType == null
                            ? AppColors.donorGreen
                            : Colors.grey[700],
                      ),
                      backgroundColor: Theme.of(context).cardColor,
                      side: BorderSide(
                        color: _selectedAssistanceType == null
                            ? AppColors.donorGreen
                            : Colors.grey[300]!,
                      ),
                    ),
                  ),
                  // Type-specific chips
                  ..._assistanceTypes.map(
                    (type) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(type),
                        selected: _selectedAssistanceType == type,
                        onSelected: (_) {
                          setState(() {
                            _selectedAssistanceType =
                                _selectedAssistanceType == type ? null : type;
                          });
                        },
                        selectedColor: AppColors.donorGreen.withOpacity(0.2),
                        checkmarkColor: AppColors.donorGreen,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: _selectedAssistanceType == type
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: _selectedAssistanceType == type
                              ? AppColors.donorGreen
                              : Colors.grey[700],
                        ),
                        backgroundColor: Theme.of(context).cardColor,
                        side: BorderSide(
                          color: _selectedAssistanceType == type
                              ? AppColors.donorGreen
                              : Colors.grey[300]!,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Family list with A-Z Index
            Expanded(
              child: StreamBuilder<List<Family>>(
                stream: _familiesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  var families = snapshot.data ?? [];

                  // Filter by search query
                  if (_searchQuery.isNotEmpty) {
                    families = families
                        .where(
                          (f) =>
                              f.area.toLowerCase().contains(_searchQuery) ||
                              f.city.toLowerCase().contains(_searchQuery) ||
                              f.needsSummary.toLowerCase().contains(
                                _searchQuery,
                              ),
                        )
                        .toList();
                  }

                  // Filter by assistance type
                  if (_selectedAssistanceType != null) {
                    families = families
                        .where(
                          (f) => f.assistanceNeeds.contains(
                            _selectedAssistanceType,
                          ),
                        )
                        .toList();
                  }

                  // Sort alphabetically by City then Area
                  families.sort((a, b) {
                    int cityCompare = a.city.toLowerCase().compareTo(
                      b.city.toLowerCase(),
                    );
                    if (cityCompare != 0) return cityCompare;
                    return a.area.toLowerCase().compareTo(b.area.toLowerCase());
                  });

                  if (families.isEmpty) {
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
                            _searchQuery.isNotEmpty
                                ? 'No families found matching "$_searchQuery"'
                                : 'No families available',
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(
                          bottom: 16,
                          right: 20,
                        ), // Right padding for A-Z bar
                        itemCount: families.length,
                        itemBuilder: (context, index) {
                          return _FamilyCard(family: families[index]);
                        },
                      ),
                      // A-Z Index Slider (Samsung Style)
                      if (_searchQuery.isEmpty && families.length > 5)
                        Positioned(
                          right: 2,
                          top: 40,
                          bottom: 40,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: _isIndexVisible ? 1.0 : 0.0,
                            child: Center(
                              child: Container(
                                width: 24, // Fixed width to prevent fluctuation
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).cardColor.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isDark
                                          ? Colors.black.withOpacity(0.3)
                                          : Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                      offset: const Offset(-1, 0),
                                    ),
                                  ],
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    // Generate full A-Z list
                                    final alphabet = List.generate(
                                      26,
                                      (index) =>
                                          String.fromCharCode(index + 65),
                                    );

                                    return GestureDetector(
                                      onVerticalDragUpdate: (details) {
                                        // Reset timer on interaction
                                        _onScroll();

                                        // Calculate which letter is being touched
                                        final renderBox =
                                            context.findRenderObject()
                                                as RenderBox;
                                        final localPosition = renderBox
                                            .globalToLocal(
                                              details.globalPosition,
                                            );
                                        final itemHeight =
                                            renderBox.size.height /
                                            alphabet.length;
                                        final index =
                                            (localPosition.dy / itemHeight)
                                                .floor();

                                        if (index >= 0 &&
                                            index < alphabet.length) {
                                          final letter = alphabet[index];
                                          _scrollToLetter(letter, families);
                                        }
                                      },
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: alphabet.map((letter) {
                                          return GestureDetector(
                                            onTap: () {
                                              _onScroll();
                                              _scrollToLetter(letter, families);
                                            },
                                            child: Container(
                                              height:
                                                  constraints.maxHeight /
                                                  28, // Distribute height
                                              alignment: Alignment.center,
                                              child: Text(
                                                letter,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.donorGreen,
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToLetter(String letter, List<Family> families) {
    final index = families.indexWhere(
      (f) => f.city.isNotEmpty && f.city.toUpperCase().startsWith(letter),
    );
    if (index != -1) {
      // Approx height: Card (variable) + Margin (12)
      // Using 160 as average height estimate
      double offset = index * 160.0;
      // Clamp offset to max scroll extent
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (offset > maxScroll) {
          offset = maxScroll;
        }
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }
}

/// Family card widget - Compact design with last updated and verified badge
class _FamilyCard extends StatefulWidget {
  final Family family;

  const _FamilyCard({required this.family});

  @override
  State<_FamilyCard> createState() => _FamilyCardState();
}

class _FamilyCardState extends State<_FamilyCard> {
  bool _isFavorite = false;
  bool _isTogglingFavorite = false;

  @override
  void initState() {
    super.initState();
    _checkFavoriteStatus();
  }

  Future<void> _checkFavoriteStatus() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      final isFav = await FavoritesService.isFavorite(userId, widget.family.id);
      if (mounted) {
        setState(() => _isFavorite = isFav);
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (_isTogglingFavorite) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() => _isTogglingFavorite = true);

    final success = await FavoritesService.toggleFavorite(
      userId,
      widget.family.id,
    );
    if (success && mounted) {
      setState(() {
        _isFavorite = !_isFavorite;
        _isTogglingFavorite = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFavorite ? 'Added to favorites' : 'Removed from favorites',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
          backgroundColor: _isFavorite
              ? AppColors.donorGreen
              : Colors.grey[700],
        ),
      );
    } else if (mounted) {
      setState(() => _isTogglingFavorite = false);
    }
  }

  Family get family => widget.family;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.pushNamed(context, '/family-detail', arguments: family);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: Theme.of(context).brightness == Brightness.dark
                    ? [
                        Theme.of(context).cardColor,
                        Theme.of(context).cardColor.withOpacity(0.8),
                      ]
                    : [Colors.white, AppColors.donorGreen.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.1)
                    : AppColors.donorGreen.withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black.withOpacity(0.3)
                      : AppColors.donorGreen.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.donorGreen, AppColors.accentGreen],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.donorGreen.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_city,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                family.city.isNotEmpty
                                    ? family.city
                                    : 'Unknown City',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Verified badge
                              const Icon(
                                Icons.verified,
                                size: 16,
                                color: Colors.green,
                              ),
                            ],
                          ),
                          if (family.area.isNotEmpty)
                            Text(
                              family.area,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.donorGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${family.needs.length} items needed',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.donorGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Favorite and Navigate buttons
                    Column(
                      children: [
                        // Favorite heart button
                        GestureDetector(
                          onTap: _toggleFavorite,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _isFavorite
                                  ? Colors.red.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: _isTogglingFavorite
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.red,
                                    ),
                                  )
                                : Icon(
                                    _isFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 16,
                                    color: _isFavorite
                                        ? Colors.red
                                        : Colors.grey[500],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Arrow button
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.donorGreen.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: AppColors.donorGreen,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Family composition chips - compact
                Row(
                  children: [
                    Expanded(
                      child: _FamilyInfoChip(
                        icon: Icons.man,
                        label: 'Adults',
                        count: family.numberOfAdults,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FamilyInfoChip(
                        icon: Icons.child_care,
                        label: 'Children',
                        count: family.numberOfChildren,
                        color: Colors.pink,
                      ),
                    ),
                  ],
                ),
                // Last updated text (Moved up below chips)
                if (family.updatedAt != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 10,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.4),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Updated ${_getTimeAgo(family.updatedAt!)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.5),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Bottom section with needs
                if (family.needs.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.list_alt,
                        size: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          family.needsSummary,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.7),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }
}

/// Compact chip for family info
class _FamilyInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _FamilyInfoChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
