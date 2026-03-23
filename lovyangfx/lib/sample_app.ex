# SPDX-FileCopyrightText: 2026 Masatoshi Nishiguchi, piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp do
  @moduledoc false

  alias SampleApp.MovingIcons

  @sample_open_options [
    lcd_spi_host: :spi2_host,
    touch_spi_host: :spi2_host,
    lcd_bus_shared: true,
    touch_bus_shared: true,
    spi_sclk_gpio: 7,
    spi_mosi_gpio: 9,
    spi_miso_gpio: 8,
    lcd_cs_gpio: 43,
    lcd_dc_gpio: 3,
    lcd_rst_gpio: 2,
    touch_cs_gpio: 44,
    touch_irq_gpio: -1
  ]

  @rotation 1
  @bg 0x000000

  def start do
    {:ok, port} = AtomLGFX.open(@sample_open_options)

    log_info("AtomLGFX opened with open_options=#{inspect(@sample_open_options)}")

    try do
      with :ok <- step("ping", AtomLGFX.ping(port)),
           :ok <- step("init", AtomLGFX.init(port)),
           :ok <- step("display(init)", AtomLGFX.display(port)),
           :ok <- step("set_rotation", AtomLGFX.set_rotation(port, @rotation)),
           :ok <- step("display(rotation)", AtomLGFX.display(port)),
           {:ok, w, h} <- get_wh(port),
           :ok <- step("fill_screen", AtomLGFX.fill_screen(port, @bg)),
           :ok <- MovingIcons.run(port, w, h) do
        :ok
      else
        {:error, reason} = err ->
          log_failure("sample_app failed", reason)
          err
      end
    after
      safe_close_device(port)
    end
  end

  defp get_wh(port) do
    with {:ok, w} <- AtomLGFX.width(port, 0),
         {:ok, h} <- AtomLGFX.height(port, 0) do
      log_info("viewport=#{w}x#{h}")
      {:ok, w, h}
    end
  end

  defp safe_close_device(port) do
    case AtomLGFX.close(port) do
      :ok ->
        log_info("AtomLGFX device closed")
        :ok

      {:error, reason} ->
        log_failure("AtomLGFX device close failed", reason)
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

  defp log_info(message) when is_binary(message), do: IO.puts(message)

  defp log_failure(prefix, reason) when is_binary(prefix) do
    IO.puts("#{prefix}: #{AtomLGFX.format_error(reason)}")
  end
end
