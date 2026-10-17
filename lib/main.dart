import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'pages/home_page.dart';
import 'store/todo_storage.dart';
import 'store/todo_store.dart';
import 'widgets/store_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final TodoStore store = TodoStore(FileTodoStorage());
  await store.load();
  runApp(MasonryTodoApp(store: store));
}

class MasonryTodoApp extends StatelessWidget {
  const MasonryTodoApp({super.key, required this.store});

  final TodoStore store;

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: MaterialApp(
        title: 'Masonry Todo',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        home: const HomePage(),
      ),
    );
  }
}
