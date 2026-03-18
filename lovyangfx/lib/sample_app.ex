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
    port = LGFXPort.open(@sample_open_options)

    log_info("LGFXPort opened open_options=#{inspect(@sample_open_options)}")

    try do
      with :ok <- step("ping", LGFXPort.ping(port)),
           :ok <- step("init", LGFXPort.init(port)),
           :ok <- step("display(init)", LGFXPort.display(port)),
           :ok <- step("set_rotation", LGFXPort.set_rotation(port, @rotation)),
           :ok <- step("display(rotation)", LGFXPort.display(port)),
           {:ok, w, h} <- get_wh(port),
           :ok <- step("fill_screen", LGFXPort.fill_screen(port, @bg)),
           :ok <- MovingIcons.run(port, w, h) do
        :ok
      else
        {:error, reason} = err ->
          log_failure("sample_app failed", reason)
          err
      end
    after
      safe_close_port(port)
    end
  end

  defp get_wh(port) do
    with {:ok, w} <- LGFXPort.width(port, 0),
         {:ok, h} <- LGFXPort.height(port, 0) do
      log_info("viewport=#{w}x#{h}")
      {:ok, w, h}
    end
  end

  defp safe_close_port(port) do
    case LGFXPort.close(port) do
      :ok ->
        log_info("LGFXPort closed")
        :ok

      {:error, reason} ->
        log_failure("LGFXPort close failed", reason)
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
    IO.puts("#{prefix}: #{LGFXPort.format_error(reason)}")
  end
end
