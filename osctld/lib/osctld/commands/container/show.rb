module OsCtld
  class Commands::Container::Show < Commands::Base
    handle :ct_show

    include Utils::Log
    include Utils::System
    include Utils::SwitchUser

    def execute
      ct = DB::Containers.find(opts[:id], opts[:pool])
      return error('container not found') unless ct

      ct.inclusively do
        ok({
          pool: ct.pool.name,
          id: ct.id,
          user: ct.user.name,
          group: ct.group.name,
          dataset: ct.dataset.name,
          rootfs: ct.rootfs,
          lxc_path: ct.lxc_home,
          lxc_dir: ct.lxc_dir,
          group_path: ct.cgroup_path,
          distribution: ct.distribution,
          version: ct.version,
          state: ct.state,
          init_pid: ct.init_pid,
          hostname: ct.hostname,
          dns_resolvers: ct.dns_resolvers,
          nesting: ct.nesting,
          log_file: ct.log_path,
        })
      end
    end
  end
end
