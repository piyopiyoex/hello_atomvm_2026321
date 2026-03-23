<!--
SPDX-FileCopyrightText: 2026 Masatoshi Nishiguchi, piyopiyo.ex members

SPDX-License-Identifier: Apache-2.0
-->

# AtomLGFX

`AtomLGFX` は、AtomVM 上から LovyanGFX 系の表示機能を扱うための Elixir インターフェースです。

## 概要

基本的な流れは次のとおりです。

1. ドライバーを開く
2. 疎通を確認する
3. デバイスを初期化する
4. 描画する
5. 表示へ反映する

`ili9488` を使う最小例です。

```elixir
# ili9488 向けの設定でドライバーを開く
{:ok, port} = AtomLGFX.open(panel_driver: :ili9488, width: 320, height: 480)

# ドライバーとの疎通を確認する
:ok = AtomLGFX.ping(port)

# 設定内容を使ってデバイスを初期化する
:ok = AtomLGFX.init(port)

# 画面を黒で塗りつぶす
:ok = AtomLGFX.fill_screen(port, 0x000000)

# 日本語フォントと文字サイズを設定する
:ok = AtomLGFX.set_text_font_preset(port, :jp)
:ok = AtomLGFX.set_text_size(port, 2)

# 文字色を設定して文字列を描画する
:ok = AtomLGFX.set_text_color(port, 0xFFFFFF, 0x000000)
:ok = AtomLGFX.draw_string(port, 16, 16, "こんにちは")

# 描画結果を画面へ反映する
:ok = AtomLGFX.display(port)
```

実際の利用では、配線や基板構成に応じて追加の開始時設定が必要になる場合があります。

## 基本事項

### 対象

多くの関数は「対象」を扱います。

- `0`
  - LCD

- `1..254`
  - スプライト番号

対象引数を省略できる関数では、通常 `0`、つまり LCD が使われます。

```elixir
:ok = AtomLGFX.fill_screen(port, 0x000000)
:ok = AtomLGFX.fill_screen(port, 0x000000, 0)
:ok = AtomLGFX.fill_screen(port, 0x000000, 1)
```

### 色

#### RGB888 色

基本図形や文字色では、RGB888 整数を使います。

```elixir
0x000000
0xFFFFFF
0x112233
```

#### 添字色

一部の関数では、添字色も使えます。

```elixir
{:index, 3}
```

添字色は、パレット対応スプライトに対してのみ有効です。

#### スプライト転送時の透過色

スプライト転送では、透過色として次のどちらかを指定できます。

- RGB565 整数
- 添字色

```elixir
0xF800
{:index, 0}
```

添字色による透過指定は、パレット対応の元スプライトに対してのみ有効です。

### 返り値

代表的な返り値は次のとおりです。

- `:ok`
- `{:ok, value}`
- `{:error, reason}`

## 開始と終了

### `open/1`

ネイティブドライバーを開きます。

引数には開始時設定のキーワードリストまたはプロパティリストを渡します。省略した項目には、ドライバーのビルド時既定値が使われます。

```elixir
port = AtomLGFX.open(panel_driver: :ili9488, width: 320, height: 480)
```

### `ping/1`

基本的な疎通を確認します。

```elixir
:ok = AtomLGFX.ping(port)
```

### `init/1`

そのポートに記憶されている開始時設定を使って、ネイティブデバイスを初期化します。

```elixir
:ok = AtomLGFX.init(port)
```

### `display/1`

現在の描画結果を画面へ反映します。

```elixir
:ok = AtomLGFX.display(port)
```

### `close/1`

そのポートが所有するネイティブ側のデバイス状態を終了します。

```elixir
:ok = AtomLGFX.close(port)
```

## 表示制御

### `start_write/1` と `end_write/1`

LCD デバイスに対して書き込み開始状態へ入り、終了します。

これらは LovyanGFX の `startWrite()` と `endWrite()` に対応します。

```elixir
:ok = AtomLGFX.start_write(port)

:ok = AtomLGFX.draw_line(port, 0, 0, 100, 100, 0xFFFFFF)
:ok = AtomLGFX.draw_rect(port, 10, 10, 50, 30, 0x00FF00)

:ok = AtomLGFX.end_write(port)
:ok = AtomLGFX.display(port)
```

### `set_rotation/2`

LCD の回転を設定します。

受け付け値は `0..7` です。

```elixir
:ok = AtomLGFX.set_rotation(port, 1)
```

### `set_brightness/2`

LCD の明るさを設定します。

```elixir
:ok = AtomLGFX.set_brightness(port, 128)
```

### `set_color_depth/3`

対象の色深度を設定します。

利用できる値は次のとおりです。

- `1`
- `2`
- `4`
- `8`
- `16`
- `24`

```elixir
:ok = AtomLGFX.set_color_depth(port, 16)
:ok = AtomLGFX.set_color_depth(port, 8, 1)
```

## クリップ

### `set_clip_rect/6`

対象に切り取り矩形を設定します。

```elixir
:ok = AtomLGFX.set_clip_rect(port, 10, 10, 100, 80)
```

### `clear_clip_rect/2`

設定されている切り取り矩形を解除します。

```elixir
:ok = AtomLGFX.clear_clip_rect(port)
```

LCD とスプライトは、それぞれ独立した切り取り状態を持ちます。

## 基本図形

### 対象全体への描画

- `fill_screen/3`
- `clear/3`

```elixir
:ok = AtomLGFX.fill_screen(port, 0x101820)
:ok = AtomLGFX.clear(port, 0x000000)
```

### 点と線

- `draw_pixel/5`
- `draw_fast_vline/6`
- `draw_fast_hline/6`
- `draw_line/7`

```elixir
:ok = AtomLGFX.draw_pixel(port, 20, 20, 0xFFFFFF)
:ok = AtomLGFX.draw_line(port, 0, 0, 100, 100, 0x00FF00)
```

### 矩形、円、三角形

- `draw_rect/7`
- `fill_rect/7`
- `draw_circle/6`
- `fill_circle/6`
- `draw_triangle/9`
- `fill_triangle/9`

```elixir
:ok = AtomLGFX.draw_rect(port, 20, 20, 120, 60, 0x00FF00)
:ok = AtomLGFX.fill_circle(port, 220, 120, 24, 0xFFAA00)
```

## 文字

### 文字種と倍率

`AtomLGFX` では、文字種と文字倍率を別々に設定します。

使う関数は次のとおりです。

- `set_text_font_preset/3`
- `set_text_size/3`
- `set_text_size_xy/4`

利用できる文字プリセットは次の 2 つです。

- `:ascii`
- `:jp`

```elixir
:ok = AtomLGFX.set_text_font_preset(port, :jp)
:ok = AtomLGFX.set_text_size(port, 2)
```

倍率には `1`、`2`、`1.5` のような自然な値を使えます。

### 文字基準位置と折り返し

- `set_text_datum/3`
- `set_text_wrap/3`
- `set_text_wrap_xy/4`

`set_text_datum/3` は `0..255` を受け付けます。

`set_text_wrap/3` は LovyanGFX 互換の 1 引数形式です。

- `wrap_x = wrap`
- `wrap_y = false`

```elixir
:ok = AtomLGFX.set_text_wrap(port, true)
:ok = AtomLGFX.set_text_wrap_xy(port, true, true)
```

### 文字色

`set_text_color/4` では、前景色だけ、または前景色と背景色の両方を指定できます。

```elixir
:ok = AtomLGFX.set_text_color(port, 0xFFFFFF)
:ok = AtomLGFX.set_text_color(port, 0xFFFFFF, 0x000000)
```

### カーソルと書き込み

- `set_cursor/4`
- `get_cursor/2`
- `print/3`
- `println/3`

```elixir
:ok = AtomLGFX.set_cursor(port, 16, 48)
:ok = AtomLGFX.print(port, "Line 1")
:ok = AtomLGFX.println(port, " Line 2")
```

### 直接描画

- `draw_string/5`
- `draw_string_bg/8`

```elixir
:ok = AtomLGFX.draw_string(port, 16, 16, "日本語テキスト")
```

`draw_string_bg/8` は、文字色と倍率を設定してから文字列を描画する補助関数です。

## スプライト

### 作成と削除

スプライト番号には `1..254` を使います。

- `create_sprite/4`
- `create_sprite/5`
- `delete_sprite/2`

```elixir
:ok = AtomLGFX.create_sprite(port, 120, 80, 1)
:ok = AtomLGFX.create_sprite(port, 120, 80, 8, 2)
:ok = AtomLGFX.delete_sprite(port, 1)
```

### パレット

- `create_palette/2`
- `set_palette_color/4`

```elixir
:ok = AtomLGFX.create_palette(port, 1)
:ok = AtomLGFX.set_palette_color(port, 1, 0, 0x112233)
```

### 基準点

`set_pivot/4` は、回転や拡大縮小で使う基準点を設定します。

```elixir
:ok = AtomLGFX.set_pivot(port, 1, 60, 40)
```

### スプライト転送

- `push_sprite_to/5`
- `push_sprite_to/6`
- `push_sprite/4`
- `push_sprite/5`

```elixir
:ok = AtomLGFX.push_sprite(port, 1, 40, 30)
:ok = AtomLGFX.push_sprite(port, 1, 40, 30, 0x0000)
:ok = AtomLGFX.push_sprite_to(port, 1, 0, 40, 30)
```

### 回転と拡大縮小

- `push_rotate_zoom_to/7`
- `push_rotate_zoom_to/8`
- `push_rotate_zoom_to/9`

角度は度数法、倍率は自然な数値で指定します。

```elixir
:ok = AtomLGFX.push_rotate_zoom_to(port, 1, 0, 160, 120, 30.0, 1.5)
:ok = AtomLGFX.push_rotate_zoom_to(port, 1, 0, 160, 120, 30.0, 1.2, 1.5)
```

## 画像

### JPEG 描画

JPEG 関連の関数は次のとおりです。

- `draw_jpg/5`
- `draw_jpg/11`
- `draw_jpg_scaled/10`
- `draw_jpg_scaled/11`

```elixir
:ok = AtomLGFX.draw_jpg(port, 0, 0, jpeg_binary)
```

```elixir
:ok = AtomLGFX.draw_jpg(port, 0, 0, 320, 480, 0, 0, 1.0, 1.0, jpeg_binary)
```

```elixir
:ok = AtomLGFX.draw_jpg_scaled(port, 0, 0, 320, 480, 0, 0, 1.5, jpeg_binary)
```

### RGB565 画像転送

`push_image_rgb565/8` は、RGB565 の画素バイナリを対象へ転送します。

```elixir
:ok = AtomLGFX.push_image_rgb565(port, 0, 0, width, height, pixels)
```

```elixir
:ok = AtomLGFX.push_image_rgb565(port, 0, 0, width, height, pixels, stride_pixels)
```

## タッチ

### タッチ状態の取得

- `get_touch/1`
- `get_touch_raw/1`

どちらも返り値は次のいずれかです。

- `{:ok, :none}`
- `{:ok, {x, y, size}}`

```elixir
case AtomLGFX.get_touch(port) do
  {:ok, :none} ->
    :noop

  {:ok, {x, y, size}} ->
    IO.inspect({x, y, size})

  {:error, reason} ->
    IO.inspect(reason)
end
```

### タッチ補正

- `set_touch_calibrate/2`
- `calibrate_touch/1`

```elixir
:ok = AtomLGFX.set_touch_calibrate(port, {1, 2, 3, 4, 5, 6, 7, 8})
```

`calibrate_touch/1` は対話的な補正を実行し、結果の 8 要素タプルを返します。
