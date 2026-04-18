# SPDX-FileCopyrightText: 2026 piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp do
  @moduledoc false

  def start do
    start([])
  end

  def start(open_options) when is_list(open_options) do
    SampleApp.Provision.maybe_provision()

    {:ok, _} = SampleApp.DistErl.start_link()
    {:ok, _} = SampleApp.FaceServer.start_link(open_options)
    maybe_start_wifi()

    Process.sleep(:infinity)
  end

  defp maybe_start_wifi do
    case SampleApp.WiFi.start_link() do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        IO.puts("wifi: not started #{inspect(reason)}")
        :ok
    end
  end
end
