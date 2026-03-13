<!--
SPDX-FileCopyrightText: 2026 piyopiyo.ex members

SPDX-License-Identifier: Apache-2.0
-->

# lovyangfx

[LovyanGFX](https://github.com/lovyan03/LovyanGFX) を組み込んだ表示サンプルです。

このサンプルでは、専用の AtomVM イメージを書き込んだうえで、RGB565 画像を使ったアニメーションを表示します。
カスタムの AtomVM イメージを書き込み、その上でアプリケーションを書き換えながら動かす流れを確認できます。

<p align="center">
  <img alt="lovyangfx" width="320" src="https://github.com/user-attachments/assets/54818ce9-65bc-4567-a1be-24a20a242a0d">
</p>

## この例で試すこと

- 専用の AtomVM イメージを書き込む
- RGB565 画像を表示する
- 画像の移動、回転、拡大縮小を実機で確認する
- 表示内容や素材を差し替えて反映させる

## 使い方

このディレクトリーに移動します。

```sh
cd lovyangfx
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

書き込み後、画面上で画像が動いて表示されれば成功です。
