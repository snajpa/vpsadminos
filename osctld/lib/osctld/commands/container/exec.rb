require 'osctld/commands/base'

module OsCtld
  class Commands::Container::Exec < Commands::Base
    handle :ct_exec

    include OsCtl::Lib::Utils::Log
    include Utils::SwitchUser

    def execute
      ct = DB::Containers.find(opts[:id], opts[:pool])
      error!('container not found') unless ct
      error!('container not running') if !ct.running? && !opts[:run]

      client.send({status: true, response: 'continue'}.to_json + "\n", 0)

      ct_exec(
        ct,
        cmd: opts[:cmd],
        network: opts[:network],
        stdin: client.recv_io,
        stdout: client.recv_io,
        stderr: client.recv_io,
      )
    end
  end
end
