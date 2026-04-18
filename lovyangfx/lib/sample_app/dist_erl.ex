# SPDX-FileCopyrightText: 2026 piyopiyo.ex members
#
# SPDX-License-Identifier: Apache-2.0

defmodule SampleApp.DistErl do
  @moduledoc false

  @compile {:no_warn_undefined, :epmd}
  @compile {:no_warn_undefined, :net_kernel}

  @cookie <<"AtomVM">>
  @listen_port 9100
  @node_base "piyopiyo"

  def start_link(opts \\ []) do
    :gen_server.start_link({:local, __MODULE__}, __MODULE__, :ok, opts)
  end

  def maybe_start(ip_info) do
    :gen_server.cast(__MODULE__, {:maybe_start, ip_info})
  end

  def hello do
    IO.puts("disterl: hello/0 invoked")
    {:hello_from_atomvm, :erlang.node()}
  end

  def set_expression(expression) do
    SampleApp.FaceServer.set_expression(expression)
  end

  def set_gaze(horizontal, vertical) do
    SampleApp.FaceServer.set_gaze(horizontal, vertical)
  end

  def set_mouth_open(ratio) do
    SampleApp.FaceServer.set_mouth_open(ratio)
  end

  def get_face_state do
    SampleApp.FaceServer.get_face_state()
  end

  def init(:ok) do
    {:ok, %{started?: false, node_name: nil}}
  end

  def handle_cast({:maybe_start, {address, _netmask, _gateway}}, %{started?: false} = state) do
    case start_distribution(address) do
      {:ok, node_name} ->
        IO.puts("disterl: started")
        IO.puts("disterl: node #{inspect(node_name)}")
        IO.puts("disterl: cookie #{inspect(@cookie)}")
        IO.puts("disterl: registered process :disterl")
        {:noreply, %{state | started?: true, node_name: node_name}}

      {:error, reason} ->
        IO.puts("disterl: failed to start #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:maybe_start, _ip_info}, state) do
    {:noreply, state}
  end

  def handle_info(:demo_message, state) do
    IO.puts("disterl: received :demo_message")
    {:noreply, state}
  end

  def handle_info(message, state) do
    IO.puts("disterl: received #{inspect(message)}")
    {:noreply, state}
  end

  defp start_distribution({a, b, c, d}) do
    node_name = :"#{@node_base}@#{a}.#{b}.#{c}.#{d}"

    with :ok <- ensure_epmd_started(),
         :ok <- ensure_net_kernel_started(node_name),
         :ok <- :net_kernel.set_cookie(@cookie),
         :ok <- ensure_registered(:disterl, self()) do
      {:ok, node_name}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_epmd_started do
    case :epmd.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      other -> {:error, {:epmd_start_failed, other}}
    end
  end

  defp ensure_net_kernel_started(node_name) do
    options = %{
      name_domain: :longnames,
      avm_dist_opts: %{
        listen_port_min: @listen_port,
        listen_port_max: @listen_port
      }
    }

    case :net_kernel.start(node_name, options) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      other -> {:error, {:net_kernel_start_failed, other}}
    end
  end

  defp ensure_registered(name, pid) do
    case Process.whereis(name) do
      nil ->
        true = :erlang.register(name, pid)
        :ok

      ^pid ->
        :ok

      other_pid ->
        {:error, {:already_registered, name, other_pid}}
    end
  end
end
