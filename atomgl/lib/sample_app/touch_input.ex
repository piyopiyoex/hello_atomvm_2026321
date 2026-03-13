# SPDX-FileCopyrightText: 2026 Masatoshi Nishiguchi, piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp.TouchInput do
  @compile {:no_warn_undefined, :spi}

  @xpt2046_cmd_read_x 0xD0
  @xpt2046_cmd_read_y 0x90

  def start_link(opts) do
    pid = spawn_link(__MODULE__, :init, [opts])
    {:ok, pid}
  end

  def init(opts) do
    state = %{
      spi: Keyword.fetch!(opts, :spi),
      device: Keyword.fetch!(opts, :device),
      poll_ms: Keyword.get(opts, :poll_ms, 25),
      width: Keyword.fetch!(opts, :width),
      height: Keyword.fetch!(opts, :height),
      rotation: Keyword.get(opts, :rotation, 0),
      raw_x_min: Keyword.get(opts, :raw_x_min, 80),
      raw_x_max: Keyword.get(opts, :raw_x_max, 1950),
      raw_y_min: Keyword.get(opts, :raw_y_min, 80),
      raw_y_max: Keyword.get(opts, :raw_y_max, 1950),
      swap_xy: Keyword.get(opts, :swap_xy, false),
      invert_x: Keyword.get(opts, :invert_x, false),
      invert_y: Keyword.get(opts, :invert_y, false),
      subscribers: MapSet.new()
    }

    loop(state)
  end

  defp loop(state) do
    receive do
      {:"$call", from, request} ->
        loop(handle_call(from, request, state))

      {:"$gen_call", from, request} ->
        loop(handle_call(from, request, state))
    after
      state.poll_ms ->
        loop(poll_and_emit(state))
    end
  end

  defp handle_call(from, :subscribe_input, state) do
    reply(from, :ok)
    subscribe(from, state)
  end

  defp handle_call(from, {:subscribe_input}, state) do
    reply(from, :ok)
    subscribe(from, state)
  end

  defp handle_call(from, {:subscribe_input, pid}, state) when is_pid(pid) do
    reply(from, :ok)
    %{state | subscribers: MapSet.put(state.subscribers, pid)}
  end

  defp handle_call(from, _request, state) do
    reply(from, :ok)
    state
  end

  defp subscribe({pid, _ref}, state) when is_pid(pid) do
    %{state | subscribers: MapSet.put(state.subscribers, pid)}
  end

  defp reply({pid, ref}, value), do: send(pid, {ref, value})

  defp poll_and_emit(state) do
    {raw_x0, raw_y0} = read_raw_xy(state)

    pressed? =
      in_range?(raw_x0, state.raw_x_min, state.raw_x_max) and
        in_range?(raw_y0, state.raw_y_min, state.raw_y_max)

    if pressed? do
      {x, y} = to_screen_point(raw_x0, raw_y0, state)
      broadcast(state.subscribers, {:touch, x, y})
    end

    state
  end

  defp broadcast(subscribers, event) do
    Enum.each(subscribers, fn pid -> send(pid, event) end)
  end

  defp read_raw_xy(state) do
    rx = read12(state, @xpt2046_cmd_read_x)
    ry = read12(state, @xpt2046_cmd_read_y)

    if state.swap_xy, do: {ry, rx}, else: {rx, ry}
  end

  defp read12(state, cmd) do
    case :spi.write_read(state.spi, state.device, %{write_data: <<cmd, 0x00, 0x00>>}) do
      {:ok, <<_::8, hi::8, lo::8>>} ->
        div(hi * 256 + lo, 16)

      _ ->
        0
    end
  end

  defp to_screen_point(raw_x, raw_y, state) do
    {native_width, native_height} =
      if state.rotation in [1, 3] do
        {state.height, state.width}
      else
        {state.width, state.height}
      end

    x0 = scale(raw_x, state.raw_x_min, state.raw_x_max, native_width - 1)
    y0 = scale(raw_y, state.raw_y_min, state.raw_y_max, native_height - 1)

    x0 = if state.invert_x, do: native_width - 1 - x0, else: x0
    y0 = if state.invert_y, do: native_height - 1 - y0, else: y0

    apply_rotation({x0, y0}, state.rotation, state.width, state.height)
  end

  defp apply_rotation({x, y}, 0, _w, _h), do: {x, y}
  defp apply_rotation({x, y}, 1, w, _h), do: {w - 1 - y, x}
  defp apply_rotation({x, y}, 2, w, h), do: {w - 1 - x, h - 1 - y}
  defp apply_rotation({x, y}, 3, _w, h), do: {y, h - 1 - x}

  defp scale(v, min_v, max_v, max_out) do
    v = clamp(v, min_v, max_v)
    range = max_v - min_v
    if range <= 0, do: 0, else: div((v - min_v) * max_out, range)
  end

  defp clamp(v, min_v, _max_v) when v < min_v, do: min_v
  defp clamp(v, _min_v, max_v) when v > max_v, do: max_v
  defp clamp(v, _min_v, _max_v), do: v

  defp in_range?(v, min_v, max_v), do: v >= min_v and v <= max_v
end
