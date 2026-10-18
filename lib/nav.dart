import 'package:flutter/material.dart';

import 'models/entry.dart';
import 'pages/detail_page.dart';
import 'pages/entry_editor_page.dart';

Future<void> openDetail(BuildContext context, String entryId) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => DetailPage(entryId: entryId),
    ),
  );
}

Future<void> openCreate(BuildContext context, EntryKind kind) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => EntryEditorPage(kind: kind),
    ),
  );
}
