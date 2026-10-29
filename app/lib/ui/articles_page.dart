import 'package:flutter/material.dart';

import '../state/group_session.dart';
import 'article_page.dart';
import 'dialogs.dart';
import 'scope.dart';

/// Artikelstamm einer Gruppe.
class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key, required this.session});

  final GroupSession session;

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  String _query = '';

  void _open(String articleId) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          ArticlePage(session: widget.session, articleId: articleId),
    ),
  );

  @override
  Widget build(BuildContext context) {
    AppScope.of(context);
    final group = widget.session.group;
    final categories = {for (final c in group.categories) c.id: c.name};
    final q = _query.toLowerCase();
    final articles = group.articles
        .where((a) => a.name.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artikel'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SearchBar(
              hintText: 'Suchen',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Neuer Artikel',
        child: const Icon(Icons.add),
        onPressed: () async {
          final name = await promptText(
            context,
            title: 'Neuer Artikel',
            initial: _query,
          );
          if (name == null) return;
          final r = group.createArticle(name);
          widget.session.apply(r.changes);
          _open(r.id);
        },
      ),
      body: ListView(
        children: [
          for (final a in articles)
            ListTile(
              title: Text(a.name),
              subtitle: a.categoryId == null
                  ? null
                  : Text(categories[a.categoryId] ?? ''),
              onTap: () => _open(a.id),
            ),
        ],
      ),
    );
  }
}
