import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/account_api.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/models/platform_model.dart';

Future<void> resetIpDialog() async {
  final ipCtrl = TextEditingController();
  var isInProgress = false;
  String? err;

  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      final ip = ipCtrl.text.trim();
      if (ip.isEmpty) {
        setState(() => err = 'IP必填');
        return;
      }
      setState(() {
        isInProgress = true;
        err = null;
      });
      final ok = await AccountApi.probeServerConfig(ip);
      setState(() => isInProgress = false);
      if (!ok) {
        setState(() => err = '该地址不是有效服务器');
        return;
      }
      await bind.mainSetOption(key: 'external-primary-server', value: ip);
      close();
      showToast('重置成功，请重启App生效');
    }

    return CustomAlertDialog(
      title: const Text('重置IP'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: ipCtrl,
            autofocus: true,
            cursorColor: const Color(0xFF2E7D32),
            decoration: InputDecoration(
              labelText: '服务器IP',
              errorText: err,
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