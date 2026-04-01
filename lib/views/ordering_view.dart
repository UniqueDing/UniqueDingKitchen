import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:unique_ding_kitchen/l10n/app_localizations.dart';
import 'package:unique_ding_kitchen/models/models.dart';
import 'package:unique_ding_kitchen/services/menu_repository.dart';
import 'package:unique_ding_kitchen/services/startup_shell_signal.dart';
import 'package:unique_ding_kitchen/views/ordering_data_loader.dart';
import 'package:unique_ding_kitchen/views/ordering_page_derived.dart';
import 'package:unique_ding_kitchen/views/hero_controls.dart';
import 'package:unique_ding_kitchen/views/share_dialog.dart';

const double _pageContentMaxWidth = 640;

class OrderingView extends StatefulWidget {
  const OrderingView({
    super.key,
    required this.repository,
    required this.siteName,
    required this.locale,
    required this.onThemeModeChanged,
    required this.onLocaleChanged,
  });

  final MenuRepository repository;
  final String siteName;
  final Locale locale;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<OrderingView> createState() => _OrderingViewState();
}

class _OrderingViewState extends State<OrderingView>
    with WidgetsBindingObserver {
  static const String _recommendationCategory = recommendationCategoryKey;
  static const double _heroTopInset = 8;
  static const double _heroBottomGap = 8;
  static const double _heroUnderlapOffset = 64;
  static const double _tocSwitchHysteresis = 16;

  final Map<String, int> _quantities = <String, int>{};
  final Map<String, String> _selectedFlavorByDish = <String, String>{};
  final Map<String, Set<String>> _selectedToppingsByDish =
      <String, Set<String>>{};
  final Map<String, GlobalKey> _sectionKeys = <String, GlobalKey>{};
  final Map<String, double> _sectionScrollOffsets = <String, double>{};
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _heroCardKey = GlobalKey();
  late final OrderingDataLoader _dataLoader;

  late Future<List<Dish>> _pageFuture;
  final ValueNotifier<String> _selectedCategory = ValueNotifier<String>('');
  bool _isProgrammaticScroll = false;
  String _recommendationLoadNote = '';
  bool _startupShellReadySent = false;
  bool _heroCardHeightSyncScheduled = false;
  bool _sectionOffsetRefreshScheduled = false;
  bool _sectionOffsetHydrationInProgress = false;
  double _heroCardHeight = 56;

  List<Dish>? _cachedDishesRef;
  OrderingDerivedState _cachedDerived = const OrderingDerivedState(
    categories: <String>[],
    groupedByCategory: <String, List<Dish>>{},
    menuEntries: <MenuListEntry>[],
  );

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dataLoader = OrderingDataLoader(repository: widget.repository);
    _pageFuture = _loadPageData();
    _scrollController.addListener(_syncCategoryFromScroll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && state == AppLifecycleState.resumed) {
      _reloadPageData();
    }
  }

  @override
  void didUpdateWidget(covariant OrderingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteName != widget.siteName ||
        oldWidget.locale != widget.locale) {
      _syncHeroCardHeight();
    }
  }

  @override
  void didChangeMetrics() {
    _syncHeroCardHeight();
    _scheduleSectionOffsetRefresh();
  }

  void _reloadPageData() {
    if (!mounted) {
      return;
    }
    setState(() {
      _startupShellReadySent = false;
      _cachedDishesRef = null;
      _sectionScrollOffsets.clear();
      _cachedDerived = const OrderingDerivedState(
        categories: <String>[],
        groupedByCategory: <String, List<Dish>>{},
        menuEntries: <MenuListEntry>[],
      );
      _pageFuture = _loadPageData();
    });
  }

  void _notifyStartupShellReadyAfterFrame() {
    if (_startupShellReadySent) {
      return;
    }
    _startupShellReadySent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyStartupShellReady();
    });
  }

  void _syncHeroCardHeight() {
    if (_heroCardHeightSyncScheduled) {
      return;
    }
    _heroCardHeightSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _heroCardHeightSyncScheduled = false;
      if (!mounted) {
        return;
      }
      final context = _heroCardKey.currentContext;
      final box = context?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        return;
      }
      final nextHeight = box.size.height;
      if ((nextHeight - _heroCardHeight).abs() < 0.5) {
        return;
      }
      setState(() {
        _heroCardHeight = nextHeight;
      });
      _scheduleSectionOffsetRefresh();
    });
  }

  void _scheduleSectionOffsetRefresh() {
    if (_sectionOffsetRefreshScheduled) {
      return;
    }
    _sectionOffsetRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sectionOffsetRefreshScheduled = false;
      if (!mounted) {
        return;
      }
      _refreshSectionScrollOffsets();
      _hydrateSectionOffsetsIfNeeded();
    });
  }

  void _refreshSectionScrollOffsets() {
    if (!_scrollController.hasClients) {
      return;
    }

    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final nextOffsets = <String, double>{};
    for (final category in _cachedDerived.categories) {
      final renderObject = _sectionKeys[category]?.currentContext
          ?.findRenderObject();
      if (renderObject == null) {
        continue;
      }
      final viewport = RenderAbstractViewport.of(renderObject);
      final revealOffset = viewport.getOffsetToReveal(renderObject, 0).offset;
      nextOffsets[category] = revealOffset.clamp(0.0, maxScrollExtent);
    }

    if (nextOffsets.isEmpty) {
      return;
    }

    _sectionScrollOffsets.addAll(nextOffsets);
    _syncCategoryFromScroll();
  }

  Future<void> _hydrateSectionOffsetsIfNeeded() async {
    if (!mounted ||
        _sectionOffsetHydrationInProgress ||
        !_scrollController.hasClients ||
        _cachedDerived.categories.isEmpty ||
        _sectionScrollOffsets.length >= _cachedDerived.categories.length) {
      return;
    }

    _sectionOffsetHydrationInProgress = true;
    final originalOffset = _scrollController.offset;
    final max = _scrollController.position.maxScrollExtent;

    try {
      for (final category in _cachedDerived.categories) {
        if (_sectionScrollOffsets.containsKey(category)) {
          continue;
        }

        RenderObject? renderObject = _sectionKeys[category]?.currentContext
            ?.findRenderObject();

        if (renderObject == null) {
          for (final probeOffset in _candidateCategoryOffsets(category)) {
            _scrollController.jumpTo(probeOffset);
            await WidgetsBinding.instance.endOfFrame;
            if (!mounted) {
              return;
            }
            renderObject = _sectionKeys[category]?.currentContext
                ?.findRenderObject();
            if (renderObject != null) {
              break;
            }
          }
        }

        if (renderObject == null) {
          continue;
        }

        final viewport = RenderAbstractViewport.of(renderObject);
        final revealOffset = viewport.getOffsetToReveal(renderObject, 0).offset;
        final clamped = revealOffset.clamp(0.0, max);
        _sectionScrollOffsets[category] = clamped;
      }
    } finally {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(originalOffset.clamp(0.0, max));
      }
      _sectionOffsetHydrationInProgress = false;
      if (mounted) {
        _syncCategoryFromScroll();
      }
    }
  }

  void _ensureMenuCache(List<Dish> dishes) {
    if (identical(_cachedDishesRef, dishes)) {
      return;
    }
    _cachedDishesRef = dishes;
    _cachedDerived = OrderingPageDeriver.derive(
      dishes,
      recommendationCategory: _recommendationCategory,
    );
    _syncHeroCardHeight();
    _scheduleSectionOffsetRefresh();
  }

  Future<List<Dish>> _loadPageData() async {
    final pageData = await _dataLoader.loadPageData();
    _recommendationLoadNote = pageData.recommendationLoadNote;
    return pageData.dishes;
  }

  bool _isTrilliumSource() {
    final repository = widget.repository;
    if (repository is AssetMenuRepository) {
      return repository.menuSource.trim().toLowerCase() == 'trillium';
    }
    return false;
  }

  String _trilliumUrl() {
    final repository = widget.repository;
    if (repository is AssetMenuRepository) {
      return repository.trilliumUrl.trim();
    }
    return '';
  }

  String _trilliumTitle() {
    final repository = widget.repository;
    if (repository is AssetMenuRepository) {
      return repository.trilliumTitle.trim();
    }
    return '';
  }

  Future<void> _openShareDialog() async {
    final shareUri = Uri.base.replace(query: '', fragment: '');
    await showDialog<void>(
      context: context,
      builder: (context) {
        return ShareDialog(shareUri: shareUri, siteName: widget.siteName);
      },
    );
  }

  Future<void> _copyRecommendationLoadNote() async {
    if (_recommendationLoadNote.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: _recommendationLoadNote));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.recommendationDiagCopied)));
  }

  String _categoryLabel(String category) {
    return category == _recommendationCategory
        ? l10n.recommendationTocLabel
        : category;
  }

  String _displayCategoryName(String category) {
    return category == _recommendationCategory
        ? l10n.recommendationCategoryTitle
        : category;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _selectedCategory.dispose();
    _scrollController
      ..removeListener(_syncCategoryFromScroll)
      ..dispose();
    super.dispose();
  }

  void _syncCategoryFromScroll() {
    if (_isProgrammaticScroll) {
      return;
    }

    if (_sectionScrollOffsets.length < _cachedDerived.categories.length) {
      _scheduleSectionOffsetRefresh();
      _hydrateSectionOffsetsIfNeeded();
    }

    String? activeCategory;
    String? firstKnownCategory;
    final currentOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final activationOffset =
        currentOffset + _heroUnderlapOffset + _tocSwitchHysteresis;

    for (final category in _cachedDerived.categories) {
      final sectionOffset = _sectionScrollOffsets[category];
      if (sectionOffset == null) {
        continue;
      }
      firstKnownCategory ??= category;

      if (sectionOffset <= activationOffset) {
        activeCategory = category;
      }
    }

    activeCategory ??= firstKnownCategory;
    if (activeCategory == null && _cachedDerived.categories.isNotEmpty) {
      activeCategory = _cachedDerived.categories.first;
    }

    if (activeCategory != null && activeCategory != _selectedCategory.value) {
      _selectedCategory.value = activeCategory;
    }
  }

  bool _isDefaultFlavorValue(String value) {
    const defaults = <String>{'默认', 'Default', '標準', '기본'};
    return defaults.contains(value.trim());
  }

  bool _isDefaultToppingValue(String value) {
    const defaults = <String>{'不加', 'None', 'なし', '없음'};
    return defaults.contains(value.trim());
  }

  String _normalizeFlavorValue(String value) {
    return value.trim();
  }

  String _normalizeToppingValue(String value) {
    return value.trim();
  }

  _DishOptionConfig? _optionConfig(Dish dish) {
    final hasFlavor = dish.flavors.isNotEmpty;
    final hasTopping = dish.toppings.isNotEmpty;
    if (!hasFlavor && !hasTopping) {
      return null;
    }

    final flavorValues = dish.flavors
        .map(_normalizeFlavorValue)
        .where((item) => item.isNotEmpty && !_isDefaultFlavorValue(item))
        .toList();
    final toppingValues = dish.toppings
        .map(_normalizeToppingValue)
        .where((item) => item.isNotEmpty && !_isDefaultToppingValue(item))
        .toList();

    if (flavorValues.isEmpty && toppingValues.isEmpty) {
      return null;
    }

    final flavors = hasFlavor ? flavorValues : <String>[];
    final toppings = hasTopping ? toppingValues : <String>[];

    return _DishOptionConfig(flavors: flavors, toppings: toppings);
  }

  String _buildCartKey(
    String dishId, {
    required String flavor,
    required Iterable<String> toppings,
  }) {
    final normalizedFlavor = flavor.trim();
    final normalizedToppings =
        toppings
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList()
          ..sort();
    final toppingPart = normalizedToppings.join('|');
    return '$dishId::f=$normalizedFlavor::t=$toppingPart';
  }

  ({String dishId, String flavor, List<String> toppings}) _parseCartKey(
    String key,
  ) {
    final parts = key.split('::');
    final dishId = parts.isNotEmpty ? parts[0] : key;
    String flavor = '';
    List<String> toppings = const <String>[];
    for (final part in parts.skip(1)) {
      if (part.startsWith('f=')) {
        flavor = part.substring(2).trim();
      } else if (part.startsWith('t=')) {
        final raw = part.substring(2).trim();
        toppings = raw.isEmpty
            ? const <String>[]
            : raw.split('|').where((item) => item.isNotEmpty).toList();
      }
    }
    return (dishId: dishId, flavor: flavor, toppings: toppings);
  }

  String _currentCartKeyForDish(Dish dish) {
    final config = _optionConfig(dish);
    if (config == null) {
      return _buildCartKey(dish.id, flavor: '', toppings: const <String>[]);
    }

    final flavor = _selectedFlavorByDish[dish.id] ?? '';
    final toppings = _selectedToppingsByDish[dish.id] ?? const <String>{};

    return _buildCartKey(dish.id, flavor: flavor, toppings: toppings);
  }

  List<CartItem> _cartItems(List<Dish> dishes) {
    final dishById = <String, Dish>{for (final dish in dishes) dish.id: dish};
    final items = <CartItem>[];

    for (final entry in _quantities.entries) {
      final quantity = entry.value;
      if (quantity <= 0) {
        continue;
      }
      final parsed = _parseCartKey(entry.key);
      final dish = dishById[parsed.dishId];
      if (dish == null) {
        continue;
      }
      items.add(
        CartItem(
          cartKey: entry.key,
          dish: dish,
          quantity: quantity,
          flavor: parsed.flavor,
          toppings: parsed.toppings,
        ),
      );
    }
    return items;
  }

  int _dishTotalQuantity(String dishId) {
    var total = 0;
    for (final entry in _quantities.entries) {
      final parsed = _parseCartKey(entry.key);
      if (parsed.dishId == dishId) {
        total += entry.value;
      }
    }
    return total;
  }

  List<String> _visibleOptionDetails({
    required String flavor,
    required Iterable<String> toppings,
  }) {
    final details = <String>[];
    final normalizedFlavor = flavor.trim();
    if (normalizedFlavor.isNotEmpty &&
        !_isDefaultFlavorValue(normalizedFlavor)) {
      details.add('${l10n.flavorPrefix}:$normalizedFlavor');
    }

    final visibleToppings = toppings
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && !_isDefaultToppingValue(item))
        .toList();
    if (visibleToppings.isNotEmpty) {
      details.add('${l10n.toppingPrefix}:${visibleToppings.join('、')}');
    }
    return details;
  }

  String _cartItemDisplayName(CartItem item) {
    final details = _visibleOptionDetails(
      flavor: item.flavor,
      toppings: item.toppings,
    );
    if (details.isEmpty) {
      return item.dish.name;
    }
    return '${item.dish.name} (${details.join('，')})';
  }

  void _incrementByCartKey(String cartKey) {
    setState(() {
      _quantities[cartKey] = (_quantities[cartKey] ?? 0) + 1;
    });
  }

  Future<void> _handleAddTap(Dish dish) async {
    final config = _optionConfig(dish);
    var shouldAdd = true;
    if (config != null) {
      shouldAdd = await _openOptionsMenu(dish, config);
    }
    if (!shouldAdd) {
      return;
    }
    _incrementByCartKey(_currentCartKeyForDish(dish));
  }

  void _decrementByCartKey(String cartKey) {
    final current = _quantities[cartKey] ?? 0;
    if (current == 0) {
      return;
    }

    setState(() {
      if (current == 1) {
        _quantities.remove(cartKey);
      } else {
        _quantities[cartKey] = current - 1;
      }
    });
  }

  void _decrementDishSelection(Dish dish) {
    final currentKey = _currentCartKeyForDish(dish);
    if ((_quantities[currentKey] ?? 0) > 0) {
      _decrementByCartKey(currentKey);
      return;
    }

    for (final entry in _quantities.entries) {
      if (entry.value <= 0) {
        continue;
      }
      final parsed = _parseCartKey(entry.key);
      if (parsed.dishId == dish.id) {
        _decrementByCartKey(entry.key);
        return;
      }
    }
  }

  Future<bool> _openOptionsMenu(Dish dish, _DishOptionConfig config) async {
    final selectedFlavor = _normalizeFlavorValue(
      _selectedFlavorByDish[dish.id] ?? '',
    );
    final initialFlavor = config.flavors.contains(selectedFlavor)
        ? selectedFlavor
        : '';
    final selectedToppings = (_selectedToppingsByDish[dish.id] ?? <String>{})
        .map(_normalizeToppingValue)
        .where((item) => config.toppings.contains(item))
        .toSet();

    final result = await showModalBottomSheet<_OptionSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OptionSheet(
        dishName: dish.name,
        config: config,
        initialFlavor: initialFlavor,
        initialToppings: selectedToppings,
      ),
    );

    if (result == null) {
      return false;
    }

    setState(() {
      final normalizedFlavor = _normalizeFlavorValue(result.flavor);
      if (normalizedFlavor.isEmpty) {
        _selectedFlavorByDish.remove(dish.id);
      } else {
        _selectedFlavorByDish[dish.id] = normalizedFlavor;
      }

      final normalizedToppings = result.toppings
          .map(_normalizeToppingValue)
          .where((item) => item.isNotEmpty)
          .toSet();
      if (normalizedToppings.isEmpty) {
        _selectedToppingsByDish.remove(dish.id);
      } else {
        _selectedToppingsByDish[dish.id] = normalizedToppings;
      }
    });
    return true;
  }

  Future<void> _scrollToCategory(String category) async {
    _selectedCategory.value = category;
    _isProgrammaticScroll = true;
    try {
      BuildContext? targetContext = _sectionKeys[category]?.currentContext;

      if (targetContext == null && _scrollController.hasClients) {
        for (final offset in _candidateCategoryOffsets(category)) {
          _scrollController.jumpTo(offset);
          if (!mounted) {
            return;
          }
          await WidgetsBinding.instance.endOfFrame;
          targetContext = _sectionKeys[category]?.currentContext;
          if (targetContext != null) {
            break;
          }
        }
      }

      if (targetContext == null) {
        return;
      }

      if (!_scrollController.hasClients) {
        return;
      }

      final renderObject = _sectionKeys[category]?.currentContext
          ?.findRenderObject();
      if (renderObject == null) {
        return;
      }

      final viewport = RenderAbstractViewport.of(renderObject);
      final revealOffset = viewport.getOffsetToReveal(renderObject, 0).offset;
      final targetOffset = revealOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      final adjustedOffset = (targetOffset - _heroUnderlapOffset).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );

      await _scrollController.animateTo(
        adjustedOffset.toDouble(),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (mounted) {
        _isProgrammaticScroll = false;
      }
    }
  }

  List<double> _candidateCategoryOffsets(String category) {
    if (!_scrollController.hasClients) {
      return const <double>[];
    }

    final categories = _cachedDerived.categories;
    final index = categories.indexOf(category);
    if (index < 0) {
      return const <double>[];
    }

    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) {
      return const <double>[0];
    }

    final ratio = categories.length <= 1
        ? 0.0
        : index / (categories.length - 1);
    final raw = <double>[
      ratio,
      ratio - 0.12,
      ratio + 0.12,
      ratio - 0.24,
      ratio + 0.24,
    ];

    final offsets = <double>[];
    for (final item in raw) {
      final clampedRatio = item.clamp(0.0, 1.0);
      final offset = (max * clampedRatio).toDouble();
      if (offsets.any((existing) => (existing - offset).abs() < 4)) {
        continue;
      }
      offsets.add(offset);
    }
    return offsets;
  }

  Widget _buildCategoryHeader(BuildContext context, String category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: _sectionKeys[category],
      margin: const EdgeInsets.only(bottom: 8, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _displayCategoryName(category),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontSize: 17),
          ),
          if (category == _recommendationCategory &&
              _recommendationLoadNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      _recommendationLoadNote,
                      key: const Key('recommendation-load-note'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? const Color(0xFFE2B09C)
                            : const Color(0xFFB65E48),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('copy-recommendation-load-note'),
                    onPressed: _copyRecommendationLoadNote,
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: l10n.copyDiagTooltip,
                    visualDensity: VisualDensity.compact,
                    color: isDark
                        ? const Color(0xFFE2B09C)
                        : const Color(0xFFB65E48),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openOrderSummary(List<CartItem> items) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _OrderSummaryPage(
          items: List<CartItem>.from(items),
          buildOrderText: (note) => _buildOrderText(items, note),
          categoryLabel: _displayCategoryName,
          itemLabel: _cartItemDisplayName,
        ),
      ),
    );
  }

  String _buildOrderText(List<CartItem> items, String note) {
    final lines = <String>[widget.siteName];
    if (note.isNotEmpty) {
      lines.add('${l10n.notePrefix}: $note');
    }
    String? currentCategory;

    for (final item in items) {
      if (item.dish.category != currentCategory) {
        currentCategory = item.dish.category;
        lines
          ..add('')
          ..add('【${_displayCategoryName(currentCategory)}】');
      }

      final details = _visibleOptionDetails(
        flavor: item.flavor,
        toppings: item.toppings,
      );
      var dishLabel = item.dish.name;
      if (details.isNotEmpty) {
        dishLabel = '$dishLabel (${details.join('，')})';
      }
      final line = '- $dishLabel x ${item.quantity}';
      lines.add(line);
    }

    return lines.join('\n').trim();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Dish>>(
      future: _pageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildInitialLoadingScaffold(context);
        }

        if (snapshot.hasError) {
          _notifyStartupShellReadyAfterFrame();
          final errorText = '${snapshot.error}'.trim();
          final isTrillium = _isTrilliumSource();
          final hint = isTrillium
              ? l10n.menuLoadFailedHintTrillium
              : l10n.menuLoadFailedHintMarkdown;
          final url = _trilliumUrl();
          final title = _trilliumTitle();
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.menuLoadFailedTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(hint, style: Theme.of(context).textTheme.bodyMedium),
                    if (isTrillium) ...[
                      const SizedBox(height: 10),
                      Text(
                        l10n.menuLoadSourceInfoLabel,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        '${l10n.menuLoadTrilliumUrlLabel}: ${url.isEmpty ? '-empty-' : url}\n'
                        '${l10n.menuLoadTrilliumTitleLabel}: ${title.isEmpty ? '-empty-' : title}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (errorText.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        l10n.menuLoadFailedDetailLabel,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        errorText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        _notifyStartupShellReadyAfterFrame();
        final dishes = snapshot.data ?? <Dish>[];
        _ensureMenuCache(dishes);
        final categories = _cachedDerived.categories;
        if (_selectedCategory.value.isEmpty && categories.isNotEmpty) {
          _selectedCategory.value = categories.first;
        }

        for (final category in categories) {
          _sectionKeys.putIfAbsent(category, GlobalKey.new);
        }
        final menuEntries = _cachedDerived.menuEntries;
        final cartItems = _cartItems(dishes);
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final totalItems = cartItems.fold<int>(
          0,
          (sum, item) => sum + item.quantity,
        );

        Future<void> openSelectedDishes() async {
          await showDialog<void>(
            context: context,
            barrierColor: const Color(0x22000000),
            builder: (context) {
              return StatefulBuilder(
                builder: (context, dialogSetState) {
                  final popupCartItems = _cartItems(dishes);
                  final groupedPopupItems =
                      OrderingPageDeriver.groupCartItemsByCategory(
                        popupCartItems,
                      );
                  return Stack(
                    children: [
                      Positioned(
                        left: 12,
                        right: 84,
                        bottom: 92,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2D2521)
                                  : const Color(0xFFF9F3EB),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x302C1D18),
                                  blurRadius: 16,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(12),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.sizeOf(context).height * 0.62,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        l10n.selectedDishesTitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(fontSize: 16),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        icon: const Icon(Icons.close_rounded),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  if (popupCartItems.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(l10n.selectedDishesEmptyHint),
                                    )
                                  else
                                    Flexible(
                                      child: SingleChildScrollView(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: groupedPopupItems.expand((
                                            entry,
                                          ) {
                                            final category = entry.key;
                                            final items = entry.value;
                                            return <Widget>[
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 6,
                                                  bottom: 4,
                                                ),
                                                child: _CategoryGroupHeader(
                                                  label: _displayCategoryName(
                                                    category,
                                                  ),
                                                ),
                                              ),
                                              ...items.map((item) {
                                                final itemKey =
                                                    item.cartKey.hashCode;
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 8,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          _cartItemDisplayName(
                                                            item,
                                                          ),
                                                        ),
                                                      ),
                                                      IconButton.filledTonal(
                                                        key: Key(
                                                          'panel-remove-$itemKey',
                                                        ),
                                                        onPressed: () {
                                                          _decrementByCartKey(
                                                            item.cartKey,
                                                          );
                                                          dialogSetState(() {});
                                                        },
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        icon: const Icon(
                                                          Icons.remove_rounded,
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                            ),
                                                        child: Text(
                                                          '${item.quantity}',
                                                        ),
                                                      ),
                                                      IconButton.filled(
                                                        key: Key(
                                                          'panel-add-$itemKey',
                                                        ),
                                                        onPressed: () {
                                                          _incrementByCartKey(
                                                            item.cartKey,
                                                          );
                                                          dialogSetState(() {});
                                                        },
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        style:
                                                            IconButton.styleFrom(
                                                              backgroundColor:
                                                                  const Color(
                                                                    0xFFB65E48,
                                                                  ),
                                                            ),
                                                        icon: const Icon(
                                                          Icons.add_rounded,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                            ];
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        }

        return Scaffold(
          body: Stack(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                        ? const <Color>[
                            Color(0xFF1A1715),
                            Color(0xFF211C19),
                            Color(0xFF2A2421),
                          ]
                        : const <Color>[
                            Color(0xFFF6EBDD),
                            Color(0xFFF8F1E7),
                            Color(0xFFFDFBF8),
                          ],
                  ),
                ),
                child: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _pageContentMaxWidth,
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(
                                    top:
                                        _heroTopInset +
                                        _heroCardHeight +
                                        _heroBottomGap,
                                  ),
                                  child: Row(
                                    children: [
                                      ValueListenableBuilder<String>(
                                        valueListenable: _selectedCategory,
                                        builder:
                                            (context, selectedCategory, _) {
                                              return _CategoryToc(
                                                categories: categories,
                                                selectedCategory:
                                                    selectedCategory,
                                                onTapCategory:
                                                    _scrollToCategory,
                                                categoryLabel: _categoryLabel,
                                              );
                                            },
                                      ),
                                      Expanded(
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Transform.translate(
                                              offset: const Offset(
                                                0,
                                                -_heroUnderlapOffset,
                                              ),
                                              child: ListView.builder(
                                                controller: _scrollController,
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      8,
                                                      _heroUnderlapOffset + 8,
                                                      16,
                                                      196,
                                                    ),
                                                itemCount: menuEntries.length,
                                                itemBuilder: (context, index) {
                                                  final entry =
                                                      menuEntries[index];
                                                  if (entry.category != null) {
                                                    return _buildCategoryHeader(
                                                      context,
                                                      entry.category!,
                                                    );
                                                  }

                                                  final dish = entry.dish!;
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 10,
                                                        ),
                                                    child: RepaintBoundary(
                                                      child: _DishCard(
                                                        dish: dish,
                                                        quantity:
                                                            _dishTotalQuantity(
                                                              dish.id,
                                                            ),
                                                        optionConfig:
                                                            _optionConfig(dish),
                                                        onAdd: () =>
                                                            _handleAddTap(dish),
                                                        onRemove: () =>
                                                            _decrementDishSelection(
                                                              dish,
                                                            ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  left: 16,
                                  right: 16,
                                  top: _heroTopInset,
                                  child: KeyedSubtree(
                                    key: _heroCardKey,
                                    child: HeroCardPanel(
                                      siteName: widget.siteName,
                                      locale: widget.locale,
                                      onThemeModeChanged:
                                          widget.onThemeModeChanged,
                                      onLocaleChanged: widget.onLocaleChanged,
                                      onOpenShare: _openShareDialog,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _pageContentMaxWidth,
                    ),
                    child: _OrderBar(
                      totalItems: totalItems,
                      onGenerate: totalItems == 0
                          ? null
                          : () => _openOrderSummary(cartItems),
                      onOpenSelected: openSelectedDishes,
                      selectedCount: totalItems,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInitialLoadingScaffold(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF2F2824)
        : const Color(0xFFF1E5D9);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const <Color>[
                    Color(0xFF1A1715),
                    Color(0xFF211C19),
                    Color(0xFF2A2421),
                  ]
                : const <Color>[
                    Color(0xFFF6EBDD),
                    Color(0xFFF8F1E7),
                    Color(0xFFFDFBF8),
                  ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _pageContentMaxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  children: [
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Row(
                        children: [
                          Column(
                            children: List<Widget>.generate(6, (index) {
                              return Container(
                                width: 72,
                                height: 36,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: baseColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ListView.separated(
                              itemCount: 8,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                return Container(
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: baseColor,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                        const SizedBox(width: 10),
                        const Text('Loading...'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DishOptionConfig {
  const _DishOptionConfig({required this.flavors, required this.toppings});

  final List<String> flavors;
  final List<String> toppings;
}

class _OptionSelection {
  const _OptionSelection({required this.flavor, required this.toppings});

  final String flavor;
  final Set<String> toppings;
}

class _CategoryToc extends StatelessWidget {
  const _CategoryToc({
    required this.categories,
    required this.selectedCategory,
    required this.onTapCategory,
    required this.categoryLabel,
  });

  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onTapCategory;
  final String Function(String category) categoryLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 84,
      margin: const EdgeInsets.fromLTRB(12, 0, 8, 0),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final selected = category == selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    key: Key('category-$category'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onTapCategory(category),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFB65E48)
                            : (isDark
                                  ? const Color(0xFF2F2824)
                                  : const Color(0xFFFFFFFF)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFB65E48)
                              : (isDark
                                    ? const Color(0xFF5A4A42)
                                    : const Color(0xFFE7D7CB)),
                        ),
                      ),
                      child: Text(
                        categoryLabel(category),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : (isDark
                                    ? const Color(0xFFF3E8DE)
                                    : const Color(0xFF5A4339)),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
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

class _DishCard extends StatelessWidget {
  const _DishCard({
    required this.dish,
    required this.quantity,
    required this.optionConfig,
    required this.onAdd,
    required this.onRemove,
  });

  final Dish dish;
  final int quantity;
  final _DishOptionConfig? optionConfig;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasDescription = dish.description.trim().isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF312925).withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF5C4A42)
                    : const Color(0xFFEAD8C4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 1),
                    child: Column(
                      key: Key('dish-content-${dish.id}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: hasDescription
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: [
                        Text(
                          dish.name,
                          style: textTheme.titleLarge?.copyWith(
                            fontSize: 18,
                            height: 1.2,
                          ),
                        ),
                        if (hasDescription) ...[
                          const SizedBox(height: 5),
                          Text(
                            dish.description,
                            style: textTheme.bodyMedium?.copyWith(fontSize: 14),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IgnorePointer(
                      ignoring: quantity == 0,
                      child: Opacity(
                        opacity: quantity == 0 ? 0 : 1,
                        child: IconButton.filledTonal(
                          key: Key('remove-${dish.id}'),
                          onPressed: onRemove,
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.remove_rounded),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 26,
                      child: Center(
                        child: quantity > 0
                            ? Text(
                                '$quantity',
                                style: textTheme.titleLarge?.copyWith(
                                  fontSize: 17,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    IconButton.filled(
                      key: Key('add-${dish.id}'),
                      onPressed: onAdd,
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      constraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 34,
                      ),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFB65E48),
                      ),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (optionConfig != null)
            Positioned(
              right: 0,
              top: 0,
              child: ClipPath(
                clipper: _CornerTriangleClipper(),
                child: Container(
                  width: 30,
                  height: 30,
                  color: const Color(0xFFD27D5C),
                  alignment: const Alignment(0.55, -0.55),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CornerTriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _OptionSheet extends StatefulWidget {
  const _OptionSheet({
    required this.dishName,
    required this.config,
    required this.initialFlavor,
    required this.initialToppings,
  });

  final String dishName;
  final _DishOptionConfig config;
  final String initialFlavor;
  final Set<String> initialToppings;

  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends State<_OptionSheet> {
  late String _flavor;
  late Set<String> _toppings;

  @override
  void initState() {
    super.initState();
    _flavor = widget.initialFlavor;
    _toppings = Set<String>.from(widget.initialToppings);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2521) : const Color(0xFFF9F3EB),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.configureDishTitle(widget.dishName),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 12),
              if (widget.config.flavors.isNotEmpty)
                _SingleSelectChips(
                  title: l10n.flavorSingleSelect,
                  options: widget.config.flavors,
                  selected: _flavor,
                  onSelected: (value, selected) {
                    setState(() {
                      _flavor = selected ? value : '';
                    });
                  },
                ),
              if (widget.config.flavors.isNotEmpty &&
                  widget.config.toppings.isNotEmpty)
                const SizedBox(height: 10),
              if (widget.config.toppings.isNotEmpty)
                _MultiSelectChips(
                  title: l10n.toppingMultiSelect,
                  options: widget.config.toppings,
                  selected: _toppings,
                  onToggle: (value, selected) {
                    setState(() {
                      if (selected) {
                        _toppings.add(value);
                      } else {
                        _toppings.remove(value);
                      }
                    });
                  },
                ),
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('save-options'),
                onPressed: () {
                  Navigator.of(context).pop(
                    _OptionSelection(
                      flavor: _flavor,
                      toppings: Set<String>.from(_toppings),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: const Color(0xFFB65E48),
                ),
                child: Text(l10n.saveSelection),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SingleSelectChips extends StatelessWidget {
  const _SingleSelectChips({
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final List<String> options;
  final String selected;
  final void Function(String value, bool selected) onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: options
              .map(
                (option) => ChoiceChip(
                  key: Key('sheet-flavor-$option'),
                  label: Text(option),
                  selected: selected == option,
                  onSelected: (value) => onSelected(option, value),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _MultiSelectChips extends StatelessWidget {
  const _MultiSelectChips({
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final String title;
  final List<String> options;
  final Set<String> selected;
  final void Function(String value, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: options
              .map(
                (option) => FilterChip(
                  key: Key('sheet-topping-$option'),
                  label: Text(option),
                  selected: selected.contains(option),
                  onSelected: (value) => onToggle(option, value),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _OrderBar extends StatelessWidget {
  const _OrderBar({
    required this.totalItems,
    required this.onGenerate,
    required this.onOpenSelected,
    required this.selectedCount,
  });

  final int totalItems;
  final VoidCallback? onGenerate;
  final VoidCallback onOpenSelected;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomInset),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xC9231D1A) : const Color(0xB82C1D18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                IconButton.filledTonal(
                  key: const Key('show-selected-dishes'),
                  onPressed: onOpenSelected,
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0x66504139)
                        : const Color(0x66332621),
                    foregroundColor: const Color(0xFFFFE5CB),
                  ),
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.restaurant_menu_rounded),
                      Positioned(
                        right: -7,
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFB65E48),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$selectedCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        totalItems == 0
                            ? l10n.noDishYet
                            : l10n.selectedDishCount(totalItems),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                    ],
                  ),
                ),
                FilledButton(
                  key: const Key('generate-order-text'),
                  onPressed: onGenerate,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF1B577),
                    foregroundColor: const Color(0xFF2C1D18),
                  ),
                  child: Text(l10n.placeOrder),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryGroupHeader extends StatelessWidget {
  const _CategoryGroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFFB65E48),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: isDark ? const Color(0xFFE2B09C) : const Color(0xFF7D4B3A),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _OrderSummaryPage extends StatefulWidget {
  const _OrderSummaryPage({
    required this.items,
    required this.buildOrderText,
    required this.categoryLabel,
    required this.itemLabel,
  });

  final List<CartItem> items;
  final String Function(String note) buildOrderText;
  final String Function(String category) categoryLabel;
  final String Function(CartItem item) itemLabel;

  @override
  State<_OrderSummaryPage> createState() => _OrderSummaryPageState();
}

class _OrderSummaryPageState extends State<_OrderSummaryPage> {
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groupedItems = <String, List<CartItem>>{};
    for (final item in widget.items) {
      groupedItems
          .putIfAbsent(item.dish.category, () => <CartItem>[])
          .add(item);
    }

    Future<void> onCopy() async {
      final orderText = widget.buildOrderText(_noteController.text.trim());
      await Clipboard.setData(ClipboardData(text: orderText));
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.orderTextCopied)));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.orderConfirmTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _pageContentMaxWidth),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      l10n.orderedMenuTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    ...groupedItems.entries.expand((entry) {
                      final category = entry.key;
                      final items = entry.value;
                      return <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 4),
                          child: _CategoryGroupHeader(
                            label: widget.categoryLabel(category),
                          ),
                        ),
                        ...items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(child: Text(widget.itemLabel(item))),
                                Text('${item.quantity}'),
                              ],
                            ),
                          ),
                        ),
                      ];
                    }),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2F2824)
                              : const Color(0xFFFFFBF6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF5A4A42)
                                : const Color(0xFFE7D7CB),
                          ),
                        ),
                        child: TextField(
                          key: const Key('summary-note-input'),
                          controller: _noteController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: l10n.noteOptionalHint,
                            isDense: true,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('summary-add-more'),
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(l10n.addDish),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              key: const Key('summary-copy'),
                              onPressed: onCopy,
                              child: Text(l10n.copy),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
