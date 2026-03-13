# SPDX-FileCopyrightText: 2026 piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp.HelloScene do
  @title "Hello, AtomVM"
  @line1 "ESP32-S3 + Elixir"
  @line2 "Touch the screen"
  @line3 "Edit this file and flash again"

  @swap_red_blue false

  def start_link(args, opts) do
    :avm_scene.start_link(__MODULE__, args, opts)
  end

  def init(args) do
    state = %{
      width: Keyword.fetch!(args, :width),
      height: Keyword.fetch!(args, :height),
      touch_point: nil
    }

    send(self(), :render)
    {:ok, state}
  end

  def handle_info(:render, state) do
    {:noreply, state, [{:push, render_items(state)}]}
  end

  def handle_info({:touch, x, y}, state) do
    state = %{state | touch_point: {x, y}}
    {:noreply, state, [{:push, render_items(state)}]}
  end

  def handle_input({:touch, x, y}, _ts, _input_server_pid, state) do
    state = %{state | touch_point: {x, y}}
    {:noreply, state, [{:push, render_items(state)}]}
  end

  defp render_items(%{width: width, height: height, touch_point: touch_point}) do
    title_x = 36
    title_y = 40
    line1_y = 96
    line2_y = 122
    line3_y = 148
    line4_y = 200

    border_items = border_items(width, height, panel_color(0xD1D5DB))
    touch_items = touch_marker_items(touch_point, width, height)
    touch_text = touch_text(touch_point)

    [
      {:text, title_x, title_y, :default16px, panel_color(0xFFFFFF), :transparent, @title},
      {:text, title_x, line1_y, :default16px, panel_color(0x111827), :transparent, @line1},
      {:text, title_x, line2_y, :default16px, panel_color(0x111827), :transparent, @line2},
      {:text, title_x, line3_y, :default16px, panel_color(0x6B7280), :transparent, @line3},
      {:text, title_x, line4_y, :default16px, panel_color(0xB91C1C), :transparent, touch_text}
    ] ++
      touch_items ++
      border_items ++
      [
        {:rect, 24, 24, width - 48, 36, panel_color(0x2563EB)},
        {:rect, 0, 0, width, height, panel_color(0xFFFFFF)}
      ]
  end

  defp touch_marker_items(nil, _width, _height), do: []

  defp touch_marker_items({x, y}, width, height) do
    x = clamp_i(x, 3, width - 4)
    y = clamp_i(y, 3, height - 4)

    [
      {:rect, x - 3, y - 3, 7, 7, panel_color(0xFF0000)}
    ]
  end

  defp touch_text(nil), do: "touch: -"
  defp touch_text({x, y}), do: "touch: {#{x}, #{y}}"

  defp border_items(width, height, color) do
    x = 16
    y = 16
    w = width - 32
    h = height - 32
    t = 2

    [
      {:rect, x, y, w, t, color},
      {:rect, x, y + h - t, w, t, color},
      {:rect, x, y, t, h, color},
      {:rect, x + w - t, y, t, h, color}
    ]
  end

  defp panel_color(rgb24) when rgb24 in 0..0xFFFFFF do
    if @swap_red_blue do
      <<r::8, g::8, b::8>> = <<rgb24::24>>
      b * 0x10000 + g * 0x100 + r
    else
      rgb24
    end
  end

  defp clamp_i(v, lo, _hi) when v < lo, do: lo
  defp clamp_i(v, _lo, hi) when v > hi, do: hi
  defp clamp_i(v, _lo, _hi), do: v
end
