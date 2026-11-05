import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/models/rating_model.dart';
import '../../../data/repositories/csat_repository.dart';

class RatingNotifier extends StateNotifier<AsyncValue<List<RatingModel>>> {
  static const int _pageSize = 15;

  final CsatRepository _repository;
  List<RatingModel> _allRatings = [];
  int _currentPage = 1;
  int _lastPage = 1;
  bool _isLoadingMore = false;

  RatingNotifier(this._repository) : super(const AsyncValue.loading()) {
    _loadInitial();
  }

  bool get hasMore => _currentPage < _lastPage;
  bool get isLoadingMore => _isLoadingMore;

  Future<void> _loadInitial() async {
    try {
      _currentPage = 1;
      final history = await _repository.getCsatHistory();

      _allRatings = history.map((csat) => RatingModel(
        id: csat.id,
        ticketId: csat.ticketId,
        ticketTitle: csat.ticketTitle,
        category: csat.category,
        score: csat.score,
        comment: csat.comment,
        createdAt: DateTime.tryParse(csat.createdAt) ?? DateTime.now(),
      )).toList();
      
      // Assuming we get total pages from API or handle it. For now, we fetch next page to check if more.
      _lastPage = history.length < _pageSize ? 1 : 2; 

      state = AsyncValue.data(_allRatings);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore) return;
    _isLoadingMore = true;
    try {
      _currentPage++;
      final moreHistory = await _repository.getCsatHistory();
      
      if (moreHistory.isEmpty) {
        _lastPage = _currentPage;
      } else {
        final newRatings = moreHistory.map((csat) => RatingModel(
          id: csat.id,
          ticketId: csat.ticketId,
          ticketTitle: csat.ticketTitle,
          category: csat.category,
          score: csat.score,
          comment: csat.comment,
        createdAt: DateTime.tryParse(csat.createdAt) ?? DateTime.now(),
        )).toList();
        
        _allRatings = [..._allRatings, ...newRatings];
        _lastPage = moreHistory.length < _pageSize ? _currentPage : _currentPage + 1;
        state = AsyncValue.data(_allRatings);
      }
    } catch (e) {
      // Ignore error on loadMore, just reset page
      _currentPage--;
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadInitial();
  }
}

final ratingProvider =
    StateNotifierProvider<RatingNotifier, AsyncValue<List<RatingModel>>>(
  (ref) => RatingNotifier(ref.watch(csatRepositoryProvider)),
);

final adminRatingProvider =
    StateNotifierProvider<RatingNotifier, AsyncValue<List<RatingModel>>>(
  (ref) => RatingNotifier(ref.watch(csatRepositoryProvider)),
);
