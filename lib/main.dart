import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_theme.dart';
import 'pages/home_page.dart';
import 'store/todo_storage.dart';
import 'store/todo_store.dart';
import 'update/app_version.dart';
import 'update/update_controller.dart';
import 'widgets/store_scope.dart';
import 'widgets/update_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final TodoStore store = TodoStore(FileTodoStorage());
  await store.load();
  final UpdateController? updateController = Platform.isAndroid
      ? await _buildUpdateController()
      : null;
  if (updateController != null) {
    // 等首页亮起来再自动检查，提示才不会丢。
    Future.delayed(const Duration(seconds: 1), updateController.checkNow);
  }
  runApp(MasonryTodoApp(store: store, updateController: updateController));
}

Future<UpdateController?> _buildUpdateController() async {
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    final VersionParts? current = currentAppVersion(
      info.version,
      info.buildNumber,
    );
    if (current == null) return null;
    const MethodChannel channel = MethodChannel('masonry_todo.updates');
    final String? abi = await channel.invokeMethod<String>('getAbi');
    return UpdateController(
      currentVersion: current,
      abi: abi,
      channel: channel,
    );
  } catch (error) {
    debugPrint('自动更新不可用：$error');
    return null;
  }
}

class MasonryTodoApp extends StatelessWidget {
  const MasonryTodoApp({super.key, required this.store, this.updateController});

  final TodoStore store;
  final UpdateController? updateController;

  @override
  Widget build(BuildContext context) {
    final Widget app = MaterialApp(
      title: 'Masonry Todo',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: const HomePage(),
    );
    final UpdateController? update = updateController;
    return StoreScope(
      store: store,
      child: update == null ? app : UpdateScope(notifier: update, child: app),
    );
  }
}
