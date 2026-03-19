<!--
SPDX-FileCopyrightText: 2026 Masatoshi Nishiguchi, piyopiyo.ex members

SPDX-License-Identifier: Apache-2.0
-->

# AtomVM Elixir ESP32-S3 ハンズオン

本ハンズオンでは、事前構築済みの [AtomVM] イメージを ESP32-S3 に書き込みます。
そのうえで、Elixir アプリケーションを `.avm` として作成し、実機に書き込んで動作を確認します。

一度 AtomVM 側の準備ができれば、その後はアプリケーションを書き換えながら `.avm` を繰り返し書き込んで試せます。

ハンズオンに関する質問や作例の共有は、[Discussions][discussions] をご利用ください。

## 対象機材

- [Seeed Studio XIAO ESP32S3][xiao_esp32s3] を搭載した [piyopiyo-pcb]
- 表示用に ILI9488 ディスプレイを使用

[![](https://media.connpass.com/thumbs/e1/2e/e12e4210dff87d0a423c872c0d606b2d.png)](https://piyopiyoex.connpass.com/event/373137/)

## 対象開発環境

本ハンズオンでは、次の環境を想定しています。

- macOS または Linux
- データ転送に対応した USB ケーブル
- Elixir
- `mix` (Elixir プロジェクトのビルドや書き込みに使うコマンド)
- `esptool` (ESP32-S3 にイメージを書き込むためのツール)
- `tio` ([シリアルログを確認するためのツール][シリアルコンソール])

このハンズオンでは、次の準備は不要です。

- AtomVM 本体の手動ビルド
- ESP-IDF の導入
- C 言語向け開発環境の準備

詳しくは、AtomVM 公式の [ESP32 Requirements][atomvm esp32-requirements] ドキュメントを参照してください。

## サンプル

- [`blinky`](./blinky/): XIAO ESP32S3 のオンボード LED を点滅させる最小例
- [`atomgl`](./atomgl/): AtomGL を使った文字表示とタッチ入力の例
- [`lovyangfx`](./lovyangfx/): LovyanGFX を使った画像表示とアニメーションの例

詳しくは各ディレクトリーの `README.md` を参照してください。

## 開発の流れ

このハンズオンでは、次の流れで進めます。

1. 事前構築済みの AtomVM イメージを ESP32-S3 に書き込む
2. `tio` で起動ログを確認する
3. Elixir アプリケーションを `.avm` にまとめる
4. `.avm` を実機へ書き込む
5. 動作を確認しながらコードを変更し、再度 `.avm` を書き込む

## 環境構築

### Elixir と Erlang/OTP

Elixir と Erlang/OTP の一般的な対応範囲は、次の資料を参照してください。

- [Elixir 公式の対応表][elixir compatibility-and-deprecations]
- [AtomVM 側の変更点や対応状況][atomvm release-notes]

本リポジトリーで動作確認している版は、[.tool-versions](./.tool-versions) を参照してください。

Elixir 開発では、`mise` や `asdf` がよく使われます。
ここでは `mise` の例を示します。

```bash
cat .tool-versions
mise install
mise ls
```

### esptool

`esptool` は、ESP32-S3 に AtomVM イメージを書き込むためのツールです。

導入方法はいくつかあります。
詳しくは [公式ドキュメント][esptool installation] を参照してください。

ここでは、`pipx` と `mise` を使う例を示します。

```bash
pipx --version
mise use --global pipx:esptool
mise ls
```

### tio

`tio` は、ESP32-S3 のシリアルログを確認するためのツールです。

Debian 系では、次のように導入できます。

```bash
sudo apt install tio
```

macOS や Linux で Homebrew を使う場合は、次のように導入できます。

```bash
brew install tio
```

導入後は、次のように確認できます。

```bash
tio --version
tio --list
```

`tio --list` を使うと、接続されているシリアル機器の接続先を確認できます。

詳しくは [公式ドキュメント][tio] を参照してください。

## Piyopiyo PCB の配線

### v1.5 以前

| 用途        | XIAO ESP32S3 の端子 | ESP32-S3 の GPIO |
| ----------- | ------------------- | ---------------- |
| SCLK        | D8                  | 7                |
| MISO        | D9                  | 8                |
| MOSI        | D10                 | 9                |
| Display CS  | —                   | 43               |
| Touch CS    | —                   | 44               |
| Display D/C | D2                  | 3                |
| Display RST | D1                  | 2                |
| SDCard CS   | D3                  | 4                |

### v1.6 以降

次の 2 本の信号が入れ替わります。

- Display CS → GPIO4
- SDCard CS → GPIO43

現状の `atomgl` と `lovyangfx` は、コード上は v1.5 以前の配線を前提にしています。
v1.6 以降の基板で試す場合は、表示まわりの CS 設定を見直してください。

## フラッシュ上の配置

AtomVM を ESP32-S3 で使うときは、フラッシュ全体をおおむね次のように使います。

```text
|               |
+---------------+  ----------- 0x0
| boot loader   |           ^
+---------------+           |
| partition map |           | AtomVM
+---------------+           | binary
|               |           | image
|   AtomVM      |           |
|   Virtual     |           |
|   Machine     |           |
|               |           v
+---------------+  ----------- 0x250000
|               |           ^
|               |           |
|     data      |           | Elixir
|   partition   |           | application
|               |           |
|               |           v
+---------------+  ----------- end
```

このハンズオンでは、まず事前構築済みの AtomVM イメージ全体を書き込みます。
このイメージには、boot loader、partition map、AtomVM Virtual Machine が含まれます。

その後、各サンプルの Elixir アプリケーションを書き込みます。
このリポジトリーのサンプルでは、アプリケーションの書き込み先は `0x250000` です。

つまり、通常の開発では AtomVM 本体を書き換えるのではなく、アプリケーション領域だけを書き換えながら試します。

詳しくは [AtomVM Getting Started Guide][atomvm getting-started] を参照してください。

## よくある詰まりどころ

- USB ケーブルが給電専用で、通信に対応していない
- ポート名を取り違えている
- `esptool` が見つからない
- ほかのシリアル監視ツールがポートを使用している
- Elixir と Erlang/OTP の組み合わせが合っていない
- サンプルに対応しない AtomVM イメージを書き込んでいる

[AtomVM]: https://atomvm.org/
[atomvm]: https://atomvm.org/
[piyopiyo-pcb]: https://github.com/piyopiyoex/piyopiyo-pcb
[xiao_esp32s3]: https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/
[atomvm getting-started]: https://doc.atomvm.org/latest/getting-started-guide.html
[elixir compatibility-and-deprecations]: https://hexdocs.pm/elixir/compatibility-and-deprecations.html
[atomvm release-notes]: https://doc.atomvm.org/main/release-notes.html
[atomvm esp32-requirements]: https://doc.atomvm.org/main/getting-started-guide.html#esp32-requirements
[シリアルコンソール]: https://wiki.archlinux.jp/index.php/%E3%82%B7%E3%83%AA%E3%82%A2%E3%83%AB%E3%82%B3%E3%83%B3%E3%82%BD%E3%83%BC%E3%83%AB
[tio]: https://github.com/tio/tio
[esptool installation]: https://docs.espressif.com/projects/esptool/en/latest/esp32/installation.html
[discussions]: https://github.com/piyopiyoex/hello_atomvm_2026321/discussions
