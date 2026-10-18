import 'dart:async';

import 'package:flutter/material.dart';

import '../update/update_controller.dart';
import '../update/github_release.dart';

/// 挂在首页上的透明监听器：观察 [UpdateController] 的状态变化，
/// 驱动「发现新版本」提示、下载进度弹窗与安装引导。
///
/// 只在用户主动检查或下载失败时弹 snackbar；启动时的自动检查
/// 失败保持安静，避免每次开应用都打扰。
class UpdateWatch extends StatefulWidget {
  const UpdateWatch({super.key, required this.controller, required this.child});

  final UpdateController controller;
  final Widget child;

  @override
  State<UpdateWatch> createState() => _UpdateWatchState();
}

class _UpdateWatchState extends State<UpdateWatch> {
  /// 已经弹过提示的 release tag，避免同一版本反复弹窗。
  String? _promptedTag;

  /// 下载进度弹窗是否还开着。
  bool _downloadDialogOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChange);
    // 启动时的自动检查可能在挂上之前就已结束；
    // 首帧后再弹，避免构建期 push 路由。
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _onStateChange() {
    if (!mounted) return;
    final UpdateController controller = widget.controller;
    switch (controller.state.kind) {
      case UpdateStateKind.available:
        _maybePrompt();
      case UpdateStateKind.upToDate:
        if (controller.userInitiated) {
          _snack('已是最新版本（当前 ${controller.currentVersionString}）');
        }
      case UpdateStateKind.failed:
        _closeDownloadDialog();
        if (controller.userInitiated) {
          _snack(controller.state.data.toString());
        }
      case UpdateStateKind.ready:
        _closeDownloadDialog();
        _onReady();
      case UpdateStateKind.idle:
        // 用户取消下载：只关弹窗，不提示。
        _closeDownloadDialog();
      default:
    }
  }

  void _closeDownloadDialog() {
    if (!_downloadDialogOpen) return;
    _downloadDialogOpen = false;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _maybePrompt() {
    final UpdateController controller = widget.controller;
    if (controller.state.kind != UpdateStateKind.available) return;
    final LatestRelease? release = controller.state.release;
    if (release == null) return;
    // 同一版本只自动弹一次；手动检查时不受限。
    if (_promptedTag == release.tagName && !controller.manualCheck) return;
    _promptedTag = release.tagName;
    _showAvailable(release);
  }

  void _showAvailable(LatestRelease release) {
    final ReleaseAsset? asset = widget.controller.state.asset;
    final double? sizeMb = asset?.sizeBytes != null
        ? (asset!.sizeBytes! / 1048576).toDouble()
        : null;
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('发现新版本 ${release.version ?? release.tagName}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Text(
            [
              if (sizeMb != null) 'APK 约 ${sizeMb.toStringAsFixed(1)} MB',
              '点「下载」开始更新，装好重启应用即可。',
            ].join('\n'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            // 清掉标记，之后手动检查同一版本还能再弹。
            onPressed: () {
              _promptedTag = null;
              Navigator.of(context).pop();
            },
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _download();
            },
            child: const Text('下载更新'),
          ),
        ],
      ),
    );
  }

  Future<void> _download() async {
    // 先启动下载再弹进度框，保证进度条一定能动。
    unawaited(widget.controller.startDownload());
    _downloadDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (BuildContext context, Widget? _) {
              final double progress = widget.controller.downloadProgress;
              return AlertDialog(
                title: const Text('正在下载更新'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 12),
                      Text('${(progress * 100).round()}%'),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.controller.cancelDownload();
                    },
                    child: const Text('取消'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    _downloadDialogOpen = false;
  }

  void _onReady() {
    _installFlow();
  }

  Future<void> _installFlow() async {
    final UpdateController controller = widget.controller;
    final bool canInstall = await controller.canInstall();
    if (canInstall) {
      _snack('更新包已下载，正在打开安装器');
      await controller.install();
      return;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('需要安装权限'),
        content: const SizedBox(
          width: double.maxFinite,
          child: Text(
            '系统要求先允许拾记安装未知应用。'
            '在设置页开启后回来点「重试」。',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          TextButton(
            // 用户回来点重试，重新走安装流程。
            onPressed: () {
              Navigator.of(context).pop();
              _installFlow();
            },
            child: const Text('重试'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(controller.openInstallSettings());
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}
