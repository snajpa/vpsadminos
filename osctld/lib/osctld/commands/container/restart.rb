require 'osctld/commands/logged'

module OsCtld
  class Commands::Container::Restart < Commands::Logged
    handle :ct_restart

    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include Utils::SwitchUser

    def find
      ct = DB::Containers.find(opts[:id], opts[:pool])
      ct || error!('container not found')
    end

    def execute(ct)
      manipulate(ct) do
        if opts[:reboot]
          ct_control(ct, :ct_reboot, id: ct.id)
          ok

        else
          call_cmd!(
            Commands::Container::Stop,
            id: ct.id,
            timeout: opts[:stop_timeout],
            method: opts[:stop_method]
          )
          call_cmd!(
            Commands::Container::Start,
            id: ct.id,
            force: true,
            wait: opts[:wait],
          )
        end
      end
    end
  end
end
