import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/data/models/user.dart';
import '../../auth/domain/auth_repository.dart';

class HomeScreen extends StatelessWidget {
  final User user;

  const HomeScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final authRepository = context.read<AuthRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flowchart Editor'),
        actions: [
          IconButton(
            tooltip: 'Exit',
            icon: const Icon(Icons.logout),
            onPressed: () => authRepository.logout(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Hello, ${user.name ?? user.login ?? user.id}!',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Гномики очень стараются'),
          ],
        ),
      ),
    );
  }
}
