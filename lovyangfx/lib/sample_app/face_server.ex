# SPDX-FileCopyrightText: 2026 piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp.FaceServer do
  @moduledoc false

  alias SampleApp.Face

  @default_expression :neutral
  @expression_order [:neutral, :happy, :angry, :sad, :doubt, :sleepy]

  @frame_ms 50
  @expression_interval_ms 10_000

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

  def start_link(open_options \\ []) do
    :gen_server.start_link({:local, __MODULE__}, __MODULE__, open_options, [])
  end

  def set_expression(expression) do
    :gen_server.call(__MODULE__, {:set_expression, expression})
  end

  def set_gaze(horizontal, vertical) do
    :gen_server.call(__MODULE__, {:set_gaze, horizontal, vertical})
  end

  def set_mouth_open(ratio) do
    :gen_server.call(__MODULE__, {:set_mouth_open, ratio})
  end

  def get_face_state do
    :gen_server.call(__MODULE__, :get_face_state)
  end

  def init(open_options) do
    effective_open_options = @sample_open_options ++ open_options
    log_info("about to open AtomLGFX open_options=#{inspect(effective_open_options)}")

    case AtomLGFX.open(effective_open_options) do
      {:ok, port} ->
        log_info("AtomLGFX opened open_options=#{inspect(effective_open_options)}")

        case initialize_face(port) do
          {:ok, face, display_width, display_height, touch_enabled} ->
            log_info("Stack-chan started display_size=#{display_width}x#{display_height}")
            schedule_tick()

            {:ok,
             %{
               port: port,
               face: face,
               display_width: display_width,
               display_height: display_height,
               touch_enabled: touch_enabled,
               expression_index: expression_index(@default_expression),
               last_expression_change_ms: monotonic_ms(),
               remote_mouth_open: nil
             }}

          {:error, reason} ->
            safe_close_port(port)
            {:stop, reason}
        end

      {:error, reason} ->
        log_failure("AtomLGFX open failed", reason)
        {:stop, {:atomlgfx_open_failed, reason}}
    end
  end

  def handle_call({:set_expression, expression}, _from, state) do
    if expression in @expression_order do
      updated_face = Face.set_expression(state.face, expression)

      {:reply, :ok,
       %{
         state
         | face: updated_face,
           expression_index: expression_index(expression),
           last_expression_change_ms: monotonic_ms()
       }}
    else
      {:reply, {:error, {:unsupported_expression, expression}}, state}
    end
  end

  def handle_call({:set_gaze, horizontal, vertical}, _from, state)
      when is_number(horizontal) and is_number(vertical) do
    updated_face = Face.set_gaze(state.face, horizontal, vertical)
    {:reply, :ok, %{state | face: updated_face}}
  end

  def handle_call({:set_gaze, horizontal, vertical}, _from, state) do
    {:reply, {:error, {:invalid_gaze, {horizontal, vertical}}}, state}
  end

  def handle_call({:set_mouth_open, ratio}, _from, state) when is_number(ratio) do
    normalized_ratio = clamp(ratio * 1.0, 0.0, 1.0)
    updated_face = Face.set_mouth_open(state.face, normalized_ratio)
    {:reply, :ok, %{state | face: updated_face, remote_mouth_open: normalized_ratio}}
  end

  def handle_call({:set_mouth_open, ratio}, _from, state) do
    {:reply, {:error, {:invalid_mouth_open, ratio}}, state}
  end

  def handle_call(:get_face_state, _from, state) do
    face = state.face

    {:reply,
     %{
       expression: face.expr,
       gaze_h: face.gaze_h,
       gaze_v: face.gaze_v,
       mouth_open: face.mouth_open,
       remote_mouth_open: state.remote_mouth_open,
       display_width: state.display_width,
       display_height: state.display_height,
       touch_enabled: state.touch_enabled
     }, state}
  end

  def handle_info(:tick, state) do
    now_ms = monotonic_ms()

    next_state =
      state
      |> handle_touch()
      |> maybe_rotate_expression(now_ms)
      |> update_face(now_ms)

    case Face.draw(next_state.face, next_state.port) do
      :ok ->
        schedule_tick()
        {:noreply, next_state}

      {:error, reason} ->
        log_failure("face_draw failed", reason)
        {:stop, {:face_draw_failed, reason}, next_state}
    end
  end

  def terminate(_reason, state) do
    safe_close_port(state.port)
    :ok
  end

  defp initialize_face(port) do
    with :ok <- step("ping", AtomLGFX.ping(port)),
         :ok <- step("init", AtomLGFX.init(port)),
         :ok <- step("set_rotation", AtomLGFX.set_rotation(port, 1)),
         :ok <- step("set_swap_bytes_lcd", AtomLGFX.set_swap_bytes(port, true, 0)),
         {:ok, display_width} <- step_value("width", AtomLGFX.width(port)),
         {:ok, display_height} <- step_value("height", AtomLGFX.height(port)) do
      touch_enabled = supports_touch(port)

      face0 =
        Face.new(display_width: display_width, display_height: display_height)
        |> Face.set_expression(@default_expression)

      case Face.init(face0, port) do
        {:ok, face} -> {:ok, face, display_width, display_height, touch_enabled}

        {:error, reason} = err ->
          log_failure("face_init failed", reason)
          err
      end
    end
  end

  defp supports_touch(port) do
    case AtomLGFX.supports_touch?(port) do
      {:ok, true} -> true
      {:ok, false} -> false
      _other -> false
    end
  end

  defp handle_touch(%{touch_enabled: false} = state), do: state

  defp handle_touch(state) do
    touch_center_x = state.display_width / 2.0
    touch_center_y = state.display_height / 2.0

    case AtomLGFX.get_touch(state.port) do
      {:ok, {touch_x, touch_y, _size}} ->
        gaze_h = clamp((touch_x - touch_center_x) / touch_center_x, -1.0, 1.0)
        gaze_v = clamp((touch_y - touch_center_y) / touch_center_y, -1.0, 1.0)

        updated_face =
          state.face
          |> Face.set_gaze(gaze_h, gaze_v)
          |> Face.set_mouth_open(0.7)

        %{state | face: updated_face}

      {:ok, :none} ->
        %{state | face: Face.set_mouth_open(state.face, effective_mouth_open(state))}

      {:error, _reason} ->
        state
    end
  end

  defp effective_mouth_open(%{remote_mouth_open: nil}), do: 0.0
  defp effective_mouth_open(%{remote_mouth_open: remote_mouth_open}), do: remote_mouth_open

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

  defp schedule_tick do
    Process.send_after(self(), :tick, @frame_ms)
  end

  defp expression_index(:neutral), do: 0
  defp expression_index(:happy), do: 1
  defp expression_index(:angry), do: 2
  defp expression_index(:sad), do: 3
  defp expression_index(:doubt), do: 4
  defp expression_index(:sleepy), do: 5

  defp monotonic_ms do
    :erlang.monotonic_time(:millisecond)
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

  defp step_value(label, {:ok, value}) do
    log_info("#{label} ok value=#{inspect(value)}")
    {:ok, value}
  end

  defp step_value(label, {:error, reason} = err) do
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
