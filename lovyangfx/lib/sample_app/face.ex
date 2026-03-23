# SPDX-FileCopyrightText: 2026 Masatoshi Nishiguchi, piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp.Face do
  @moduledoc false

  import Bitwise

  @canvas_width 320
  @canvas_height 240

  @eye_r 8
  @eye_r_x 90
  @eye_r_y 93
  @eye_l_x 230
  @eye_l_y 96

  @brow_w 32
  @brow_h 0
  @brow_r_x 96
  @brow_r_y 67
  @brow_l_x 230
  @brow_l_y 72

  @mouth_min_w 50
  @mouth_max_w 90
  @mouth_min_h 4
  @mouth_max_h 60
  @mouth_x 163
  @mouth_y 148

  @col_pr 0x0000
  @col_bg 0xFFE0
  @col_sweat 0x001F
  @col_heart 0xF813

  @offset_x div(480 - @canvas_width, 2)
  @offset_y div(320 - @canvas_height, 2)

  @sprite_target 1
  @sprite_depth 16

  @external_gaze_hold_ms 1_500

  defstruct expr: :neutral,
            eye_open_l: 1.0,
            eye_open_r: 1.0,
            mouth_open: 0.0,
            gaze_h: 0.0,
            gaze_v: 0.0,
            breath: 0.0,
            breath_count: 0,
            eye_open: true,
            last_blink_ms: 0,
            blink_interval: 2_500,
            last_saccade_ms: 0,
            saccade_interval: 500,
            external_gaze: false,
            external_gaze_ms: 0,
            sprite_target: @sprite_target,
            initialized: false,
            rand_seed: 1

  def new do
    now_ms = monotonic_ms()
    {seed1, blink_rand} = rand_mod(1, 20)
    {seed2, saccade_rand} = rand_mod(seed1, 20)

    %__MODULE__{
      expr: :neutral,
      eye_open_l: 1.0,
      eye_open_r: 1.0,
      mouth_open: 0.0,
      gaze_h: 0.0,
      gaze_v: 0.0,
      breath: 0.0,
      breath_count: 0,
      eye_open: true,
      last_blink_ms: now_ms,
      blink_interval: 2_500 + 100 * blink_rand,
      last_saccade_ms: now_ms,
      saccade_interval: 500 + 100 * saccade_rand,
      external_gaze: false,
      external_gaze_ms: now_ms,
      sprite_target: @sprite_target,
      initialized: false,
      rand_seed: seed2
    }
  end

  def init(%__MODULE__{initialized: true} = face, _port), do: {:ok, face}

  def init(%__MODULE__{} = face, port) do
    with :ok <-
           AtomLGFX.create_sprite(
             port,
             @canvas_width,
             @canvas_height,
             @sprite_depth,
             face.sprite_target
           ),
         :ok <- AtomLGFX.set_swap_bytes(port, true, face.sprite_target),
         :ok <- AtomLGFX.fill_screen(port, @col_bg, face.sprite_target) do
      {:ok, %{face | initialized: true}}
    end
  end

  def set_expression(%__MODULE__{} = face, expr)
      when expr in [:neutral, :happy, :angry, :sad, :doubt, :sleepy] do
    %{face | expr: expr}
  end

  def set_mouth_open(%__MODULE__{} = face, ratio) when is_number(ratio) do
    %{face | mouth_open: clamp(ratio * 1.0, 0.0, 1.0)}
  end

  def set_gaze(%__MODULE__{} = face, horizontal, vertical)
      when is_number(horizontal) and is_number(vertical) do
    now_ms = monotonic_ms()

    %{
      face
      | gaze_h: clamp(horizontal * 1.0, -1.0, 1.0),
        gaze_v: clamp(vertical * 1.0, -1.0, 1.0),
        external_gaze: true,
        external_gaze_ms: now_ms
    }
  end

  def update(%__MODULE__{} = face, now_ms) when is_integer(now_ms) do
    face
    |> update_breath()
    |> update_blink(now_ms)
    |> update_saccade(now_ms)
  end

  def draw(%__MODULE__{initialized: false} = face, port) do
    with {:ok, initialized_face} <- init(face, port) do
      draw(initialized_face, port)
    end
  end

  def draw(%__MODULE__{} = face, port) do
    breath_offset = min(1.0, face.breath)
    by = trunc(breath_offset * 3)

    with :ok <- AtomLGFX.fill_screen(port, @col_bg, face.sprite_target),
         :ok <- draw_mouth(port, face, @mouth_x, @mouth_y + by),
         :ok <- draw_eye(port, face, @eye_r_x, @eye_r_y + by, face.eye_open_r, false),
         :ok <- draw_eye(port, face, @eye_l_x, @eye_l_y + by, face.eye_open_l, true),
         :ok <- maybe_draw_eyebrows(port, face, by),
         :ok <- draw_effect(port, face, breath_offset),
         :ok <- AtomLGFX.push_sprite(port, face.sprite_target, @offset_x, @offset_y) do
      :ok
    end
  end

  defp draw_eye(port, face, x, y, open_ratio, is_left) do
    offset_x = trunc(face.gaze_h * 3)
    offset_y = trunc(face.gaze_v * 3)
    eye_x = x + offset_x
    eye_y = y + offset_y
    target = face.sprite_target

    if open_ratio > 0.0 do
      with :ok <- AtomLGFX.fill_circle(port, eye_x, eye_y, @eye_r, @col_pr, target),
           :ok <- maybe_apply_angry_sad_mask(port, face, eye_x, eye_y, is_left, target),
           :ok <- maybe_apply_happy_sleepy_mask(port, face, eye_x, eye_y, target) do
        :ok
      end
    else
      AtomLGFX.fill_rect(
        port,
        x - @eye_r + offset_x,
        y - 2 + offset_y,
        @eye_r * 2,
        4,
        @col_pr,
        target
      )
    end
  end

  defp maybe_apply_angry_sad_mask(port, face, eye_x, eye_y, is_left, target) do
    if face.expr in [:angry, :sad] do
      x0 = eye_x - @eye_r
      y0 = eye_y - @eye_r
      x1 = x0 + @eye_r * 2
      y1 = y0
      x2 = if(not is_left != not (face.expr == :sad), do: x0, else: x1)
      y2 = y0 + @eye_r

      AtomLGFX.fill_triangle(port, x0, y0, x1, y1, x2, y2, @col_bg, target)
    else
      :ok
    end
  end

  defp maybe_apply_happy_sleepy_mask(port, face, eye_x, eye_y, target) do
    if face.expr in [:happy, :sleepy] do
      rx = eye_x - @eye_r
      ry = eye_y - @eye_r
      rw = @eye_r * 2 + 4
      rh = @eye_r + 2

      with :ok <- maybe_happy_eye_inner_circle(port, face.expr, eye_x, eye_y, target),
           :ok <-
             AtomLGFX.fill_rect(
               port,
               rx,
               if(face.expr == :happy, do: ry + @eye_r, else: ry),
               rw,
               rh,
               @col_bg,
               target
             ) do
        :ok
      end
    else
      :ok
    end
  end

  defp maybe_happy_eye_inner_circle(_port, expr, _eye_x, _eye_y, _target) when expr != :happy,
    do: :ok

  defp maybe_happy_eye_inner_circle(port, :happy, eye_x, eye_y, target) do
    AtomLGFX.fill_circle(port, eye_x, eye_y, trunc(@eye_r / 1.5), @col_bg, target)
  end

  defp draw_mouth(port, face, cx, cy) do
    open_ratio = face.mouth_open
    h = @mouth_min_h + trunc((@mouth_max_h - @mouth_min_h) * open_ratio)
    w = @mouth_min_w + trunc((@mouth_max_w - @mouth_min_w) * (1.0 - open_ratio))
    x = cx - div(w, 2)
    y = cy - div(h, 2) + trunc(face.breath * 2)

    AtomLGFX.fill_rect(port, x, y, w, h, @col_pr, face.sprite_target)
  end

  defp maybe_draw_eyebrows(_port, _face, _by) when @brow_h <= 0, do: :ok

  defp maybe_draw_eyebrows(port, face, by) do
    with :ok <- draw_eyebrow(port, face, @brow_r_x, @brow_r_y + by, false),
         :ok <- draw_eyebrow(port, face, @brow_l_x, @brow_l_y + by, true) do
      :ok
    end
  end

  defp draw_eyebrow(port, face, x, y, is_left) do
    if @brow_w == 0 or @brow_h == 0 do
      :ok
    else
      if face.expr in [:angry, :sad] do
        a = if(is_left != (face.expr == :sad), do: -1, else: 1)
        dx = a * 3
        dy = a * 5
        x1 = x - div(@brow_w, 2)
        x2 = x1 - dx
        x4 = x + div(@brow_w, 2)
        x3 = x4 + dx
        y1 = y - div(@brow_h, 2) - dy
        y2 = y + div(@brow_h, 2) - dy
        y3 = y - div(@brow_h, 2) + dy
        y4 = y + div(@brow_h, 2) + dy

        with :ok <-
               AtomLGFX.fill_triangle(port, x1, y1, x2, y2, x3, y3, @col_pr, face.sprite_target),
             :ok <-
               AtomLGFX.fill_triangle(port, x2, y2, x3, y3, x4, y4, @col_pr, face.sprite_target) do
          :ok
        end
      else
        bx = x - div(@brow_w, 2)
        by = y - div(@brow_h, 2)

        AtomLGFX.fill_rect(
          port,
          bx,
          if(face.expr == :happy, do: by - 5, else: by),
          @brow_w,
          @brow_h,
          @col_pr,
          face.sprite_target
        )
      end
    end
  end

  defp draw_effect(port, face, offset) do
    case face.expr do
      :doubt ->
        draw_sweat_mark(port, face.sprite_target, 290, 110, 7, -offset)

      :angry ->
        draw_anger_mark(port, face.sprite_target, 280, 50, 12, offset)

      :happy ->
        draw_heart_mark(port, face.sprite_target, 280, 50, 12, offset)

      :sad ->
        draw_chill_mark(port, face.sprite_target, 270, 0, 30, offset)

      :sleepy ->
        with :ok <- draw_bubble_mark(port, face.sprite_target, 290, 40, 10, offset),
             :ok <- draw_bubble_mark(port, face.sprite_target, 270, 52, 6, -offset) do
          :ok
        end

      :neutral ->
        :ok
    end
  end

  defp draw_sweat_mark(port, target, x, y, r, offset) do
    y1 = y + trunc(5 * offset)
    r1 = r + trunc(r * 0.2 * offset)

    if r1 < 1 do
      :ok
    else
      a = trunc(:math.sqrt(3.0) * r1 / 2.0)

      with :ok <- AtomLGFX.fill_circle(port, x, y1, r1, @col_sweat, target),
           :ok <-
             AtomLGFX.fill_triangle(
               port,
               x,
               y1 - r1 * 2,
               x - a,
               y1 - div(r1, 2),
               x + a,
               y1 - div(r1, 2),
               @col_sweat,
               target
             ) do
        :ok
      end
    end
  end

  defp draw_anger_mark(port, target, x, y, r, offset) do
    r1 = r + abs(trunc(r * 0.4 * offset))

    with :ok <-
           AtomLGFX.fill_rect(
             port,
             x - div(r1, 3),
             y - r1,
             div(r1 * 2, 3),
             r1 * 2,
             @col_pr,
             target
           ),
         :ok <-
           AtomLGFX.fill_rect(
             port,
             x - r1,
             y - div(r1, 3),
             r1 * 2,
             div(r1 * 2, 3),
             @col_pr,
             target
           ),
         :ok <-
           AtomLGFX.fill_rect(
             port,
             x - div(r1, 3) + 2,
             y - r1,
             max(div(r1 * 2, 3) - 4, 0),
             r1 * 2,
             @col_bg,
             target
           ),
         :ok <-
           AtomLGFX.fill_rect(
             port,
             x - r1,
             y - div(r1, 3) + 2,
             r1 * 2,
             max(div(r1 * 2, 3) - 4, 0),
             @col_bg,
             target
           ) do
      :ok
    end
  end

  defp draw_heart_mark(port, target, x, y, r, offset) do
    r1 = r + trunc(r * 0.4 * offset)

    if r1 < 2 do
      :ok
    else
      a = :math.sqrt(2.0) * r1 / 4.0
      a_i = trunc(a)

      with :ok <- AtomLGFX.fill_circle(port, x - div(r1, 2), y, div(r1, 2), @col_heart, target),
           :ok <- AtomLGFX.fill_circle(port, x + div(r1, 2), y, div(r1, 2), @col_heart, target),
           :ok <-
             AtomLGFX.fill_triangle(
               port,
               x,
               y,
               x - div(r1, 2) - a_i,
               y + a_i,
               x + div(r1, 2) + a_i,
               y + a_i,
               @col_heart,
               target
             ),
           :ok <-
             AtomLGFX.fill_triangle(
               port,
               x,
               y + div(r1, 2) + trunc(2 * a),
               x - div(r1, 2) - a_i,
               y + a_i,
               x + div(r1, 2) + a_i,
               y + a_i,
               @col_heart,
               target
             ) do
        :ok
      end
    end
  end

  defp draw_chill_mark(port, target, x, y, r, offset) do
    h = r + abs(trunc(r * 0.2 * offset))

    with :ok <- AtomLGFX.fill_rect(port, x - div(r, 2), y, 3, div(h, 2), @col_pr, target),
         :ok <- AtomLGFX.fill_rect(port, x, y, 3, div(h * 3, 4), @col_pr, target),
         :ok <- AtomLGFX.fill_rect(port, x + div(r, 2), y, 3, h, @col_pr, target) do
      :ok
    end
  end

  defp draw_bubble_mark(port, target, x, y, r, offset) do
    r1 = r + trunc(r * 0.2 * offset)

    if r1 < 1 do
      :ok
    else
      with :ok <- AtomLGFX.draw_circle(port, x, y, r1, @col_pr, target),
           :ok <-
             AtomLGFX.draw_circle(
               port,
               x - div(r1, 4),
               y - div(r1, 4),
               div(r1, 4),
               @col_pr,
               target
             ) do
        :ok
      end
    end
  end

  defp update_breath(face) do
    breath_count = rem(face.breath_count + 1, 100)
    breath = :math.sin(breath_count * 2.0 * :math.pi() / 100.0)
    %{face | breath_count: breath_count, breath: breath}
  end

  defp update_blink(face, now_ms) do
    if now_ms - face.last_blink_ms > face.blink_interval do
      {next_seed, interval_rand} = rand_mod(face.rand_seed, 20)

      if face.eye_open do
        %{
          face
          | eye_open_l: 0.0,
            eye_open_r: 0.0,
            blink_interval: 300 + 10 * interval_rand,
            eye_open: false,
            last_blink_ms: now_ms,
            rand_seed: next_seed
        }
      else
        %{
          face
          | eye_open_l: 1.0,
            eye_open_r: 1.0,
            blink_interval: 2_500 + 100 * interval_rand,
            eye_open: true,
            last_blink_ms: now_ms,
            rand_seed: next_seed
        }
      end
    else
      face
    end
  end

  defp update_saccade(face, now_ms) do
    face =
      if face.external_gaze do
        if now_ms - face.external_gaze_ms < @external_gaze_hold_ms do
          face
        else
          %{face | external_gaze: false}
        end
      else
        face
      end

    if face.external_gaze do
      face
    else
      if now_ms - face.last_saccade_ms > face.saccade_interval do
        {seed1, gaze_v_rand} = rand_mod(face.rand_seed, 200)
        {seed2, gaze_h_rand} = rand_mod(seed1, 200)
        {seed3, interval_rand} = rand_mod(seed2, 20)

        %{
          face
          | gaze_v: gaze_v_rand / 100.0 - 1.0,
            gaze_h: gaze_h_rand / 100.0 - 1.0,
            saccade_interval: 500 + 100 * interval_rand,
            last_saccade_ms: now_ms,
            rand_seed: seed3
        }
      else
        face
      end
    end
  end

  defp rand_mod(seed, modulus) when is_integer(seed) and is_integer(modulus) and modulus > 0 do
    next_seed = lcg_next(seed)
    {next_seed, rem(next_seed, modulus)}
  end

  defp lcg_next(seed) do
    seed * 1_103_515_245 + 12_345 &&& 0x7FFFFFFF
  end

  defp monotonic_ms do
    :erlang.monotonic_time(:millisecond)
  end

  defp clamp(value, min_value, _max_value) when value < min_value, do: min_value
  defp clamp(value, _min_value, max_value) when value > max_value, do: max_value
  defp clamp(value, _min_value, _max_value), do: value
end
