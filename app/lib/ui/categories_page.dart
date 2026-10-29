import 'package:flutter/material.dart';

import '../state/group_session.dart';
import 'dialogs.dart';
import 'scope.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key, required this.session});

  final GroupSession session;

  @override
  Widget build(BuildContext context) {
    AppScope.of(context);
    final group = session.group;
    return Scaffold(
      appBar: AppBar(title: const Text('Kategorien')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Neue Kategorie',
        child: const Icon(Icons.add),
        onPressed: () async {
          final name = await promptText(context, title: 'Neue Kategorie');
          if (name != null) session.apply(group.createCategory(name).changes);
        },
      ),
      body: ListView(
        children: [
          for (final c in group.categories)
            ListTile(
              title: Text(c.name),
              onTap: () async {
                final name = await promptText(
                  context,
                  title: 'Kategorie umbenennen',
                  initial: c.name,
                );
                if (name != null) {
                  session.apply(group.renameCategory(c.id, name));
                }
              },
              trailing: IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(
                    context,
                    title: '„${c.name}“ löschen?',
                    message:
                        'Artikel dieser Kategorie werden unter '
                        '„Sonstiges“ einsortiert.',
                  )) {
                    session.apply(group.deleteCategory(c.id));
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
