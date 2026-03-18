# SPDX-FileCopyrightText: 2026 piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp.MovingIcons do
  @moduledoc false

  import Bitwise

  alias SampleApp.Assets
  import SampleApp.AtomVMCompat, only: [yield: 0]

  # -----------------------------------------------------------------------------
  # デモ設定
  # -----------------------------------------------------------------------------

  @obj_count 4

  # 描画方式
  #
  # - :auto
  #     まず分割バッファ描画を試し、失敗したら LCD へ直接描画する
  #
  # - :strip_buffers
  #     分割バッファ描画を必須にする
  #
  # - :direct_lcd
  #     毎フレーム LCD へ直接描画する
  @frame_render_mode :auto

  @initial_split_factor 2

  # 元画像は単色背景付きなので、描画先を背景色で上書きしないよう透過色を使う。
  # 透過色は RGB565。`0x0000` は元の LovyanGFX デモに合わせる。
  @use_transparent_key true
  @transparent_key_rgb888 0x000000
  @transparent_key_rgb565 0x0000

  # 背景色 (RGB888)
  @bg 0x000000

  # スプライト対応
  @cap_sprite 1 <<< 0

  # 元スプライトの handle
  #
  # 表示順:
  #   0 -> piyopiyo
  #   1 -> info
  #   2 -> alert
  #   3 -> close
  @sprite_piyopiyo 1
  @sprite_info 2
  @sprite_alert 3
  @sprite_close 4

  # 分割描画用の二重バッファ
  @sprite_buf0 10
  @sprite_buf1 11

  # 倍率の範囲 (x1024 固定小数)
  # - 512  = 0.5x
  # - 2048 = 2.0x
  @zoom_min_x1024 512
  @zoom_max_x1024 2048

  # -----------------------------------------------------------------------------
  # 公開入口
  # -----------------------------------------------------------------------------

  def run(port, w, h) when is_integer(w) and w > 0 and is_integer(h) and h > 0 do
    icon_w = Assets.icon_w()
    icon_h = Assets.icon_h()

    icons = {
      Assets.icon(:piyopiyo),
      Assets.icon(:info),
      Assets.icon(:alert),
      Assets.icon(:close)
    }

    log_icon_sizes(icons, icon_w, icon_h)

    with {:ok, caps} <- LGFXPort.get_caps(port),
         :ok <- ensure_sprite_support(caps, 6),
         :ok <- LGFXPort.fill_screen(port, @bg),
         {:ok, icon_handles} <- prepare_icon_sprites(port, icons, icon_w, icon_h),
         {:ok, render_target} <- prepare_render_target(port, w, h) do
      try do
        {_seed, objects} = init_objects(1, @obj_count, w, h)

        # 状態:
        # {w, h, render_target, flip, objects, icon_handles}
        state = {w, h, render_target, 0, objects, icon_handles}

        loop(port, state)
      after
        cleanup_frame_sprites(port)
        cleanup_icon_sprites(port)
      end
    else
      {:error, reason} ->
        IO.puts("moving_icons setup failed: #{LGFXPort.format_error(reason)}")
        {:error, reason}
    end
  end

  # -----------------------------------------------------------------------------
  # 準備
  # -----------------------------------------------------------------------------

  defp ensure_sprite_support(%{feature_bits: feature_bits, max_sprites: max_sprites}, needed) do
    cond do
      (feature_bits &&& @cap_sprite) == 0 ->
        {:error, :cap_sprite_missing}

      max_sprites < needed ->
        {:error, {:insufficient_sprite_capacity, max_sprites, needed}}

      true ->
        :ok
    end
  end

  defp prepare_icon_sprites(port, icons, icon_w, icon_h) do
    piyopiyo_bin = elem(icons, 0)
    info_bin = elem(icons, 1)
    alert_bin = elem(icons, 2)
    close_bin = elem(icons, 3)

    with :ok <-
           create_and_load_icon_sprite(port, @sprite_piyopiyo, icon_w, icon_h, piyopiyo_bin),
         :ok <- create_and_load_icon_sprite(port, @sprite_info, icon_w, icon_h, info_bin),
         :ok <- create_and_load_icon_sprite(port, @sprite_alert, icon_w, icon_h, alert_bin),
         :ok <- create_and_load_icon_sprite(port, @sprite_close, icon_w, icon_h, close_bin) do
      {:ok, {@sprite_piyopiyo, @sprite_info, @sprite_alert, @sprite_close}}
    else
      {:error, _} = err ->
        cleanup_icon_sprites(port)
        err
    end
  end

  defp create_and_load_icon_sprite(port, sprite_target, icon_w, icon_h, pixels) do
    pivot_x = div(icon_w, 2)
    pivot_y = div(icon_h, 2)

    with :ok <- LGFXPort.create_sprite(port, icon_w, icon_h, sprite_target),
         :ok <- LGFXPort.clear(port, @transparent_key_rgb888, sprite_target),
         :ok <- LGFXPort.push_image_rgb565(port, 0, 0, icon_w, icon_h, pixels, 0, sprite_target),
         :ok <- LGFXPort.set_pivot(port, sprite_target, pivot_x, pivot_y) do
      :ok
    else
      {:error, reason} ->
        _ = LGFXPort.delete_sprite(port, sprite_target)
        {:error, {:sprite_setup_failed, sprite_target, reason}}
    end
  end

  defp prepare_render_target(port, w, h) do
    case @frame_render_mode do
      :direct_lcd ->
        IO.puts("moving_icons render mode=direct_lcd")
        {:ok, :direct_lcd}

      :strip_buffers ->
        with {:ok, strip_h} <- prepare_frame_sprites(port, w, h) do
          IO.puts("moving_icons render mode=strip_buffers strip_h=#{strip_h}")
          {:ok, {:strip_buffers, strip_h, @sprite_buf0, @sprite_buf1}}
        end

      :auto ->
        case prepare_frame_sprites(port, w, h) do
          {:ok, strip_h} ->
            IO.puts("moving_icons render mode=strip_buffers strip_h=#{strip_h}")
            {:ok, {:strip_buffers, strip_h, @sprite_buf0, @sprite_buf1}}

          {:error, reason} ->
            IO.puts(
              "moving_icons strip buffers unavailable: #{format_local_error(reason)}; falling back to direct_lcd"
            )

            {:ok, :direct_lcd}
        end
    end
  end

  defp prepare_frame_sprites(port, w, h) do
    prepare_frame_sprites_i(port, w, h, @initial_split_factor)
  end

  # 2 枚の分割描画用スプライトを確保する。
  # 失敗したら分割数を増やして高さを下げ、入るまで試す。
  defp prepare_frame_sprites_i(port, w, h, split_factor) do
    strip_h = max(1, div_ceil(h, split_factor))

    with :ok <- create_frame_sprite(port, @sprite_buf0, w, strip_h),
         :ok <- create_frame_sprite(port, @sprite_buf1, w, strip_h) do
      {:ok, strip_h}
    else
      {:error, reason} ->
        cleanup_frame_sprites(port)

        if strip_h == 1 do
          {:error, {:frame_sprite_alloc_failed, w, h, split_factor, reason}}
        else
          prepare_frame_sprites_i(port, w, h, split_factor + 1)
        end
    end
  end

  defp create_frame_sprite(port, target, w, h) do
    # いまは色深度を 16 固定にする
    color_depth = 16
    LGFXPort.create_sprite(port, w, h, color_depth, target)
  end

  defp cleanup_icon_sprites(port) do
    _ = safe_delete_sprite(port, @sprite_piyopiyo)
    _ = safe_delete_sprite(port, @sprite_info)
    _ = safe_delete_sprite(port, @sprite_alert)
    _ = safe_delete_sprite(port, @sprite_close)
    :ok
  end

  defp cleanup_frame_sprites(port) do
    _ = safe_delete_sprite(port, @sprite_buf0)
    _ = safe_delete_sprite(port, @sprite_buf1)
    :ok
  end

  defp safe_delete_sprite(port, sprite_target) do
    case LGFXPort.delete_sprite(port, sprite_target) do
      :ok -> :ok
      {:error, _} -> :ok
    end
  end

  # -----------------------------------------------------------------------------
  # 疑似乱数
  # -----------------------------------------------------------------------------

  # AtomVM 向け。`:rand` は使わない。
  defp rand_u32(seed) when is_integer(seed) do
    seed2 = rem(seed * 1_664_525 + 1_013_904_223, 4_294_967_296)
    {seed2, seed2}
  end

  # -----------------------------------------------------------------------------
  # 初期配置と移動
  # -----------------------------------------------------------------------------

  # オブジェクト状態:
  # {x, y, dx, dy, img_index, r_cdeg, z_x1024, dr_cdeg, dz_x1024}
  defp init_objects(seed, count, w, h) do
    init_objects_i(seed, 0, count, w, h, [])
  end

  defp init_objects_i(seed, _i, count, _w, _h, acc) when count <= 0 do
    {seed, :lists.reverse(acc)}
  end

  defp init_objects_i(seed, i, count, w, h, acc) do
    {seed, r1} = rand_u32(seed)
    {seed, r2} = rand_u32(seed)
    {seed, r3} = rand_u32(seed)
    {seed, r4} = rand_u32(seed)
    {seed, r5} = rand_u32(seed)

    img = rem(i, 4)

    x = rem(r1, w)
    y = rem(r2, h)

    dx0 = (band3(r3) + 1) * sign(i &&& 1)
    dy0 = (band3(r4) + 1) * sign(i &&& 2)

    dr_deg = (band3(r5) + 1) * sign(i &&& 2)
    dr_cdeg = dr_deg * 100

    # 倍率と倍率変化量
    # - z_x1024: 1.0..1.9
    # - dz_x1024: 0.01..0.10
    z10 = rem(r3, 10) + 10
    z_x1024 = div(z10 * 1024, 10)

    dz100 = rem(r4, 10) + 1
    dz_x1024 = div(dz100 * 1024, 100)

    obj = {x, y, dx0, dy0, img, 0, z_x1024, dr_cdeg, dz_x1024}
    init_objects_i(seed, i + 1, count - 1, w, h, [obj | acc])
  end

  defp band3(u32), do: u32 &&& 3

  defp sign(0), do: -1
  defp sign(_), do: 1

  defp move_objects(objects, w, h) do
    move_objects_i(objects, w, h, [])
  end

  defp move_objects_i([], _w, _h, acc), do: :lists.reverse(acc)

  defp move_objects_i(
         [{x, y, dx, dy, img, r_cdeg, z_x1024, dr_cdeg, dz_x1024} | rest],
         w,
         h,
         acc
       ) do
    r2 = wrap_angle_cdeg(r_cdeg + dr_cdeg)

    {x2, dx2} = bounce_i16(x + dx, dx, 0, w - 1)
    {y2, dy2} = bounce_i16(y + dy, dy, 0, h - 1)

    z2 = z_x1024 + dz_x1024
    {z3, dz2} = bounce_i32(z2, dz_x1024, @zoom_min_x1024, @zoom_max_x1024)

    move_objects_i(rest, w, h, [{x2, y2, dx2, dy2, img, r2, z3, dr_cdeg, dz2} | acc])
  end

  defp bounce_i16(pos, delta, min_v, max_v) do
    cond do
      pos < min_v -> {min_v, abs(delta)}
      pos > max_v -> {max_v, -abs(delta)}
      true -> {pos, delta}
    end
  end

  defp bounce_i32(pos, delta, min_v, max_v) do
    cond do
      pos < min_v -> {min_v, abs(delta)}
      pos > max_v -> {max_v, -abs(delta)}
      true -> {pos, delta}
    end
  end

  defp wrap_angle_cdeg(a) do
    cond do
      a < 0 -> a + 36_000
      a >= 36_000 -> a - 36_000
      true -> a
    end
  end

  # -----------------------------------------------------------------------------
  # 描画ループ
  # -----------------------------------------------------------------------------

  defp loop(port, {w, h, render_target, flip0, objects0, icon_handles}) do
    objects = move_objects(objects0, w, h)

    case render_frame(port, h, render_target, flip0, objects, icon_handles) do
      {:ok, flip1} ->
        yield()
        loop(port, {w, h, render_target, flip1, objects, icon_handles})

      {:error, reason} ->
        IO.puts("moving_icons render failed: #{LGFXPort.format_error(reason)}")
        {:error, reason}
    end
  end

  defp render_frame(port, _h, :direct_lcd, _flip0, objects, icon_handles) do
    with :ok <- LGFXPort.fill_screen(port, @bg),
         :ok <- draw_all_objects_to_target(port, objects, icon_handles, 0, 0),
         :ok <- LGFXPort.display(port) do
      {:ok, 0}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp render_frame(
         port,
         h,
         {:strip_buffers, strip_h, buf0, buf1},
         flip0,
         objects,
         icon_handles
       ) do
    render_strips(port, h, strip_h, buf0, buf1, flip0, objects, icon_handles)
  end

  defp render_strips(port, h, strip_h, buf0, buf1, flip0, objects, icon_handles) do
    case render_strips_i(port, h, strip_h, 0, buf0, buf1, flip0, objects, icon_handles) do
      {:ok, flip1} ->
        case LGFXPort.display(port) do
          :ok -> {:ok, flip1}
          {:error, reason} -> {:error, reason}
        end

      {:error, _} = err ->
        err
    end
  end

  defp render_strips_i(_port, h, _strip_h, y, _buf0, _buf1, flip, _objects, _icons)
       when y >= h do
    {:ok, flip}
  end

  # 1 フレームを縦方向に分けて描画する。
  # 物体が重なったときの描き直しのちらつきを避けるため、
  # いったん分割バッファへ描いてから LCD へ転送する。
  defp render_strips_i(port, h, strip_h, y0, buf0, buf1, flip0, objects, icon_handles) do
    {flip1, buf} =
      if flip0 == 0 do
        {1, buf0}
      else
        {0, buf1}
      end

    with :ok <- LGFXPort.clear(port, @bg, buf),
         :ok <- draw_all_objects_to_target(port, objects, icon_handles, buf, y0),
         :ok <- LGFXPort.push_sprite(port, buf, 0, y0) do
      render_strips_i(
        port,
        h,
        strip_h,
        y0 + strip_h,
        buf0,
        buf1,
        flip1,
        objects,
        icon_handles
      )
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp draw_all_objects_to_target(port, objects, icon_handles, dst_target, y0) do
    draw_all_objects_to_target_i(port, objects, icon_handles, dst_target, y0)
  end

  defp draw_all_objects_to_target_i(_port, [], _icons, _dst_target, _y0), do: :ok

  defp draw_all_objects_to_target_i(
         port,
         [{x, y, _dx, _dy, img, r_cdeg, z_x1024, _dr, _dz} | rest],
         icon_handles,
         dst_target,
         y0
       ) do
    src =
      case img do
        0 -> elem(icon_handles, 0)
        1 -> elem(icon_handles, 1)
        2 -> elem(icon_handles, 2)
        3 -> elem(icon_handles, 3)
      end

    # 分割描画時は、その帯の先頭 y を引いた座標で描く。
    # LCD 直接描画時は y0 は 0。
    dst_x = x
    dst_y = y - y0

    result =
      if @use_transparent_key do
        LGFXPort.push_rotate_zoom_to(
          port,
          src,
          dst_target,
          dst_x,
          dst_y,
          r_cdeg,
          z_x1024,
          z_x1024,
          @transparent_key_rgb565
        )
      else
        LGFXPort.push_rotate_zoom_to(
          port,
          src,
          dst_target,
          dst_x,
          dst_y,
          r_cdeg,
          z_x1024,
          z_x1024
        )
      end

    case result do
      :ok -> draw_all_objects_to_target_i(port, rest, icon_handles, dst_target, y0)
      {:error, reason} -> {:error, reason}
    end
  end

  # -----------------------------------------------------------------------------
  # 補助関数
  # -----------------------------------------------------------------------------

  defp log_icon_sizes(icons, icon_w, icon_h) do
    expected = icon_w * icon_h * 2
    i0 = byte_size(elem(icons, 0))
    i1 = byte_size(elem(icons, 1))
    i2 = byte_size(elem(icons, 2))
    i3 = byte_size(elem(icons, 3))

    IO.puts("icon bytes piyopiyo=#{i0} info=#{i1} alert=#{i2} close=#{i3} expected=#{expected}")
  end

  defp div_ceil(a, b) when is_integer(a) and is_integer(b) and b > 0 do
    div(a + b - 1, b)
  end

  defp format_local_error({:frame_sprite_alloc_failed, w, h, split_factor, reason}) do
    "frame sprite alloc failed w=#{w} h=#{h} split_factor=#{split_factor} reason=#{LGFXPort.format_error(reason)}"
  end

  defp format_local_error(reason), do: inspect(reason)
end
