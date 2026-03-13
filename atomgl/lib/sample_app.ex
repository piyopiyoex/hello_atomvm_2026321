# SPDX-FileCopyrightText: 2026 Masatoshi Nishiguchi, piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp do
  @compile {:no_warn_undefined, :spi}

  @scene SampleApp.HelloScene

  @spi_config [
    bus_config: [sclk: 7, miso: 8, mosi: 9],
    device_config: [
      spi_dev_lcd: [
        cs: 43,
        mode: 0,
        clock_speed_hz: 20_000_000,
        command_len_bits: 0,
        address_len_bits: 0
      ],
      spi_dev_touch: [
        cs: 44,
        mode: 0,
        clock_speed_hz: 1_000_000,
        command_len_bits: 0,
        address_len_bits: 0
      ]
    ]
  ]

  @display_width 480
  @display_height 320
  @display_rotation 1

  @display_port_options [
    width: @display_width,
    height: @display_height,
    compatible: "ilitek,ili9488",
    rotation: @display_rotation,
    cs: 43,
    dc: 3,
    reset: 2
  ]

  @touch_options [
    device: :spi_dev_touch,
    poll_ms: 25,
    width: @display_width,
    height: @display_height,
    rotation: @display_rotation,
    raw_x_min: 80,
    raw_x_max: 1950,
    raw_y_min: 80,
    raw_y_max: 1950,
    swap_xy: false,
    invert_x: true,
    invert_y: false
  ]

  @scene_args [
    width: @display_width,
    height: @display_height
  ]

  def start do
    spi_host = :spi.open(@spi_config)

    display_port =
      :erlang.open_port(
        {:spawn, "display"},
        @display_port_options ++ [spi_host: spi_host]
      )

    {:ok, input_server_pid} =
      SampleApp.TouchInput.start_link([spi: spi_host] ++ @touch_options)

    {:ok, _scene_pid} =
      @scene.start_link(@scene_args,
        display_server: {:port, display_port},
        input_server: input_server_pid
      )

    Process.sleep(:infinity)
  end
end
