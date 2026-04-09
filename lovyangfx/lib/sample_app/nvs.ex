# SPDX-FileCopyrightText: 2026 piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp.NVS do
  @moduledoc false

  @compile {:no_warn_undefined, :esp}

  @namespace :stackchan_face

  def get_binary(key) when is_atom(key) do
    case :esp.nvs_get_binary(@namespace, key) do
      :undefined -> nil
      <<>> -> nil
      value when is_binary(value) -> value
    end
  end

  def put_binary(key, value) when is_atom(key) and is_binary(value) do
    :esp.nvs_put_binary(@namespace, key, value)
  end

  def delete(key) when is_atom(key) do
    :esp.nvs_erase_key(@namespace, key)
  end

  def delete_all do
    :esp.nvs_erase_all(@namespace)
  end
end
