# SPDX-FileCopyrightText: 2026 Masatoshi Nishiguchi, piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp do
  @compile {:no_warn_undefined, :gpio}
  @pin 21

  def start() do
    :gpio.set_pin_mode(@pin, :output)
    loop(@pin, :low)
  end

  defp loop(pin, level) do
    IO.puts("Setting pin #{pin} #{level}")
    :gpio.digital_write(pin, level)
    Process.sleep(1000)
    loop(pin, toggle(level))
  end

  defp toggle(:high), do: :low
  defp toggle(:low), do: :high
end
