<!--
SPDX-FileCopyrightText: 2026 piyopiyo.ex members

SPDX-License-Identifier: Apache-2.0
-->

# lovyangfx

[LovyanGFX](https://github.com/lovyan03/LovyanGFX) を組み込んだ表示サンプルです。

このサンプルでは、LovyanGFX が使える専用の AtomVM イメージを書き込んだうえで、
Stack-chan 風の顔アニメーションを表示します。

あわせて、Wi-Fi 接続と Distributed Erlang に対応しており、
別端末の IEx から表情や視線、口の開き具合を変更できます。

<p align="center">
  <img alt="lovyangfx" width="320" src="https://github.com/user-attachments/assets/47e24bd0-ea04-4f8e-bde6-708dc2fe6b35">
</p>

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

Wi-Fi と Distributed Erlang も使う場合は、アプリケーションを書き込む前に Wi-Fi 情報を設定します。
Wi-Fi を使わずに顔表示だけを試す場合は、この手順は省略できます。

```sh
export ATOMVM_WIFI_SSID="your-ssid"
export ATOMVM_WIFI_PASSPHRASE="your-passphrase"
```

必要に応じて、起動のたびに Wi-Fi 情報を上書きできます。

```sh
export ATOMVM_WIFI_FORCE=true
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

書き込み後、画面上で顔が動いて表示されれば成功です。

Wi-Fi 情報を設定している場合は、あわせて Wi-Fi 接続と Distributed Erlang の起動ログも表示されます。

例:

```text
wifi: first-time provision (stored Wi-Fi credentials in NVS)
wifi: connected to AP
wifi: got IP {{192,168,1,123},{255,255,255,0},{192,168,1,1}}
disterl: started
disterl: node :"piyopiyo@192.168.1.123"
disterl: cookie <<"AtomVM">>
disterl: registered process :disterl
sntp: synced {tv_sec, tv_usec}
```

## リモート操作

Wi-Fi と Distributed Erlang が起動していれば、別端末の IEx から顔を変更できます。

まず、開発端末側で IEx をノード名付きで起動します。
`YOUR_HOST_LAN_IP` には、ESP32 と同じネットワーク上の開発端末の IP アドレスを指定してください。

```sh
iex --name host@YOUR_HOST_LAN_IP --cookie AtomVM
```

次に IEx 上で ESP32 ノードへ接続します。
`YOUR_ESP32_IP` には、シリアルログに表示された IP アドレスを指定してください。

```elixir
device = :"piyopiyo@YOUR_ESP32_IP"

Node.connect(device)
:erpc.call(device, SampleApp.DistErl, :hello, [])
:erpc.call(device, SampleApp.DistErl, :set_expression, [:happy])
:erpc.call(device, SampleApp.DistErl, :set_gaze, [0.8, -0.4])
:erpc.call(device, SampleApp.DistErl, :set_mouth_open, [0.9])
:erpc.call(device, SampleApp.DistErl, :get_face_state, [])
send({:disterl, device}, :demo_message)
```

表情には次を指定できます。

- `:neutral`
- `:happy`
- `:angry`
- `:sad`
- `:doubt`
- `:sleepy`

## 補足

Wi-Fi 情報を設定せずに書き込んだ場合でも、顔表示そのものは動作します。
その場合、Wi-Fi と Distributed Erlang は起動せず、シリアルログにその旨が表示されます。
