import 'package:flutter/material.dart';
import 'package:kirana_gpt/core/api/api_configuration.dart';
import 'package:kirana_gpt/core/api/shop_client.dart';

/// Read-only view of the current SQLite-backed shop records.
class DatabaseViewPage extends StatefulWidget {
  const DatabaseViewPage({required this.configuration, super.key});

  final ApiConfiguration configuration;

  @override
  State<DatabaseViewPage> createState() => _DatabaseViewPageState();
}

class _DatabaseViewPageState extends State<DatabaseViewPage> {
  late final ShopApiClient _client;
  late Future<ShopSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _client = ShopApiClient(configuration: widget.configuration);
    _snapshot = _client.loadSnapshot();
  }

  void _refresh() => setState(() => _snapshot = _client.loadSnapshot());

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
                        'Database view',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh records',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Current stock and outstanding customer credit.'),
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
                    'Could not load the current shop records. Refresh to try again.',
                  )
                else ...[
                  _RecordSection(
                    title: 'Current stock',
                    child: _StockRecords(items: result.data!.stock),
                  ),
                  const SizedBox(height: 16),
                  _RecordSection(
                    title: 'Outstanding credit',
                    child: _CreditRecords(items: result.data!.credits),
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

class _RecordSection extends StatelessWidget {
  const _RecordSection({required this.title, required this.child});

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

class _StockRecords extends StatelessWidget {
  const _StockRecords({required this.items});

  final List<StockItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('No stock records yet.');
    return Column(
      children: items
          .map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.name),
              subtitle: item.lowStock ? const Text('Low stock') : null,
              trailing: Text('${item.quantity} ${item.unit}'),
            ),
          )
          .toList(),
    );
  }
}

class _CreditRecords extends StatelessWidget {
  const _CreditRecords({required this.items});

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
