<!--
SPDX-FileCopyrightText: 2026 piyopiyo.ex members

SPDX-License-Identifier: Apache-2.0
-->

# atomgl

[AtomGL](https://github.com/atomvm/atomgl) を使った表示サンプルです。

このサンプルでは、ILI9488 ディスプレイに文字や図形を描画し、タッチした位置を画面上に表示します。
[atomgl](https://github.com/atomvm/atomgl) と [avm_scene](https://github.com/atomvm/avm_scene) を使った、画面表示と入力処理の基本的な流れを確認できます。

<p align="center">
  <img alt="atomgl" width="320" src="https://github.com/user-attachments/assets/5926108a-c781-4dcc-856d-d300c1233715">
</p>

## この例で試すこと

- 専用の AtomVM イメージを書き込む
- 文字表示とタッチ入力を実機で確認する
- 画面の文言や配色を変更して反映させる

## 使い方

このディレクトリーに移動します。

```sh
cd atomgl
```

依存関係を取得します。

```sh
mix deps.get
```

このサンプル用の AtomVM イメージがまだ ESP32-S3 に書き込まれていない場合は、先に次を実行してください。
すでに書き込み済みの場合は、この手順は不要です。

```sh
# フラッシュ全体を消去して、まっさらな状態にする
esptool --chip esp32s3 --port /dev/ttyACM0 erase-flash

# このサンプル用の AtomVM イメージを 0x0 から書き込む
esptool --chip esp32s3 --port /dev/ttyACM0 write-flash 0x0 atomvm-esp32s3-elixir.img
```

アプリケーションを書き込みます。

```sh
mix atomvm.esp32.flash --port /dev/ttyACM0
```

接続先は必要に応じて読み替えてください。

例:

- Linux: `/dev/ttyACM0`, `/dev/ttyUSB0`
- macOS: `/dev/cu.usbmodemXXXX`, `/dev/cu.usbserialXXXX`

接続先が分からない場合は、次で確認できます。

```sh
tio --list
```

## 動作確認

別端末でシリアルログを開きます。

```sh
tio /dev/ttyACM0
```

書き込み後、画面に次のような内容が表示されれば成功です。

- `Hello, AtomVM`
- `ESP32-S3 + Elixir`
- `Touch the screen`
- `Edit this file and flash again`

画面を触ると、タッチ位置に赤い印が表示され、座標が更新されます。

## 補足

- [AtomGL の設定方法](https://github.com/atomvm/atomgl/blob/main/docs/display-drivers.md)
