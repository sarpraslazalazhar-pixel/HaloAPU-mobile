import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:halo_apu_mobile/core/services/cache_service.dart';
import 'package:halo_apu_mobile/core/services/session_manager.dart';
import 'package:halo_apu_mobile/core/services/ticket_service.dart';
import 'package:halo_apu_mobile/core/theme/app_theme.dart';
import 'package:halo_apu_mobile/presentation/dashboard/providers/monitor_provider.dart';
import 'package:halo_apu_mobile/presentation/widgets/app_error_view.dart';
import 'package:halo_apu_mobile/presentation/widgets/shimmer.dart';
import 'package:halo_apu_mobile/domain/models/ticket_model.dart';
import '../widgets/custom_bottom_nav.dart';
import 'providers/admin_ticket_provider.dart';
import 'widgets/handover_asset_sheet.dart';
import 'widgets/return_asset_sheet.dart';
import 'widgets/ticket_card.dart';
import '../widgets/pagination_footer.dart';
import 'dart:async';

class AdminTicketListScreen extends ConsumerStatefulWidget {
  final String? initialFilter;
  final String? initialTab;

  const AdminTicketListScreen({super.key, this.initialFilter, this.initialTab});

  @override
  ConsumerState<AdminTicketListScreen> createState() => _AdminTicketListScreenState();
}

class _AdminTicketListScreenState extends ConsumerState<AdminTicketListScreen> {
  final ScrollController _scrollController = ScrollController();
  String _activeTab = 'masuk';
  String _selectedFilter = 'Semua';
  final List<String> _filters = ['Semua', 'Aktif', 'Terbuka', 'Diproses', 'Perlu Revisi', 'Tertunda', 'Selesai', 'Ditolak'];
  static const List<({String key, String label})> _loanStageFilters = [
    (key: 'aktif', label: 'Perlu Tindakan'),
    (key: 'menunggu_diserahkan', label: 'Menunggu Dikasih'),
    (key: 'sedang_dipinjam', label: 'Sedang Dipinjam'),
    (key: 'dikembalikan', label: 'Sudah Dikembalikan'),
    (key: 'semua', label: 'Semua'),
  ];
  final TicketService _ticketService = TicketService();
  bool _isLoadingMore = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.initialTab != null &&
        (widget.initialTab == 'masuk' ||
            widget.initialTab == 'saya_ajukan' ||
            widget.initialTab == 'peminjaman_alat')) {
      _activeTab = widget.initialTab!;
    }
    final filter = widget.initialFilter == 'Menunggu' ? 'Terbuka' : widget.initialFilter;
    if (filter != null && _filters.contains(filter)) {
      _selectedFilter = filter;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (widget.initialTab != null) {
          ref.read(adminTicketProvider.notifier).setTab(_activeTab);
        }
        if (filter != null) {
          ref.read(adminTicketProvider.notifier).setFilter(filter);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _onScroll() async {
    final notifier = ref.read(adminTicketProvider.notifier);
    if (_isLoadingMore || !notifier.hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      setState(() => _isLoadingMore = true);
      await notifier.loadMore();
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _performSearch(String query) {
    ref.read(adminTicketProvider.notifier).setSearchQuery(query.trim());
  }

  List<TicketModel> _getFilteredTickets(List<TicketModel> tickets) {
    return tickets;
  }

  Future<void> _handleQuickHandover(TicketModel ticket) async {
    await HandoverAssetSheet.show(
      context,
      ticketId: ticket.id,
      borrowerName: ticket.requesterName,
      equipmentText: ticket.alatText,
      scheduleText: ticket.rentangWaktu,
      onConfirm: (penerimaUserId, kondisi, catatan, attachments) async {
        final res = await _ticketService.serahkanAlat(
          ticket.id,
          penerimaUserId: penerimaUserId,
          kondisi: kondisi,
          catatan: catatan,
          attachments: attachments,
        );
        if (!mounted) return false;
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.success,
              content: Text(
                res['message']?.toString() ??
                    'Alat berhasil ditandai sudah diserahkan',
              ),
            ),
          );
          await CacheService.removeByPrefix('ticket_');
          ref.read(adminTicketProvider.notifier).refresh();
          ref.read(monitorProvider.notifier).refresh();
          return true;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.danger,
            content: Text(
              res['message']?.toString() ?? 'Gagal menandai serah-terima alat',
            ),
          ),
        );
        return false;
      },
    );
  }

  Future<void> _handleQuickReturn(TicketModel ticket) async {
    await ReturnAssetSheet.show(
      context,
      ticketId: ticket.id,
      hasHandedOver: ticket.isSudahDiserahkan,
      borrowerName: ticket.requesterName,
      equipmentText: ticket.alatText,
      scheduleText: ticket.rentangWaktu,
      onConfirm: (kondisi, catatan, attachments) async {
        final res = await _ticketService.kembalikanAlat(
          ticket.id,
          kondisi: kondisi,
          catatan: catatan,
          attachments: attachments,
        );
        if (!mounted) return false;
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.success,
              content: Text(
                res['message']?.toString() ?? 'Alat berhasil dikembalikan',
              ),
            ),
          );
          await CacheService.removeByPrefix('ticket_');
          ref.read(adminTicketProvider.notifier).refresh();
          ref.read(monitorProvider.notifier).refresh();
          return true;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.danger,
            content: Text(
              res['message']?.toString() ??
                  'Gagal menandai pengembalian alat',
            ),
          ),
        );
        return false;
      },
    );
  }

  Widget _buildTabButton({
    required String tabKey,
    required String activeTab,
    required IconData icon,
    required String label,
    int? badgeCount,
  }) {
    final isSelected = activeTab == tabKey;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (activeTab == tabKey) return;
          setState(() {
            _activeTab = tabKey;
            _selectedFilter = 'Semua';
          });
          ref.read(adminTicketProvider.notifier).setTab(tabKey);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00768C) : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              if (badgeCount != null && badgeCount > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.25)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ticketState = ref.watch(adminTicketProvider);
    final notifier = ref.read(adminTicketProvider.notifier);
    final canViewLoans = notifier.canViewEquipmentLoans;
    final effectiveTab = (!canViewLoans && _activeTab == 'peminjaman_alat')
        ? 'masuk'
        : _activeTab;
    final isLoanTab = effectiveTab == 'peminjaman_alat';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Manajemen Tiket', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          // Tab Switcher: Antrean Unit vs Tiket Saya (+ Pinjam Alat bila berhak)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                children: [
                  _buildTabButton(
                    tabKey: 'masuk',
                    activeTab: effectiveTab,
                    icon: Icons.inbox_rounded,
                    label: 'Antrean Unit',
                  ),
                  _buildTabButton(
                    tabKey: 'saya_ajukan',
                    activeTab: effectiveTab,
                    icon: Icons.send_rounded,
                    label: 'Tiket Saya',
                  ),
                  if (canViewLoans)
                    _buildTabButton(
                      tabKey: 'peminjaman_alat',
                      activeTab: effectiveTab,
                      icon: Icons.inventory_2_outlined,
                      label: 'Pinjam Alat',
                      badgeCount: notifier.peminjamanAlatCount,
                    ),
                ],
              ),
            ),
          ),
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (val) => _performSearch(val),
              onChanged: (_) {
                setState(() {}); // Hanya update UI untuk ikon clear
              },
              decoration: InputDecoration(
                hintText: 'Cari ID, Layanan, Kanal, atau Detail...',
                prefixIcon: IconButton(
                  icon: const Icon(Icons.search, color: Colors.grey),
                  onPressed: () => _performSearch(_searchController.text),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                          _performSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          // Filter Chips (Status biasa atau 5 sub-filter Pinjam Alat)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: isLoanTab
                ? Row(
                    children: _loanStageFilters.map((stage) {
                      final isSelected = notifier.loanStage == stage.key;
                      final stageCount = notifier.loanStageCounts[stage.key];
                      final label = stageCount != null
                          ? '${stage.label} ($stageCount)'
                          : stage.label;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(label),
                          selected: isSelected,
                          onSelected: (_) {
                            notifier.setLoanStage(stage.key);
                          },
                          backgroundColor: Colors.grey.shade100,
                          selectedColor:
                              const Color(0xFF00B8D9).withValues(alpha: 0.2),
                          checkmarkColor: const Color(0xFF00B8D9),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? const Color(0xFF0066FF)
                                : Colors.grey.shade700,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected
                                  ? const Color(0xFF00B8D9)
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  )
                : Row(
                    children: _filters.map((filter) {
                      final isSelected = _selectedFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(filter),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedFilter = filter;
                            });
                            ref.read(adminTicketProvider.notifier).setFilter(filter);
                          },
                          backgroundColor: Colors.grey.shade100,
                          selectedColor: const Color(0xFF00B8D9).withValues(alpha: 0.2),
                          checkmarkColor: const Color(0xFF00B8D9),
                          labelStyle: TextStyle(
                            color: isSelected ? const Color(0xFF0066FF) : Colors.grey.shade700,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF00B8D9) : Colors.transparent,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          
          // Ticket List
          Expanded(
            child: ticketState.when(
              loading: () => const TicketListSkeleton(count: 4, showHeader: false),
              error: (error, stack) => AppErrorView(
                error: error,
                fullPage: false,
                onRetry: () => ref.read(adminTicketProvider.notifier).refresh(),
                onLogin: () => SessionManager.instance.forceReLogin(),
              ),
              data: (tickets) {
                final filteredTickets = _getFilteredTickets(tickets);
                final hasMore = ref.read(adminTicketProvider.notifier).hasMore;

                if (filteredTickets.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () => ref.read(adminTicketProvider.notifier).refresh(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  effectiveTab == 'saya_ajukan'
                                      ? 'Belum ada tiket yang Anda ajukan'
                                      : (isLoanTab
                                          ? 'Belum ada tiket peminjaman alat pada tahap ini'
                                          : 'Belum ada tiket di unit ini'),
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => ref.read(adminTicketProvider.notifier).refresh(),
                  color: const Color(0xFF00B8D9),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    itemCount: filteredTickets.length + 1,
                    itemBuilder: (context, index) {
                      if (index == filteredTickets.length) {
                        return PaginationFooter(
                          isLoading: _isLoadingMore,
                          hasMore: hasMore,
                        );
                      }
                      final ticket = filteredTickets[index];
                      return TicketCard(
                        ticket: ticket,
                        showLoanDetails: isLoanTab,
                        onQuickHandover: isLoanTab && ticket.canSerahkan
                            ? () => _handleQuickHandover(ticket)
                            : null,
                        onQuickReturn: isLoanTab && ticket.canKembalikan
                            ? () => _handleQuickReturn(ticket)
                            : null,
                        onTap: () {
                          if (effectiveTab == 'saya_ajukan') {
                            context.push('/tickets/user/detail', extra: ticket);
                          } else {
                            context.push('/tickets/admin/detail', extra: ticket);
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: const AdminBottomNav(currentIndex: 1), // Index 1 is Antrean
      floatingActionButton: CustomFloatingActionButton(
        icon: Icons.add,
        onPressed: () => context.push('/tickets/create'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
