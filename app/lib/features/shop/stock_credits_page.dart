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
      builder: (context, result) {
        return SafeArea(
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
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
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
                    Text(
                      'Open the app while connected to the shop backend, then refresh.',
                    )
                  else ...[
                    _Section(
                      title: 'Current stock',
                      child: _StockList(items: result.data!.stock),
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: 'Credit given out',
                      child: _CreditList(items: result.data!.credits),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

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
  const _StockList({required this.items});
  final List<StockItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('No stock yet.');
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
              trailing: Text('₹${item.outstanding}'),
            ),
          )
          .toList(),
    );
  }
}
