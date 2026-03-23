# SPDX-FileCopyrightText: 2026 piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp do
  @moduledoc false

  alias SampleApp.Face

  @default_expression :neutral
  @expression_order [:neutral, :happy, :angry, :sad, :doubt, :sleepy]

  @frame_ms 33
  @expression_interval_ms 10_000

  @touch_center_x 240.0
  @touch_center_y 160.0

  @background 0x000080

  @sample_open_options [
    panel_driver: :ili9488,
    width: 320,
    height: 480,
    offset_rotation: 0,
    readable: false,
    invert: false,
    rgb_order: false,
    dlen_16bit: false,
    lcd_spi_host: :spi2_host,
    spi_sclk_gpio: 7,
    spi_mosi_gpio: 9,
    spi_miso_gpio: 8,
    lcd_cs_gpio: 43,
    lcd_dc_gpio: 3,
    lcd_rst_gpio: 2,
    touch_cs_gpio: 44,
    touch_irq_gpio: -1,
    touch_spi_host: :spi2_host,
    touch_spi_freq_hz: 1_000_000,
    lcd_spi_mode: 0,
    lcd_bus_shared: true,
    touch_bus_shared: true
  ]

  def start do
    start([])
  end

  def start(open_options) when is_list(open_options) do
    effective_open_options = @sample_open_options ++ open_options
    {:ok, port} = AtomLGFX.open(effective_open_options)

    log_info("AtomLGFX opened open_options=#{inspect(effective_open_options)}")

    try do
      run(port)
    after
      safe_close_port(port)
    end
  end

  defp run(port) do
    with :ok <- step("ping", AtomLGFX.ping(port)),
         :ok <- step("init", AtomLGFX.init(port)),
         :ok <- step("set_rotation", AtomLGFX.set_rotation(port, 1)),
         :ok <- step("set_swap_bytes_lcd", AtomLGFX.set_swap_bytes(port, true, 0)),
         :ok <- step("fill_screen", AtomLGFX.fill_screen(port, @background)) do
      face0 =
        Face.new()
        |> Face.set_expression(@default_expression)

      case Face.init(face0, port) do
        {:ok, face} ->
          log_info("Stack-chan started")

          initial_state = %{
            face: face,
            expression_index: 0,
            last_expression_change_ms: monotonic_ms()
          }

          loop(port, initial_state)

        {:error, reason} = err ->
          log_failure("face_init failed", reason)
          err
      end
    end
  end

  defp loop(port, state) do
    now_ms = monotonic_ms()

    next_state =
      state
      |> handle_touch(port)
      |> maybe_rotate_expression(now_ms)
      |> update_face(now_ms)

    case Face.draw(next_state.face, port) do
      :ok ->
        sleep_frame()
        loop(port, next_state)

      {:error, reason} = err ->
        log_failure("face_draw failed", reason)
        err
    end
  end

  defp handle_touch(state, port) do
    case AtomLGFX.get_touch(port) do
      {:ok, {touch_x, touch_y, _size}} ->
        gaze_h = clamp((touch_x - @touch_center_x) / @touch_center_x, -1.0, 1.0)
        gaze_v = clamp((touch_y - @touch_center_y) / @touch_center_y, -1.0, 1.0)

        updated_face =
          state.face
          |> Face.set_gaze(gaze_h, gaze_v)
          |> Face.set_mouth_open(0.7)

        %{state | face: updated_face}

      {:ok, :none} ->
        %{state | face: Face.set_mouth_open(state.face, 0.0)}

      {:error, reason} ->
        log_failure("get_touch failed", reason)
        state
    end
  end

  defp maybe_rotate_expression(state, now_ms) do
    if now_ms - state.last_expression_change_ms > @expression_interval_ms do
      next_index = rem(state.expression_index + 1, length(@expression_order))
      next_expression = Enum.at(@expression_order, next_index)

      log_info("Expression: #{expression_name(next_expression)}")

      %{
        state
        | expression_index: next_index,
          last_expression_change_ms: now_ms,
          face: Face.set_expression(state.face, next_expression)
      }
    else
      state
    end
  end

  defp update_face(state, now_ms) do
    %{state | face: Face.update(state.face, now_ms)}
  end

  defp monotonic_ms do
    :erlang.monotonic_time(:millisecond)
  end

  defp sleep_frame do
    receive do
    after
      @frame_ms -> :ok
    end
  end

  defp clamp(value, min_value, _max_value) when value < min_value, do: min_value
  defp clamp(value, _min_value, max_value) when value > max_value, do: max_value
  defp clamp(value, _min_value, _max_value), do: value

  defp expression_name(:neutral), do: "Neutral"
  defp expression_name(:happy), do: "Happy"
  defp expression_name(:angry), do: "Angry"
  defp expression_name(:sad), do: "Sad"
  defp expression_name(:doubt), do: "Doubt"
  defp expression_name(:sleepy), do: "Sleepy"

  defp safe_close_port(port) do
    case AtomLGFX.close(port) do
      :ok ->
        log_info("AtomLGFX closed")
        :ok

      {:error, reason} ->
        log_failure("AtomLGFX close failed", reason)
        :ok
    end
  end

  defp step(label, :ok) do
    log_info("#{label} ok")
    :ok
  end

  defp step(label, {:error, reason} = err) do
    log_failure("#{label} failed", reason)
    err
  end

  defp log_info(message) when is_binary(message) do
    IO.puts(message)
  end

  defp log_failure(prefix, reason) when is_binary(prefix) do
    IO.puts("#{prefix}: #{AtomLGFX.format_error(reason)}")
  end
end
