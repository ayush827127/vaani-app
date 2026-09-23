import '../../../core/utils/formatters.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/constants.dart';
import '../../../core/db/database_helper.dart';
import '../../../core/di/injector.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../auth/repositories/shop_repository.dart';

class AIManagerScreen extends StatefulWidget {
  const AIManagerScreen({super.key});

  @override
  State<AIManagerScreen> createState() => _AIManagerScreenState();
}

class _AIManagerScreenState extends State<AIManagerScreen> {
  static String _billsText(int n) => '$n ${n == 1 ? 'bill' : 'bills'}';

  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;
  int _shopId = 1;
  String _ownerName = '';

  List<String> _suggestions(AppLocalizations l10n) => [
    l10n.aiSuggestionTopSeller,
    l10n.aiSuggestionRestock,
    l10n.aiSuggestionProfit,
    l10n.aiSuggestionBillCount,
    l10n.aiSuggestionBestCustomer,
    l10n.aiSuggestionWeekSales,
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _shopId = prefs.getInt(AppConstants.keyShopId) ?? 1;
    final shop = await getIt<ShopRepository>().getShop();
    if (!mounted) return;
    final firstName = (shop?.ownerName ?? '').split(' ').first.trim();
    setState(() {
      _ownerName = firstName.isNotEmpty ? firstName : 'there';
      _messages.add(_ChatMessage(
        text: context.l10n.aiGreeting(_ownerName),
        isAI: true,
      ));
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _messageCtrl.clear();

    setState(() {
      _messages.add(_ChatMessage(text: text, isAI: false));
      _isTyping = true;
    });
    _scrollToBottom();

    await Future.delayed(const Duration(milliseconds: 500));
    final response = await _processQuery(text.toLowerCase());

    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(text: response, isAI: true));
      _isTyping = false;
    });
    _scrollToBottom();
  }

  Future<String> _processQuery(String query) async {
    final db = await DatabaseHelper.instance.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final thisMonth = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

    // TOP_PRODUCT_TODAY
    if (_matchesIntent(query, ['what sold most', 'best item', 'top item', 'best seller', 'top item'])) {
      final result = await db.rawQuery('''
        SELECT p.name, SUM(ii.quantity) as qty FROM invoice_items ii
        JOIN items p ON p.id = ii.item_id
        JOIN invoices i ON i.id = ii.invoice_id
        WHERE i.shop_id = ? AND DATE(i.created_at) = ? AND i.deleted_at IS NULL AND i.status != 'cancelled'
        GROUP BY p.id ORDER BY qty DESC LIMIT 1
      ''', [_shopId, today]);
      if (result.isEmpty) return '📦 No sales recorded today yet. Start your first bill!';
      return '📦 Your best seller today is **${result.first['name']}** with ${result.first['qty']} units sold. Keep it well stocked!';
    }

    // SALES_TODAY
    if (_matchesIntent(query, ['today sales', 'how much today', 'kitna bikaa', 'aaj ki sale', 'daily sales'])) {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(grand_total), 0) as total, COUNT(*) as bills
        FROM invoices WHERE shop_id = ? AND DATE(created_at) = ? AND deleted_at IS NULL AND status != 'cancelled'
      ''', [_shopId, today]);
      final total = (result.first['total'] as num).toDouble();
      final bills = result.first['bills'] as int;
      return '💰 You\'ve made ${AppFormatters.formatCurrency(total.toDouble())} today across ${_billsText(bills)}. ${total > 5000 ? '🚀 Great day!' : 'Keep going!'}';
    }

    // PROFIT_TODAY
    if (_matchesIntent(query, ['profit today', 'aaj ka profit', 'earnings', 'how much profit', 'net profit'])) {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(i.grand_total) - SUM(ii.quantity * ii.cost_price), 0) as profit
        FROM invoices i JOIN invoice_items ii ON ii.invoice_id = i.id
        WHERE i.shop_id = ? AND DATE(i.created_at) = ? AND i.deleted_at IS NULL AND i.status != 'cancelled'
      ''', [_shopId, today]);
      final profit = (result.first['profit'] as num).toDouble();
      return '🟢 Today\'s estimated profit is ${AppFormatters.formatCurrency(profit.toDouble())}. Great going, $_ownerName!';
    }

    // SALES_WEEK
    if (_matchesIntent(query, ['this week', 'weekly', 'week mein', 'week sales', 'weekly sales'])) {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(grand_total), 0) as total, COUNT(*) as bills
        FROM invoices WHERE shop_id = ? AND created_at >= DATE('now', '-7 days')
          AND deleted_at IS NULL AND status != 'cancelled'
      ''', [_shopId]);
      final total = (result.first['total'] as num).toDouble();
      final bills = result.first['bills'] as int;
      final avg = bills > 0 ? total / 7 : 0;
      return '📈 This week\'s sales total is ${AppFormatters.formatCurrency(total.toDouble())} across ${_billsText(bills)}. That\'s ${AppFormatters.formatCurrency(avg.toDouble())} per day on average.';
    }

    // SALES_MONTH
    if (_matchesIntent(query, ['this month', 'monthly', 'mahine mein', 'month sales'])) {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(grand_total), 0) as total, COUNT(*) as bills
        FROM invoices WHERE shop_id = ? AND strftime('%Y-%m', created_at) = ?
          AND deleted_at IS NULL AND status != 'cancelled'
      ''', [_shopId, thisMonth]);
      final total = (result.first['total'] as num).toDouble();
      final bills = result.first['bills'] as int;
      return '📊 This month\'s sales: ${AppFormatters.formatCurrency(total.toDouble())} in ${_billsText(bills)}.';
    }

    // RESTOCK_NEEDED
    if (_matchesIntent(query, ['restock', 'kya mangaana', 'low stock', 'order what', 'what to order', 'refill'])) {
      final result = await db.rawQuery('''
        SELECT name, stock_quantity, reorder_level FROM items
        WHERE shop_id = ? AND is_active = 1 AND stock_quantity <= reorder_level
        ORDER BY stock_quantity ASC LIMIT 5
      ''', [_shopId]);
      if (result.isEmpty) return '✅ Great news! All items are sufficiently stocked.';
      final list = result.map((r) => '• ${r['name']} (${r['stock_quantity']} left)').join('\n');
      return '🔁 Time to restock these items:\n$list\n\nOrder these before you run out!';
    }

    // TOP_CUSTOMER
    if (_matchesIntent(query, ['best customer', 'top customer', 'highest spend', 'regular customer', 'vip customer'])) {
      final result = await db.rawQuery('''
        SELECT name, total_purchases FROM customers WHERE shop_id = ?
        ORDER BY total_purchases DESC LIMIT 3
      ''', [_shopId]);
      if (result.isEmpty) return '👥 No customer data yet. Start adding customers to track their purchases!';
      final list = result.asMap().entries.map((e) => '${e.key + 1}. ${e.value['name']} (${AppFormatters.formatCurrency((e.value['total_purchases'] as num).toDouble())})').join('\n');
      return '⭐ Your top customers:\n$list';
    }

    // BILLS_COUNT
    if (_matchesIntent(query, ['how many bills', 'kitne bill', 'bill count', 'bills today', 'invoice count'])) {
      final result = await db.rawQuery('''
        SELECT COUNT(*) as cnt FROM invoices WHERE DATE(created_at) = ? AND shop_id = ?
      ''', [today, _shopId]);
      final count = result.first['cnt'] as int;
      return '🧾 You\'ve generated ${_billsText(count)} so far today.';
    }

    // INVENTORY_STATUS
    if (_matchesIntent(query, ['inventory', 'stock status', 'items', 'how many items', 'total items'])) {
      final result = await db.rawQuery('''
        SELECT COUNT(*) as total,
          SUM(CASE WHEN stock_quantity > reorder_level THEN 1 ELSE 0 END) as in_stock,
          SUM(CASE WHEN stock_quantity <= reorder_level AND stock_quantity > 0 THEN 1 ELSE 0 END) as low,
          SUM(CASE WHEN stock_quantity = 0 THEN 1 ELSE 0 END) as out
        FROM items WHERE shop_id = ? AND is_active = 1
      ''', [_shopId]);
      if (result.isEmpty) return '📦 No items yet. Add your first item to get started!';
      final r = result.first;
      return '📦 Inventory status:\n✅ In stock: ${r['in_stock']}\n⚠️ Low stock: ${r['low']}\n❌ Out of stock: ${r['out']}\n📊 Total items: ${r['total']}';
    }

    return '🤔 I didn\'t quite understand that. Try asking:\n• "What sold most today?"\n• "What should I restock?"\n• "What\'s my profit today?"\n• "Best customer this month?"';
  }

  bool _matchesIntent(String query, List<String> keywords) {
    return keywords.any((k) => query.contains(k));
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.go('/home'),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.primaryLight, AppColors.primary]),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('V', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.aiManager, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text(l10n.poweredByVaani, style: const TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) return const _TypingIndicator();
                return _MessageBubble(message: _messages[i]);
              },
            ),
          ),
          // Suggestions
          if (_messages.length <= 2)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _suggestions(l10n).map((s) => GestureDetector(
                  onTap: () => _sendMessage(s),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.surfaceVariantDark
                          : AppColors.primaryLight.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primaryLight.withOpacity(0.4)),
                    ),
                    child: Text(s, style: const TextStyle(color: AppColors.primaryLight, fontSize: 12)),
                  ),
                )).toList(),
              ),
            ),
          const SizedBox(height: 8),
          // Input
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: context.colors.surface,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageCtrl,
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: l10n.askAnythingHint,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [AppColors.primaryLight, AppColors.primary]),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                    onPressed: () => _sendMessage(_messageCtrl.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isAI;
  final DateTime time;
  _ChatMessage({required this.text, required this.isAI}) : time = DateTime.now();
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: message.isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: message.isAI ? c.surface : AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.isAI ? 4 : 16),
            bottomRight: Radius.circular(message.isAI ? 16 : 4),
          ),
          border: message.isAI ? Border.all(color: c.surfaceBorder) : null,
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isAI ? c.textPrimary : Colors.white,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomRight: Radius.circular(16), bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: c.surfaceBorder),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final delay = i * 0.3;
              final v = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
              final scale = (v < 0.5 ? v * 2 : (1 - v) * 2).clamp(0.5, 1.0);
              return Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withOpacity(scale),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
