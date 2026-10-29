import 'package:flutter/material.dart';

import 'scope.dart';

/// Feste Zeile am unteren Rand für kurze Meldungen. Ohne Meldung steht dort
/// die Version. Die Höhe ändert sich nie, damit nichts darüber verrutscht,
/// während man gerade tippen will.
class StatusLine extends StatelessWidget {
  const StatusLine({super.key});

  static const height = 40.0;
  static const _background = Color(0xFF101410);

  @override
  Widget build(BuildContext context) {
    final status = AppScope.of(context).status;
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      color: _background,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: ListenableBuilder(
            listenable: status,
            builder: (context, _) {
              final message = status.current;
              if (message == null) {
                return Center(
                  child: Text(
                    status.version.isEmpty ? '' : 'Konsum ${status.version}',
                    style: textTheme.bodySmall?.copyWith(color: Colors.white38),
                  ),
                );
              }
              return Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      message.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (message.actionLabel != null)
                    TextButton(
                      onPressed: status.runAction,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF9CD67D),
                      ),
                      child: Text(message.actionLabel!),
                    ),
                  const SizedBox(width: 8),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
