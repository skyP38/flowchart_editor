import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/domain/auth_repository.dart';
import '../../features/auth/domain/auth_state.dart';

/// Показывает текущего пользователя: аватар с инициалом + имя/логин.
/// На узких экранах — компактный режим (аватар + короткий логин).
/// Рендерит пустое место, если пользователь не аутентифицирован (гость).
class UserChip extends StatelessWidget {
  final bool compact;

  const UserChip({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthRepository>().state;
    final user = authState is AuthAuthenticated
        ? authState.user
        : authState is AuthLoading
        ? authState.user
        : null;

    if (user == null) return const SizedBox.shrink();

    final name = user.name?.trim() ?? '';
    final login = user.login?.trim() ?? '';
    final primary = name.isNotEmpty ? name : login;

    if (primary.isEmpty) return const SizedBox.shrink();

    final avatar = CircleAvatar(
      radius: 14,
      backgroundColor: const Color(0xFF6750A4),
      child: Text(
        primary[0].toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final tooltip = (name.isNotEmpty && login.isNotEmpty)
        ? '$name ($login)'
        : primary;

    if (compact) {
      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              avatar,
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(
                  login.isNotEmpty ? login : primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E1E1E),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E1E1E),
                  ),
                ),
                if (name.isNotEmpty && login.isNotEmpty && name != login)
                  Text(
                    login,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
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
