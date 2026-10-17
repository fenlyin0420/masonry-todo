import 'package:flutter/material.dart';

import 'pages/create_todo_page.dart';
import 'pages/detail_page.dart';

Future<void> openDetail(BuildContext context, String todoId) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => DetailPage(todoId: todoId),
    ),
  );
}

Future<void> openCreate(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => const CreateTodoPage(),
    ),
  );
}
