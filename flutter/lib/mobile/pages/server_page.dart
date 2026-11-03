import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/dialog.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import 'home_page.dart';
import '../../common/widgets/account_api.dart';

class ServerPage extends StatefulWidget implements PageShape {
  @override
  final title = ""; // 底部导航只保留图标，删除文字

  @override
  final icon = const Icon(Icons.mobile_screen_share);

  @override
  final appBarActions = []; // 移除右上角三点密码设置下拉菜单

  ServerPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ServerPageState();
}

class _DropDownAction extends StatelessWidget {
  _DropDownAction();

  // should only have one action
  final actions = [
    PopupMenuButton<String>(
        tooltip: "",
        icon: const Icon(Icons.more_vert),
        itemBuilder: (context) {
          listTile(String text, bool checked) {
            return ListTile(
                title: Text(translate(text)),
                trailing: Icon(
                  Icons.check,
                  color: checked ? null : Colors.transparent,
                ));
          }

          final approveMode = gFFI.serverModel.approveMode;
          final verificationMethod = gFFI.serverModel.verificationMethod;
          final showPasswordOption = approveMode != 'click';
          final isApproveModeFixed = isOptionFixed(kOptionApproveMode);
          final isNumericOneTimePasswordFixed =
              isOptionFixed(kOptionAllowNumericOneTimePassword);
          final isAllowNumericOneTimePassword =
              gFFI.serverModel.allowNumericOneTimePassword;
          return [
            if (!isChangeIdDisabled())
              PopupMenuItem(
                enabled: gFFI.serverModel.connectStatus > 0,
                value: "changeID",
                child: Text(translate("Change ID")),
              ),
            if (!isChangeIdDisabled()) const PopupMenuDivider(),
            PopupMenuItem(
              value: 'AcceptSessionsViaPassword',
              child: listTile(
                  'Accept sessions via password', approveMode == 'password'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: 'AcceptSessionsViaClick',
              child:
                  listTile('Accept sessions via click', approveMode == 'click'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: "AcceptSessionsViaBoth",
              child: listTile("Accept sessions via both",
                  approveMode != 'password' && approveMode != 'click'),
              enabled: !isApproveModeFixed,
            ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption &&
                verificationMethod != kUseTemporaryPassword &&
                !isChangePermanentPasswordDisabled())
              PopupMenuItem(
                value: "setPermanentPassword",
                child: Text(translate("Set permanent password")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "setTemporaryPasswordLength",
                child: Text(translate("One-time password length")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "allowNumericOneTimePassword",
                child: listTile(translate("Numeric one-time password"),
                    isAllowNumericOneTimePassword),
                enabled: !isNumericOneTimePasswordFixed,
              ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseTemporaryPassword,
                child: listTile('Use one-time password',
                    verificationMethod == kUseTemporaryPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUsePermanentPassword,
                child: listTile('Use permanent password',
                    verificationMethod == kUsePermanentPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseBothPasswords,
                child: listTile(
                    'Use both passwords',
                    verificationMethod != kUseTemporaryPassword &&
                        verificationMethod != kUsePermanentPassword),
              ),
          ];
        },
        onSelected: (value) async {
          if (value == "changeID") {
            changeIdDialog();
          } else if (value == "setPermanentPassword") {
            setPasswordDialog();
          } else if (value == "setTemporaryPasswordLength") {
            setTemporaryPasswordLengthDialog(gFFI.dialogManager);
          } else if (value == "allowNumericOneTimePassword") {
            gFFI.serverModel.switchAllowNumericOneTimePassword();
            gFFI.serverModel.updatePasswordModel();
          } else if (value == kUsePermanentPassword ||
              value == kUseTemporaryPassword ||
              value == kUseBothPasswords) {
            callback() {
              bind.mainSetOption(key: kOptionVerificationMethod, value: value);
              gFFI.serverModel.updatePasswordModel();
            }

            if (value == kUsePermanentPassword &&
                (await bind.mainGetPermanentPassword()).isEmpty) {
              if (isChangePermanentPasswordDisabled()) {
                callback();
                return;
              }
              setPasswordDialog(notEmptyCallback: callback);
            } else {
              callback();
            }
          } else if (value.startsWith("AcceptSessionsVia")) {
            value = value.substring("AcceptSessionsVia".length);
            if (value == "Password") {
              gFFI.serverModel.setApproveMode('password');
            } else if (value == "Click") {
              gFFI.serverModel.setApproveMode('click');
            } else {
              gFFI.serverModel.setApproveMode(defaultOptionApproveMode);
            }
          }
        })
  ];

  @override
  Widget build(BuildContext context) {
    return actions[0];
  }
}

class _ServerPageState extends State<ServerPage> {
  Timer? _updateTimer;
  int _hostExpire = 0;
  bool _ledgerLoaded = false;

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 3), () async {
      await gFFI.serverModel.fetchID();
    });
    gFFI.serverModel.checkAndroidPermission();
    _loadLedgerInfo();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLedgerInfo() async {
    final id = await bind.mainGetMyId();
    if (id.isEmpty) return;
    final info = await AccountApi.deviceInfo(id);
    if (mounted) {
      setState(() {
        _hostExpire = info?.hostExpire ?? 0;
        _ledgerLoaded = true;
      });
    }
  }

  Widget _buildHostActivateSection(BuildContext context) {
    String hostText;
    bool red = false;
    if (!_ledgerLoaded) {
      hostText = '托管：加载中';
    } else if (_hostExpire <= 0) {
      hostText = '托管：未激活';
    } else {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final diff = _hostExpire - now;
      if (diff <= 0) {
        hostText = '托管：已到期';
        red = true;
      } else {
        hostText = '托管：${(diff / 86400).ceil()}天';
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            minimumSize: const Size(0, 32),
            textStyle: const TextStyle(fontSize: 13),
          ),
          icon: const Icon(Icons.vpn_key, size: 18),
          onPressed: () async {
            if (await bind.mainIsIdRegistered()) {
              // 分支1：已注册 → 弹激活输入框
              _showHostActivateDialog(context);
            } else {
              // 分支2：未注册 → 强制注册/改ID，绝不弹输入框
              if (!gFFI.serverModel.isStart) {
                await gFFI.serverModel.startService();
              } else {
                await bind.mainStartService();
              }
              showToast('正在注册 ID，注册成功后再点激活');
            }
          },
          label: const Text("托管激活"),
        ),
        const SizedBox(height: 6),
        Text(
          hostText,
          style: TextStyle(
            fontSize: 12,
            color: red
                ? Colors.red
                : Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  void _showHostActivateDialog(BuildContext context) {
    final codeController = TextEditingController();
    var isInProgress = false;
    String? errorMsg;
    gFFI.dialogManager.show((setState, close, context) {
      submit() async {
        final code = codeController.text.trim();
        if (code.isEmpty) {
          setState(() => errorMsg = '请输入激活码');
          return;
        }
        if (!await bind.mainIsIdRegistered()) {
          setState(() => errorMsg = 'ID 未注册或已变更，请先完成注册');
          return;
        }
        setState(() {
          isInProgress = true;
          errorMsg = null;
        });
        final id = await bind.mainGetMyId();
        final r = await AccountApi.activate(code, 'host', id, '__device__');
        setState(() => isInProgress = false);
        if (r.isOk) {
          close();
          showToast('激活成功');
          _loadLedgerInfo();
          return;
        }
        setState(() => errorMsg = r.msg);
      }

      return CustomAlertDialog(
        title: const Text('托管激活'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              autofocus: true,
              cursorColor: const Color(0xFF2E7D32),
              decoration: InputDecoration(
                labelText: '激活码',
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
            ).workaroundFreezeLinuxMint(),
            if (isInProgress) const LinearProgressIndicator(),
          ],
        ),
        actions: [
          dialogButton('取消',
              onPressed: close,
              isOutline: true,
              style: const TextStyle(color: Color(0xFF2E7D32))),
          dialogButton('确认',
              onPressed: submit,
              style: const TextStyle(color: Color(0xFF2E7D32))),
        ],
        onSubmit: submit,
        onCancel: close,
      );
    });
  }

  void _showAboutDialog() {
    gFFI.dialogManager.show((setState, close, context) {
      const commonStyle = TextStyle(fontSize: 14, height: 1.6, color: Colors.black);
      return CustomAlertDialog(
        title: const Text('关于'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              SelectableText(
                '请不要对外提供任何个人信息和密码，重要密码安全界面会导致黑不显示，多次按回退即可退出，重要密码请在自己设备登录使用。',
                style: commonStyle,
              ),
              SizedBox(height: 12),
              SelectableText(
                '本软件基于 RustDesk 开源项目修改，遵循 AGPL-3.0 许可证。',
                style: commonStyle,
              ),
              SizedBox(height: 8),
              SelectableText(
                '源代码地址：https://codeberg.org/newpower/newpower.git',
                style: commonStyle,
              ),
              SizedBox(height: 8),
              SelectableText(
                'AGPL-3.0 许可证全文：https://www.gnu.org/licenses/agpl-3.0.html',
                style: commonStyle,
              ),
            ],
          ),
        ),
        actions: [
          dialogButton('OK', onPressed: close),
        ],
        onSubmit: close,
        onCancel: close,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    checkService();
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
            builder: (context, serverModel, child) => SingleChildScrollView(
                  controller: gFFI.serverModel.controller,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        buildPresetPasswordWarningMobile(),
                        gFFI.serverModel.isStart
                            ? ServerInfo()
                            : ServiceNotRunningNotification(),
                        const PermissionChecker(),
                        _buildHostActivateSection(context),
                        const SizedBox(height: 12),
                        SizedBox.fromSize(size: const Size(0, 15.0)),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20.0),
                          child: Text(
                            bind.mainGetOptionSync(key: 'local-ip-addr'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        GestureDetector(
                          onTap: _showAboutDialog,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 20.0),
                            child: Text(
                              '关于',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )));
  }
}

void checkService() async {
  gFFI.invokeMethod("check_service");
  // for Android 10/11, request MANAGE_EXTERNAL_STORAGE permission from system setting page
  if (AndroidPermissionManager.isWaitingFile() && !gFFI.serverModel.fileOk) {
    AndroidPermissionManager.complete(kManageExternalStorage,
        await AndroidPermissionManager.check(kManageExternalStorage));
    debugPrint("file permission finished");
  }
}

class ServiceNotRunningNotification extends StatelessWidget {
  ServiceNotRunningNotification({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),  // 深绿
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                minimumSize: const Size(0, 32),
                textStyle: const TextStyle(fontSize: 13),
              ),
              icon: const Icon(Icons.play_arrow, size: 18),
              onPressed: () {
                serverModel.toggleService();
              },
              label: Text("连接"))
        ],
      ),
    );
  }
}

class ScamWarningDialog extends StatefulWidget {
  final ServerModel serverModel;

  ScamWarningDialog({required this.serverModel});

  @override
  ScamWarningDialogState createState() => ScamWarningDialogState();
}

class ScamWarningDialogState extends State<ScamWarningDialog> {
  int _countdown = bind.isCustomClient() ? 0 : 12;
  bool show_warning = false;
  late Timer _timer;
  late ServerModel _serverModel;

  @override
  void initState() {
    super.initState();
    _serverModel = widget.serverModel;
    startCountdown();
  }

  void startCountdown() {
    const oneSecond = Duration(seconds: 1);
    _timer = Timer.periodic(oneSecond, (timer) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isButtonLocked = _countdown > 0;

    return AlertDialog(
      content: ClipRRect(
        borderRadius: BorderRadius.circular(20.0),
        child: SingleChildScrollView(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xffe242bc),
                  Color(0xfff4727c),
                ],
              ),
            ),
            padding: EdgeInsets.all(25.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_sharp,
                      color: Colors.white,
                    ),
                    SizedBox(width: 10),
                    Text(
                      translate("Warning"),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20.0,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Center(
                  child: Image.asset(
                    'assets/scam.png',
                    width: 180,
                  ),
                ),
                SizedBox(height: 18),
                Text(
                  translate("scam_title"),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22.0,
                  ),
                ),
                SizedBox(height: 18),
                Text(
                  "${translate("scam_text1")}\n\n${translate("scam_text2")}\n",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                  ),
                ),
                Row(
                  children: <Widget>[
                    Checkbox(
                      value: show_warning,
                      onChanged: (value) {
                        setState(() {
                          show_warning = value!;
                        });
                      },
                    ),
                    Text(
                      translate("Don't show again"),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15.0,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      constraints: BoxConstraints(maxWidth: 150),
                      child: ElevatedButton(
                        onPressed: isButtonLocked
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                _serverModel.toggleService();
                                if (show_warning) {
                                  bind.mainSetLocalOption(
                                      key: "show-scam-warning", value: "N");
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: Text(
                          isButtonLocked
                              ? "${translate("I Agree")} (${_countdown}s)"
                              : translate("I Agree"),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    SizedBox(width: 15),
                    Container(
                      constraints: BoxConstraints(maxWidth: 150),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: Text(
                          translate("Decline"),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      contentPadding: EdgeInsets.all(0.0),
    );
  }
}

class ServerInfo extends StatelessWidget {
  final model = gFFI.serverModel;
  final emptyController = TextEditingController(text: "-");

  ServerInfo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);

    const Color colorPositive = Colors.green;
    const Color colorNegative = Colors.red;
    const double iconMarginRight = 10;
    const double iconSize = 20;
    const TextStyle textStyleHeading = TextStyle(
        fontSize: 16.0, fontWeight: FontWeight.bold, color: Colors.grey);
    const TextStyle textStyleValue =
        TextStyle(fontSize: 22.0, fontWeight: FontWeight.normal);

    void copyToClipboard(String value) {
      Clipboard.setData(ClipboardData(text: value));
    }

    Widget ConnectionStateNotification() {
      if (serverModel.connectStatus == -1) {
        return Row(children: [
          const Icon(Icons.warning_amber_sharp,
                  color: colorNegative, size: iconSize)
              .marginOnly(right: iconMarginRight),
          Expanded(child: Text(translate('not_ready_status')))
        ]);
      } else if (serverModel.connectStatus == 0) {
        return Row(children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
              .marginOnly(left: 4, right: iconMarginRight),
          Expanded(child: Text(translate('connecting_status')))
        ]);
      } else {
        return Row(children: [
          const Icon(Icons.check, color: colorPositive, size: iconSize)
              .marginOnly(right: iconMarginRight),
          Expanded(child: Text(translate('Ready')))
        ]);
      }
    }

    final showOneTime = serverModel.approveMode != 'click' &&
        serverModel.verificationMethod != kUsePermanentPassword;
    // 状态图标（只留图标，去掉文字）
    Widget ConnectionStateIcon() {
      if (serverModel.connectStatus == -1) {
        return const Icon(Icons.circle, color: colorNegative, size: iconSize);  // 红点
      } else if (serverModel.connectStatus == 0) {
        return const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: Colors.orange));            // 橙黄转圈
      } else {
        return const Icon(Icons.circle, color: colorPositive, size: iconSize); // 绿点
      }
    }

    return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
                padding: const EdgeInsets.only(top: 60.0),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ConnectionStateIcon(),
                      const SizedBox(width: iconMarginRight),
                      Text(
                        trimID(model.serverId.value.text),
                        style: textStyleValue,
                      ),
                      TextButton(
                      style: TextButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 0),
                      ),
                      onPressed: () {
                        copyToClipboard(trimID(model.serverId.value.text));
                      },
                      child: const Text("复制",
                          style: TextStyle(fontSize: 15, color: Color(0xFF2E7D32))))
                    ])),
          ],
        ));
  }
}

class PermissionChecker extends StatefulWidget {
  const PermissionChecker({Key? key}) : super(key: key);

  @override
  State<PermissionChecker> createState() => _PermissionCheckerState();
}

class _PermissionCheckerState extends State<PermissionChecker> {
  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          serverModel.isStart
              ? ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        minimumSize: const Size(0, 32),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      icon: const Icon(Icons.stop, size: 18),
                      onPressed: serverModel.toggleService,
                      label: Text("断开"))
              : SizedBox.shrink(),
        ],
      ),
    );
  }
}

class PermissionRow extends StatelessWidget {
  const PermissionRow(this.name, this.isOk, this.onPressed, {Key? key})
      : super(key: key);

  final String name;
  final bool isOk;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.all(0),
        title: Text(name),
        value: isOk,
        onChanged: (bool value) {
          onPressed();
        });
  }
}

class ConnectionManager extends StatelessWidget {
  const ConnectionManager({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    return Column(
        children: serverModel.clients
            .map((client) => PaddingCard(
                title: translate(
                    client.isFileTransfer ? "Transfer file" : "Share screen"),
                titleIcon: client.isFileTransfer
                    ? Icon(Icons.folder_outlined)
                    : Icon(Icons.mobile_screen_share),
                child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: ClientInfo(client)),
                      Expanded(
                          flex: -1,
                          child: client.isFileTransfer || !client.authorized
                              ? const SizedBox.shrink()
                              : IconButton(
                                  onPressed: () {
                                    gFFI.chatModel.changeCurrentKey(
                                        MessageKey(client.peerId, client.id));
                                    final bar = navigationBarKey.currentWidget;
                                    if (bar != null) {
                                      bar as BottomNavigationBar;
                                      bar.onTap!(1);
                                    }
                                  },
                                  icon: unreadTopRightBuilder(
                                      client.unreadChatMessageCount)))
                    ],
                  ),
                  client.authorized
                      ? const SizedBox.shrink()
                      : Text(
                          translate("android_new_connection_tip"),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ).marginOnly(bottom: 5),
                  client.authorized
                      ? _buildDisconnectButton(client)
                      : _buildNewConnectionHint(serverModel, client),
                  if (client.incomingVoiceCall && !client.inVoiceCall)
                    ..._buildNewVoiceCallHint(context, serverModel, client),
                ])))
            .toList());
  }

  Widget _buildDisconnectButton(Client client) {
    final disconnectButton = ElevatedButton.icon(
      style: ButtonStyle(backgroundColor: MaterialStatePropertyAll(Colors.red)),
      icon: const Icon(Icons.close),
      onPressed: () {
        bind.cmCloseConnection(connId: client.id);
        gFFI.invokeMethod("cancel_notification", client.id);
      },
      label: Text(translate("Disconnect")),
    );
    final buttons = [disconnectButton];
    if (client.inVoiceCall) {
      buttons.insert(
        0,
        ElevatedButton.icon(
          style: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.red)),
          icon: const Icon(Icons.phone),
          label: Text(translate("Stop")),
          onPressed: () {
            bind.cmCloseVoiceCall(id: client.id);
            gFFI.invokeMethod("cancel_notification", client.id);
          },
        ),
      );
    }

    if (buttons.length == 1) {
      return Container(
        alignment: Alignment.centerRight,
        child: disconnectButton,
      );
    } else {
      return Row(
        children: buttons,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
      );
    }
  }

  Widget _buildNewConnectionHint(ServerModel serverModel, Client client) {
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      TextButton(
          child: Text(translate("Dismiss")),
          onPressed: () {
            serverModel.sendLoginResponse(client, false);
          }).marginOnly(right: 15),
      if (serverModel.approveMode != 'password')
        ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: Text(translate("Accept")),
            onPressed: () {
              serverModel.sendLoginResponse(client, true);
            }),
    ]);
  }

  List<Widget> _buildNewVoiceCallHint(
      BuildContext context, ServerModel serverModel, Client client) {
    return [
      Text(
        translate("android_new_voice_call_tip"),
        style: Theme.of(context).textTheme.bodyMedium,
      ).marginOnly(bottom: 5),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(
            child: Text(translate("Dismiss")),
            onPressed: () {
              serverModel.handleVoiceCall(client, false);
            }).marginOnly(right: 15),
        if (serverModel.approveMode != 'password')
          ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: Text(translate("Accept")),
              onPressed: () {
                serverModel.handleVoiceCall(client, true);
              }),
      ])
    ];
  }
}

class PaddingCard extends StatelessWidget {
  const PaddingCard({Key? key, required this.child, this.title, this.titleIcon})
      : super(key: key);

  final String? title;
  final Icon? titleIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final children = [child];
    if (title != null) {
      children.insert(
          0,
          Padding(
              padding: const EdgeInsets.fromLTRB(0, 5, 0, 8),
              child: Row(
                children: [
                  titleIcon?.marginOnly(right: 10) ?? const SizedBox.shrink(),
                  Expanded(
                    child: Text(title!,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.merge(TextStyle(fontWeight: FontWeight.bold))),
                  )
                ],
              )));
    }
    return SizedBox(
        width: double.maxFinite,
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          margin: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 0),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 15.0, horizontal: 20.0),
            child: Column(
              children: children,
            ),
          ),
        ));
  }
}

class ClientInfo extends StatelessWidget {
  final Client client;
  ClientInfo(this.client);

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Row(
            children: [
              Expanded(
                  flex: -1,
                  child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildAvatar(context))),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(client.name, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Text(client.peerId, style: const TextStyle(fontSize: 10))
                  ]))
            ],
          ),
        ]));
  }

  Widget _buildAvatar(BuildContext context) {
    final fallback = CircleAvatar(
      backgroundColor: str2color(
          client.name,
          Theme.of(context).brightness == Brightness.light ? 255 : 150),
      child: Text(client.name.isNotEmpty ? client.name[0] : '?'),
    );
    return buildAvatarWidget(
      avatar: client.avatar,
      size: 40,
      fallback: fallback,
    )!;
  }
}

void androidChannelInit() {
  gFFI.setMethodCallHandler((method, arguments) {
    debugPrint("flutter got android msg,$method,$arguments");
    try {
      switch (method) {
        case "start_capture":
          {
            gFFI.dialogManager.dismissAll();
            gFFI.serverModel.updateClientState();
            break;
          }
        case "on_state_changed":
          {
            var name = arguments["name"] as String;
            var value = arguments["value"] as String == "true";
            debugPrint("from jvm:on_state_changed,$name:$value");
            gFFI.serverModel.changeStatue(name, value);
            break;
          }
        case "on_android_permission_result":
          {
            var type = arguments["type"] as String;
            var result = arguments["result"] as bool;
            AndroidPermissionManager.complete(type, result);
            break;
          }
        case "on_media_projection_canceled":
          {
            gFFI.serverModel.stopService();
            break;
          }
        case "msgbox":
          {
            var type = arguments["type"] as String;
            var title = arguments["title"] as String;
            var text = arguments["text"] as String;
            var link = (arguments["link"] ?? '') as String;
            msgBox(gFFI.sessionId, type, title, text, link, gFFI.dialogManager);
            break;
          }
        case "stop_service":
          {
            print(
                "stop_service by kotlin, isStart:${gFFI.serverModel.isStart}");
            if (gFFI.serverModel.isStart) {
              gFFI.serverModel.stopService();
            }
            break;
          }
      }
    } catch (e) {
      debugPrintStack(label: "MethodCallHandler err:$e");
    }
    return "";
  });
}

void showScamWarning(BuildContext context, ServerModel serverModel) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return ScamWarningDialog(serverModel: serverModel);
    },
  );
}