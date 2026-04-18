# SPDX-FileCopyrightText: 2026 piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp.Provision do
  @moduledoc false

  @wifi_ssid System.get_env("ATOMVM_WIFI_SSID")
  @wifi_passphrase System.get_env("ATOMVM_WIFI_PASSPHRASE")
  @wifi_force System.get_env("ATOMVM_WIFI_FORCE")

  def maybe_provision do
    if present?(@wifi_ssid) do
      if wifi_force?() do
        write_credentials_to_nvs(@wifi_ssid, @wifi_passphrase, reason: "forced overwrite")
      else
        write_credentials_to_nvs_if_missing(@wifi_ssid, @wifi_passphrase)
      end
    end

    :ok
  end

  defp write_credentials_to_nvs_if_missing(ssid, passphrase) do
    case SampleApp.NVS.get_binary(:wifi_ssid) do
      nil -> write_credentials_to_nvs(ssid, passphrase, reason: "first-time provision")
      _value -> :ok
    end
  end

  defp write_credentials_to_nvs(ssid, passphrase, reason: reason) do
    :ok = SampleApp.NVS.put_binary(:wifi_ssid, ssid)

    if present?(passphrase) do
      :ok = SampleApp.NVS.put_binary(:wifi_passphrase, passphrase)
    else
      if wifi_force?() do
        :ok = SampleApp.NVS.delete(:wifi_passphrase)
      end
    end

    IO.puts("wifi: #{reason} (stored Wi-Fi credentials in NVS)")
    :ok
  end

  defp wifi_force?, do: present?(@wifi_force)

  defp present?(value) when is_binary(value), do: byte_size(value) > 0
  defp present?(_value), do: false
end
