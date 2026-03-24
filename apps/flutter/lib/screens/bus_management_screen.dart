import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bus.dart';
import '../providers/data_provider.dart';

class BusManagementScreen extends ConsumerStatefulWidget {
  const BusManagementScreen({super.key});

  @override
  ConsumerState<BusManagementScreen> createState() => _BusManagementScreenState();
}

class _BusManagementScreenState extends ConsumerState<BusManagementScreen> {
  List<Bus> _registeredBuses = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchBuses();
  }

  Future<void> _fetchBuses() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final buses = await api.fetchBuses();
      if (mounted) {
        setState(() {
          _registeredBuses = buses;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAddEditDialog({Bus? existing}) {
    final macController = TextEditingController(text: existing?.busMac ?? existing?.macAddress ?? '');
    final nameController = TextEditingController(text: existing?.busName ?? '');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(existing != null ? 'Edit Bus' : 'Register New Bus'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: macController,
              decoration: InputDecoration(
                labelText: 'MAC Address',
                hintText: 'e.g., AA:BB:CC:11:22:33',
                prefixIcon: const Icon(Icons.fingerprint),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              enabled: existing == null,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Bus Name',
                hintText: 'e.g., Orange Bus 01',
                prefixIcon: const Icon(Icons.badge),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (macController.text.isEmpty || nameController.text.isEmpty) return;
              
              final api = ref.read(apiServiceProvider);
              bool success = false;
              
              if (existing != null) {
                success = await api.updateBus(macController.text, nameController.text);
              } else {
                success = await api.createBus(macController.text, nameController.text);
              }

              if (success && ctx.mounted) {
                Navigator.pop(ctx);
                _fetchBuses();
                ref.read(dataProvider.notifier).refreshBuses();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Bus bus) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bus'),
        content: Text('Are you sure you want to remove ${bus.busName}?\nThis action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final api = ref.read(apiServiceProvider);
              final success = await api.deleteBus(bus.busMac);
              if (success && ctx.mounted) {
                Navigator.pop(ctx);
                _fetchBuses();
                ref.read(dataProvider.notifier).refreshBuses();
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredBuses = _registeredBuses.where((b) => 
      b.busName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
      b.busMac.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bus Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchBuses,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        label: const Text('Add Bus'),
        icon: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search by name or MAC...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filteredBuses.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: filteredBuses.length,
                        padding: const EdgeInsets.only(bottom: 80),
                        itemBuilder: (context, index) {
                          final bus = filteredBuses[index];
                          return _buildBusTile(bus);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusTile(Bus bus) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
          child: Icon(Icons.directions_bus, color: theme.colorScheme.primary),
        ),
        title: Text(bus.busName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MAC: ${bus.busMac}', style: theme.textTheme.bodySmall),
            if (bus.routeId != null)
              Text('Route ID: ${bus.routeId}', style: TextStyle(color: theme.colorScheme.secondary, fontSize: 12)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showAddEditDialog(existing: bus),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _confirmDelete(bus),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bus_alert_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'No buses registered' : 'No matches found',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          if (_searchQuery.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _searchQuery = ''),
              child: const Text('Clear Search'),
            ),
        ],
      ),
    );
  }
}
