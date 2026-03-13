<!--
SPDX-FileCopyrightText: 2026 Masatoshi Nishiguchi, piyopiyo.ex members

SPDX-License-Identifier: Apache-2.0
-->

# blinky

最小構成の LED 点滅サンプルです。

このサンプルでは、XIAO ESP32S3 のオンボード LED につながっている GPIO 21 を 1 秒ごとに切り替えながら、状態をログに出力します。

まずはこのサンプルで、AtomVM 上で Elixir アプリケーションを動かす基本の流れを確認します。

<p align="center">
  <img alt="blinky" width="320" src="https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/82804/729af366-0db7-4be2-8faa-b1a9cce5e7c1.gif">
</p>

## この例で試すこと

- AtomVM の標準イメージを書き込む
- Elixir アプリケーションを実機に書き込む
- シリアルログを見ながら動作を確認する

## 使い方

このディレクトリーに移動します。

```sh
cd blinky
```

依存関係を取得します。

```sh
mix deps.get
```

AtomVM 本体がまだ ESP32-S3 に書き込まれていない場合は、先に次を実行してください。
すでに書き込み済みの場合は、この手順は不要です。

```sh
mix atomvm.esp32.install
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

期待される出力例:

```text
Setting pin 21 low
Setting pin 21 high
Setting pin 21 low
Setting pin 21 high
Setting pin 21 low
```

XIAO ESP32S3 のオンボード LED が 1 秒ごとに点滅していれば成功です。
