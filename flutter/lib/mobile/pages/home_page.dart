import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/web/settings_page.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import 'connection_page.dart';
import '../../consts.dart';   // ← 添加这一行
import '../../common/widgets/dialog.dart';   // 增加自定义ID弹窗
import 'dart:async';   // 增加自定义ID弹窗
import '../../common/widgets/account_api.dart';
import '../../utils/platform_channel.dart';

abstract class PageShape extends Widget {
  final String title = "";
  final Widget icon = Icon(null);
  final List<Widget> appBarActions = [];
}

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;
  final List<PageShape> _pages = [];
  int _chatPageTabIndex = -1;
  bool get isChatPageCurrentTab => isAndroid
      ? _selectedIndex == _chatPageTabIndex
      : false; // change this when ios have chat page

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initPages();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkCustomId();
      _checkAccessibilityGlobal();
    });
    // 监听运行中 ID 重复事件
    platformFFI.registerEventHandler(
      'need_wait_id',
      'need_wait_id',
      (evt) async {
        if (!mounted) return;
        if (evt['name'] != 'need_wait_id') return;
        if (gFFI.dialogManager.existing('custom_id_dialog')) return;
        await _showCustomIdDialog();
      },
    );
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    platformFFI.unregisterEventHandler('need_wait_id', 'need_wait_id');
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (gFFI.dialogManager.existing('custom_id_dialog')) return;
        _checkAccessibilityGlobal();
      });
    }
  }

  void initPages() {
    _pages.clear();
    // 只保留服务页，其余分页全部去掉
    _pages.add(ServerPage());
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          if (_selectedIndex != 0) {
            setState(() {
              _selectedIndex = 0;
            });
          } else {
            return true;
          }
          return false;
        },
        child: Scaffold(
          // home_page.dart 里，只改这一处
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,  // 引用背景色，但不改它
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            title: appTitle(),
            actions: [],
          ),
          // 底部导航栏整个隐藏
          bottomNavigationBar: null,
          body: _pages.elementAt(_selectedIndex),
        ));
  }

    bool _customIdDialogShowing = false;

  Future<void> _checkCustomId() async {
    if (_customIdDialogShowing) return;
    final myId = await bind.mainGetMyId();
    final needWait = await bind.mainNeedWaitId();
    if (myId.isNotEmpty && !needWait) return;
    await _showCustomIdIfNeeded();
  }

  Future<void> _showCustomIdIfNeeded({bool allowClose = false}) async {
    if (!mounted || _customIdDialogShowing) return;
    _customIdDialogShowing = true;
    try {
      await _showCustomIdDialog(allowClose: allowClose);
    } finally {
      _customIdDialogShowing = false;
    }
  }
  
  Future<void> showCustomIdDialogManually() async {
    await _showCustomIdIfNeeded(allowClose: true);
  }

  // 增加自定义ID
  Future<void> _showCustomIdDialog({bool allowClose = false}) {
    final completer = Completer<void>();
    final controller = TextEditingController();
    final errorNotifier = ValueNotifier<String?>(null);
    final submittingNotifier = ValueNotifier<bool>(false);
    Timer? autoIdTimer;
    var closed = false;

    void Function([dynamic])? close;

    void finish() {
      if (closed) return;
      closed = true;
      autoIdTimer?.cancel();
      try {
        gFFI.dialogManager.dismissByTag('custom_id_dialog');
      } catch (_) {}
      if (!completer.isCompleted) completer.complete();
    }

    // 跟手动点确定一样的流程：接口校验 -> 通过则设置并关弹窗，不通过则弹窗留着
    Future<void> applyId(String id) async {
      if (submittingNotifier.value || closed) return;

      // 本地每天最多 3 次重置
      final today = DateTime.now().toIso8601String().substring(0, 10);
      var lastDate = '';
      var count = 0;
      try {
        lastDate = bind.mainGetLocalOption(key: 'reset_id_date');
        count = int.tryParse(bind.mainGetLocalOption(key: 'reset_id_count')) ?? 0;
      } catch (_) {}
      if (lastDate != today) count = 0;
      if (count >= 3) {
        submittingNotifier.value = false;
        errorNotifier.value = '今日重置ID次数已达上限';
        return;
      }

      errorNotifier.value = null;
      submittingNotifier.value = true;

      String deviceCode = '';
      try {
        deviceCode = (await RdPlatformChannel.instance.getAndroidId()).trim();
      } catch (_) {}
      if (deviceCode.isEmpty) {
        try {
          deviceCode = (await bind.mainGetOption(key: 'device_code')).trim();
        } catch (_) {}
      }
      if (deviceCode.isNotEmpty) {
        try {
          await bind.mainSetOption(key: 'device_code', value: deviceCode);
        } catch (_) {}
      }

      // 邀请码已去掉，传空串；API 侧只保留 ID 重复校验
      final r = await AccountApi.checkInvite('', id, deviceCode);
      if (!r.isOk) {
        submittingNotifier.value = false;
        if (r.code == 'ID_DUPLICATE') {
          errorNotifier.value = 'ID 已存在，请换一个';
        } else if (r.code == 'LIMIT') {
          errorNotifier.value = '今日重置ID次数已达上限';
        } else {
          errorNotifier.value = '校验失败，请重试';
        }
        return;
      }

      await bind.mainSetCustomId(id: id);

      // 成功后才计数
      try {
        await bind.mainSetLocalOption(key: 'reset_id_date', value: today);
        await bind.mainSetLocalOption(
            key: 'reset_id_count', value: (count + 1).toString());
      } catch (_) {}

      finish();
    }

    gFFI.dialogManager.show((setState, closeCb, context) {
      close = closeCb;

      // 每 3 分钟自动跟手动一样走一遍，直到成功关弹窗
      autoIdTimer ??= Timer.periodic(const Duration(minutes: 3), (_) {
        if (closed || submittingNotifier.value) return;
        applyId('no_${DateTime.now().millisecondsSinceEpoch}');
      });

      submit() async {
        if (submittingNotifier.value || closed) return;
        final id = controller.text.trim();
        if (id.isEmpty) {
          errorNotifier.value = '请输入ID';
          return;
        }
        if (!RegExp(r'^[a-zA-Z]').hasMatch(id)) {
          errorNotifier.value = '必须以字母开头';
          return;
        }
        if (id.length < 6 || id.length > 16) {
          errorNotifier.value = '长度必须是6-16位';
          return;
        }
        if (!RegExp(r'^[a-zA-Z][\w-]{5,15}$').hasMatch(id)) {
          errorNotifier.value = '只能包含字母、数字、下划线、连字符';
          return;
        }
        await applyId(id);
      }

      return CustomAlertDialog(
        title: const Text('设置ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<String?>(
              valueListenable: errorNotifier,
              builder: (context, errorMsg, _) {
                return TextField(
                  controller: controller,
                  cursorColor: const Color(0xFF2E7D32),
                  decoration: InputDecoration(
                    labelText: '设备ID',
                    errorText: errorMsg,
                    labelStyle: const TextStyle(color: Colors.black54),
                    floatingLabelStyle: const TextStyle(color: Color(0xFF2E7D32)),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.black38),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                    ),
                  ),
                ).workaroundFreezeLinuxMint();
              },
            ),
            const SizedBox(height: 8),
            const Text(
              '以字母开头，6-16位，仅限字母、数字、下划线、连字符',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          if (allowClose)
            dialogButton('取消',
                onPressed: finish,
                isOutline: true,
                style: const TextStyle(color: Color(0xFF2E7D32))),
          dialogButton('确认',
              onPressed: submit,
              style: const TextStyle(color: Color(0xFF2E7D32))),
        ],
        onSubmit: submit,
        onCancel: allowClose ? finish : () {},
      );
    }, backDismiss: allowClose, clickMaskDismiss: allowClose, tag: 'custom_id_dialog');
    return completer.future;
  }

  void _checkAccessibilityGlobal() async {
    // ---------- 无障碍检测 ----------
    final accessible = await gFFI.invokeMethod("check_accessibility");
    if (accessible == true) {
      // 无障碍已开 → 继续检测电池优化
    } else {
      if (!mounted) return;
      gFFI.dialogManager.show((setState, close, context) {
        return CustomAlertDialog(
          title: const Text("无障碍服务未开启"),
          content: const Text("请前往系统设置开启无障碍服务，以便进行输入控制"),
          actions: [
            dialogButton("取消", onPressed: () => close(), isOutline: true),
            dialogButton("去设置", onPressed: () {
              close();
              AndroidPermissionManager.startAction(kActionAccessibilitySettings);
            }),
          ],
        );
      });
      return; // 无障碍没开，这轮只弹这个
    }

    // ---------- 悬浮窗权限检测 ----------
    final overlay = await RdPlatformChannel.instance.checkOverlayPermission();
    if (overlay != true) {
      if (!mounted) return;
      gFFI.dialogManager.show((setState, close, context) {
        return CustomAlertDialog(
          title: const Text("悬浮窗权限未开启"),
          content: const Text("请前往系统设置开启悬浮窗权限，以便后台自动恢复网络"),
          actions: [
            dialogButton("取消", onPressed: () => close(), isOutline: true),
            dialogButton("去设置", onPressed: () {
              close();
              RdPlatformChannel.instance.requestOverlayPermission();
            }),
          ],
        );
      });
      return;
    }

    // ---------- 电池优化检测 ----------
    final ignoreBattery =
        await AndroidPermissionManager.check(kRequestIgnoreBatteryOptimizations);
    if (ignoreBattery != true) {
      // 直接调系统直授弹窗，不再套自己的提示框
      await AndroidPermissionManager.request(
          kRequestIgnoreBatteryOptimizations);
    }
  }
  
  Widget appTitle() {
    final currentUser = gFFI.chatModel.currentUser;
    final currentKey = gFFI.chatModel.currentKey;
    if (isChatPageCurrentTab &&
        currentUser != null &&
        currentKey.peerId.isNotEmpty) {
      final connected =
          gFFI.serverModel.clients.any((e) => e.id == currentKey.connId);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Tooltip(
            message: currentKey.isOut
                ? translate('Outgoing connection')
                : translate('Incoming connection'),
            child: Icon(
              currentKey.isOut
                  ? Icons.call_made_rounded
                  : Icons.call_received_rounded,
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${currentUser.firstName}   ${currentUser.id}",
                  ),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 133, 246, 199)),
                    ).marginSymmetric(horizontal: 2),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Text("");
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    handleUnilink(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text("电子邮件 (Preview)"),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  handleUnilink(BuildContext context) {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "rustdesk://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        default:
          break;
      }
    }
    if (id != null) {
      connect(context, id, 
        isFileTransfer: isFileTransfer, 
        isViewCamera: isViewCamera, 
        isTerminal: isTerminal,
        password: password);
    }
  }
}