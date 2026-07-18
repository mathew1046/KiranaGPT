import 'package:flutter/material.dart';
import 'package:kirana_gpt/core/api/api_configuration.dart';
import 'package:kirana_gpt/core/api/shop_client.dart';

class StockCreditsPage extends StatefulWidget {
  const StockCreditsPage({required this.configuration, super.key});

  final ApiConfiguration configuration;

  @override
  State<StockCreditsPage> createState() => _StockCreditsPageState();
}

class _StockCreditsPageState extends State<StockCreditsPage> {
  late final ShopApiClient _client;
  late Future<ShopSnapshot> _snapshot;
  final _stockName = TextEditingController();
  final _stockQuantity = TextEditingController();
  final _stockUnit = TextEditingController(text: 'piece');
  final _customerName = TextEditingController();
  final _creditAmount = TextEditingController();
  final _itemsGiven = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _client = ShopApiClient(configuration: widget.configuration);
    _snapshot = _client.loadSnapshot();
  }

  @override
  void dispose() {
    _stockName.dispose();
    _stockQuantity.dispose();
    _stockUnit.dispose();
    _customerName.dispose();
    _creditAmount.dispose();
    _itemsGiven.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _snapshot = _client.loadSnapshot());

  Future<void> _save(Future<void> Function() operation, String message) async {
    setState(() => _saving = true);
    try {
      await operation();
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on ShopApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _hasText(TextEditingController controller) =>
      controller.text.trim().isNotEmpty;

  Future<void> _addStock() async {
    if (!_hasText(_stockName) ||
        !_hasText(_stockQuantity) ||
        !_hasText(_stockUnit)) {
      _showMessage('Enter the item, quantity, and unit.');
      return;
    }
    await _save(
      () => _client.restock(
        itemName: _stockName.text.trim(),
        quantity: _stockQuantity.text.trim(),
        unit: _stockUnit.text.trim(),
        lowStockThreshold: '0',
      ),
      'Stock saved.',
    );
    _stockName.clear();
    _stockQuantity.clear();
  }

  Future<void> _saveCredit({required bool isPayment}) async {
    if (!_hasText(_customerName) || !_hasText(_creditAmount)) {
      _showMessage('Enter the customer name and amount.');
      return;
    }
    await _save(
      () => isPayment
          ? _client.recordPayment(
              customerName: _customerName.text.trim(),
              amount: _creditAmount.text.trim(),
            )
          : _client.giveCredit(
              customerName: _customerName.text.trim(),
              amount: _creditAmount.text.trim(),
              itemsGiven: _itemsGiven.text.trim(),
            ),
      isPayment ? 'Repayment saved.' : 'Credit saved.',
    );
    _creditAmount.clear();
    if (!isPayment) _itemsGiven.clear();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editStock(StockItem item) async {
    final quantity = TextEditingController(text: item.quantity);
    final unit = TextEditingController(text: item.unit);
    final threshold = TextEditingController(text: item.lowStockThreshold);
    final price = TextEditingController(text: item.price);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _input(quantity, 'Quantity', number: true),
              _input(unit, 'Unit'),
              _input(threshold, 'Low-stock alert at', number: true),
              _input(price, 'Unit price (optional)', number: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await _save(
        () => _client.updateStock(
          item: item,
          quantity: quantity.text.trim(),
          unit: unit.text.trim(),
          lowStockThreshold: threshold.text.trim(),
          price: price.text.trim(),
        ),
        'Stock updated.',
      );
    }
    quantity.dispose();
    unit.dispose();
    threshold.dispose();
    price.dispose();
  }

  Future<void> _deleteStock(StockItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${item.name}?'),
        content: const Text('This only removes the current stock item.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _save(() => _client.deleteStock(item.id), 'Stock item removed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ShopSnapshot>(
      future: _snapshot,
      builder: (context, result) => SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Stock & credits',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Add or restock',
                  child: Column(
                    children: [
                      _input(_stockName, 'Item name'),
                      _input(_stockQuantity, 'Quantity', number: true),
                      _input(_stockUnit, 'Unit'),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _addStock,
                          icon: const Icon(Icons.add),
                          label: const Text('Save stock'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Give credit or record repayment',
                  child: Column(
                    children: [
                      _input(_customerName, 'Customer name'),
                      _input(_creditAmount, 'Amount (₹)', number: true),
                      _input(_itemsGiven, 'What was given out (for credit)'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => _saveCredit(isPayment: true),
                            child: const Text('Record payment'),
                          ),
                          FilledButton(
                            onPressed: _saving
                                ? null
                                : () => _saveCredit(isPayment: false),
                            child: const Text('Give credit'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (result.connectionState != ConnectionState.done)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (result.hasError)
                  const Text(
                    'Open the app while connected to the shop backend, then refresh.',
                  )
                else ...[
                  _Section(
                    title: 'Current stock',
                    child: _StockList(
                      items: result.data!.stock,
                      onEdit: _editStock,
                      onDelete: _deleteStock,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: 'Outstanding credit',
                    child: _CreditList(items: result.data!.credits),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _input(
  TextEditingController controller,
  String label, {
  bool number = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: TextField(
    controller: controller,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  ),
);

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _StockList extends StatelessWidget {
  const _StockList({
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });
  final List<StockItem> items;
  final ValueChanged<StockItem> onEdit;
  final ValueChanged<StockItem> onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('No stock yet.');
    return Column(
      children: items
          .map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => onEdit(item),
              title: Text(item.name),
              subtitle: Text(
                item.lowStock ? 'Low stock · tap to edit' : 'Tap to edit',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${item.quantity} ${item.unit}'),
                  IconButton(
                    onPressed: () => onDelete(item),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove',
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _CreditList extends StatelessWidget {
  const _CreditList({required this.items});
  final List<CustomerCredit> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('No outstanding customer credit.');
    return Column(
      children: items
          .map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.name),
              subtitle: item.itemsGiven.isEmpty
                  ? null
                  : Text(
                      item.itemsGiven.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: Text('₹${item.outstanding}'),
            ),
          )
          .toList(),
    );
  }
}
