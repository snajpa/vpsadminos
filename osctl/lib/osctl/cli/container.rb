require 'highline'
require 'ipaddress'
require 'tempfile'

module OsCtl::Cli
  class Container < Command
    include CGroupParams
    include Assets

    FIELDS = %i(
      pool
      id
      user
      group
      dataset
      rootfs
      lxc_path
      lxc_dir
      group_path
      distribution
      version
      state
      init_pid
      hostname
      dns_resolvers
      nesting
    ) + CGroupParams::CGPARAM_STATS

    FILTERS = %i(
      pool
      user
      group
      distribution
      version
      state
    )

    DEFAULT_FIELDS = %i(
      pool
      id
      user
      group
      distribution
      version
      state
      init_pid
      memory
      cpu_time
    )

    PRLIMIT_FIELDS = %i(
      name
      soft
      hard
    )

    DATASET_FIELDS = %i(
      name
      dataset
    )

    MOUNT_FIELDS = %i(
      fs
      dataset
      mountpoint
      type
      opts
    )

    def list
      if opts[:list]
        puts FIELDS.join("\n")
        return
      end

      cmd_opts = {}
      fmt_opts = {layout: :columns}

      FILTERS.each do |v|
        [gopts, opts].each do |options|
          next unless options[v]
          cmd_opts[v] = options[v].split(',')
        end
      end

      cmd_opts[:ids] = args if args.count > 0
      fmt_opts[:header] = false if opts['hide-header']
      cols = opts[:output] ? opts[:output].split(',').map(&:to_sym) : DEFAULT_FIELDS

      c = osctld_open
      cts = cg_add_stats(
        c,
        c.cmd_data!(:ct_list, cmd_opts),
        lambda { |ct| ct[:group_path] },
        cols,
        gopts[:parsable]
      )

      format_output(cts, cols, fmt_opts)
    end

    def show
      if opts[:list]
        puts FIELDS.join("\n")
        return
      end

      require_args!('id')

      cols = opts[:output] ? opts[:output].split(',').map(&:to_sym) : FIELDS

      c = osctld_open
      ct = c.cmd_data!(:ct_show, id: args[0], pool: gopts[:pool])

      cg_add_stats(c, ct, ct[:group_path], cols, gopts[:parsable])
      c.close

      format_output(ct, cols)
    end

    def create
      require_args!('id')

      if !opts[:template] && !opts[:dataset] && !opts[:stream]
        raise GLI::BadCommandLine, 'provide --template, --stream or --dataset'
      end

      cmd_opts = {
        id: args[0],
        pool: opts[:pool] || gopts[:pool],
        user: opts[:user],
      }

      %i(group dataset distribution version).each do |v|
        cmd_opts[v] = opts[v] if opts[v]
      end

      if opts[:template] && opts[:stream]
        raise GLI::BadCommandLine, 'provide --template or --stream, not both'

      elsif opts[:template]
        cmd_opts[:template] = File.absolute_path(opts[:template])

      elsif opts[:stream]
        stdin = opts[:stream] == '-'
        cmd_opts[:stream] = {
          type: stdin ? :stdin : :file,
          path: stdin ? nil : File.absolute_path(opts[:stream])
        }
      end

      if !cmd_opts[:stream] || cmd_opts[:stream][:type] == :file
        osctld_fmt(:ct_create, cmd_opts)
        return
      end

      updates = Proc.new { |msg| puts msg unless gopts[:quiet] }
      c = osctld_open
      ret = c.cmd_data!(:ct_create, cmd_opts, &updates)

      error!('invalid response, stdin stream not available') if ret != 'continue'

      r_in, w_in = IO.pipe
      c.send_io(r_in)
      r_in.close
      w_in.write(STDIN.read(16*1024)) until STDIN.eof?
      w_in.close

      c.response!(&updates)
    end

    def delete
      require_args!('id')

      osctld_fmt(:ct_delete, id: args[0], pool: gopts[:pool])
    end

    def start
      require_args!('id')
      cmd_opts = {id: args[0], pool: gopts[:pool]}
      return osctld_fmt(:ct_start, cmd_opts) unless opts[:foreground]

      open_console(args[0], gopts[:pool], 0) do |sock|
        sock.close if osctld_resp(:ct_start, cmd_opts).error?
      end
    end

    def stop
      require_args!('id')
      cmd_opts = {id: args[0], pool: gopts[:pool]}
      return osctld_fmt(:ct_stop, cmd_opts) unless opts[:foreground]

      open_console(args[0], gopts[:pool], 0) do |sock|
        sock.close if osctld_resp(:ct_stop, cmd_opts).error?
      end
    end

    def restart
      require_args!('id')
      cmd_opts = {id: args[0], pool: gopts[:pool]}
      return osctld_fmt(:ct_restart, cmd_opts) unless opts[:foreground]

      open_console(args[0], gopts[:pool], 0) do |sock|
        sock.close if osctld_resp(:ct_restart, cmd_opts).error?
      end
    end

    def console
      require_args!('id')

      open_console(args[0], gopts[:pool], opts[:tty])
    end

    def attach
      require_args!('id')

      cmd = osctld_call(:ct_attach, id: args[0], pool: gopts[:pool])

      pid = Process.fork do
        cmd[:env].each do |k, v|
          ENV[k.to_s] = v
        end

        Process.exec(*cmd[:cmd])
      end

      Process.wait(pid)
    end

    def exec
      require_args!('id', 'command')

      c = osctld_open
      cont = c.cmd_data!(
        :ct_exec,
        id: args[0],
        pool: gopts[:pool],
        cmd: args[1..-1]
      )

      if cont != 'continue'
        warn "exec not available: invalid response '#{cont}'"
        exit(false)
      end

      r_in, w_in = IO.pipe
      r_out, w_out = IO.pipe
      r_err, w_err = IO.pipe

      c.send_io(r_in)
      c.send_io(w_out)
      c.send_io(w_err)

      r_in.close
      w_out.close
      w_err.close

      loop do
        rs, ws, = IO.select([STDIN, r_out, r_err, c.socket])

        rs.each do |r|
          case r
          when r_out
            data = r.read_nonblock(4096)
            STDOUT.write(data)
            STDOUT.flush

          when r_err
            data = r.read_nonblock(4096)
            STDERR.write(data)
            STDERR.flush

          when STDIN
            data = r.read_nonblock(4096)
            w_in.write(data)

          when c.socket
            r_out.close
            r_err.close

            c.receive
            return
          end
        end
      end
    end

    def su
      require_args!('id')

      cmd = osctld_call(:ct_su, id: args[0], pool: gopts[:pool])
      pid = Process.fork do
        cmd[:env].each do |k, v|
          ENV[k.to_s] = v
        end

        Process.exec(*cmd[:cmd])
      end

      Process.wait(pid)
    end

    def set_hostname
      set(:hostname) do |args|
        args[0] || (fail 'expected hostname')
      end
    end

    def unset_hostname
      unset(:hostname)
    end

    def set_dns_resolver
      set(:dns_resolvers) do |args|
        raise GLI::BadCommandLine, 'expected at least one address' if args.empty?
        args
      end
    end

    def unset_dns_resolver
      unset(:dns_resolvers)
    end

    def set_nesting
      set(:nesting) do |args|
        case args[0]
        when 'enabled'
          true
        when 'disabled'
          false
        else
          raise GLI::BadCommandLine, 'expected enabled/disabled'
        end
      end
    end

    def set_distribution
      set(:distribution) do |args|
        raise GLI::BadCommandLine, 'expected <distribution> <version>' if args.count != 2

        {
          name: args[0],
          version: args[1],
        }
      end
    end

    def chown
      require_args!('id', 'user')
      osctld_fmt(:ct_chown, id: args[0], pool: gopts[:pool], user: args[1])
    end

    def chgrp
      require_args!('id', 'group')
      osctld_fmt(:ct_chgrp, id: args[0], pool: gopts[:pool], group: args[1])
    end

    def passwd
      require_args!('id', 'user')

      if args[2]
        password = args[2]

      else
        cli = HighLine.new
        password = cli.ask('Password: ') { |q| q.echo = false }.strip
      end

      osctld_fmt(
        :ct_passwd,
        id: args[0],
        pool: gopts[:pool],
        user: args[1],
        password: password
      )
    end

    def export
      require_args!('id', 'file')

      osctld_fmt(
        :ct_export,
        id: args[0],
        pool: gopts[:pool],
        file: File.expand_path(args[1]),
        consistent: opts[:consistent],
        compression: opts[:compression]
      )
    end

    def import
      require_args!('file')

      file = File.expand_path(args[0])
      fail "#{file}: not found" unless File.exist?(file)

      cmd_opts = {file: file}

      %w(as-id as-user as-group dataset).each do |v|
        cmd_opts[v.sub('-', '_').to_sym] = opts[v] if opts[v]
      end

      osctld_fmt(:ct_import, cmd_opts)
    end

    def cd
      require_args!('id')

      ct = osctld_call(:ct_show, id: args[0], pool: gopts[:pool])

      if opts[:runtime]
        raise "container not running" unless ct[:init_pid]
        path = File.join('/proc/', ct[:init_pid].to_s, 'root', '/')

      elsif opts[:lxc]
        path = ct[:lxc_dir]

      else
        path = ct[:rootfs]
      end

      file = Tempfile.new('osctl-rcfile')
      file.write(<<-END
        export PS1="(CT #{ct[:id]}) $PS1"
        cd "#{path}"
        END
      )
      file.close

      puts "Spawning a new shell, exit when done"
      pid = Process.spawn(ENV['SHELL'] || 'bash', '--rcfile', file.path)
      Process.wait(pid)

      file.unlink
    end

    def log_cat
      require_args!('id')

      ct = osctld_call(:ct_show, id: args[0], pool: gopts[:pool])

      File.open(ct[:log_file]) do |f|
        puts f.readline until f.eof?
      end
    end

    def log_path
      require_args!('id')

      ct = osctld_call(:ct_show, id: args[0], pool: gopts[:pool])
      puts ct[:log_file]
    end

    def assets
      require_args!('id')

      print_assets(:ct_assets, id: args[0], pool: gopts[:pool])
    end

    def open_console(ctid, pool, tty)
      c = osctld_open
      c.cmd_response!(:ct_console, id: ctid, pool: pool, tty: tty)

      puts "Press Ctrl+a q to detach the console"
      puts

      state = `stty -g`
      `stty raw -echo -icanon -isig`

      pid = Process.fork do
        OsCtl::Console.open(c.socket, STDIN, STDOUT)
      end

      yield(c) if block_given?

      Process.wait(pid)

      `stty #{state}`
      puts
    end

    def cgparam_list
      require_args!('id')

      do_cgparam_list(:ct_cgparam_list, id: args[0], pool: gopts[:pool])
    end

    def cgparam_set
      require_args!('id', 'parameter', 'value')
      do_cgparam_set(:ct_cgparam_set, id: args[0], pool: gopts[:pool])
    end

    def cgparam_unset
      require_args!('id', 'parameter')
      do_cgparam_unset(:ct_cgparam_unset, id: args[0], pool: gopts[:pool])
    end

    def cgparam_apply
      require_args!('id')
      do_cgparam_apply(:ct_cgparam_apply, id: args[0], pool: gopts[:pool])
    end

    def prlimit_list
      if opts[:list]
        puts PRLIMIT_FIELDS.join("\n")
        return
      end

      require_args!('id')

      cmd_opts = {id: args[0], pool: gopts[:pool]}
      fmt_opts = {layout: :columns}

      cmd_opts[:limits] = args[1..-1] if args.count > 1
      fmt_opts[:header] = false if opts['hide-header']

      if opts[:output]
        cols = opts[:output].split(',').map(&:to_sym)

      else
        cols = PRLIMIT_FIELDS
      end

      osctld_fmt(:ct_prlimit_list, cmd_opts, cols, fmt_opts)
    end

    def prlimit_set
      require_args!('id', 'limit', 'value')

      soft, hard = args[2..3].map { |v| /^\d+$/ =~ v ? v.to_i : v }
      hard = soft if hard.nil?

      osctld_fmt(
        :ct_prlimit_set,
        id: args[0],
        pool: gopts[:pool],
        name: args[1],
        soft: soft,
        hard: hard
      )
    end

    def prlimit_unset
      require_args!('id', 'limit')

      do_cgparam_unset(
        :ct_prlimit_unset,
        id: args[0],
        pool: gopts[:pool],
        name: args[1]
      )
    end

    def dataset_list
      if opts[:list]
        puts DATASET_FIELDS.join("\n")
        return
      end

      require_args!('id')
      props = args[1..-1]

      cmd_opts = {id: args[0], pool: gopts[:pool], properties: props}
      fmt_opts = {layout: :columns}

      fmt_opts[:header] = false if opts['hide-header']

      if opts[:output]
        cols = (opts[:output].split(',') + props).map(&:to_sym)

      else
        cols = nil
      end

      osctld_fmt(:ct_dataset_list, cmd_opts, cols, fmt_opts)
    end

    def dataset_create
      require_args!('id', 'name')
      osctld_fmt(
        :ct_dataset_create,
        id: args[0],
        pool: gopts[:pool],
        name: args[1],
        mount: opts[:mount],
        mountpoint: args[2]
      )
    end

    def dataset_delete
      require_args!('id', 'name')
      osctld_fmt(
        :ct_dataset_delete,
        id: args[0],
        pool: gopts[:pool],
        name: args[1],
        recursive: opts[:recursive],
        unmount: opts[:unmount]
      )
    end

    def mount_list
      if opts[:list]
        puts MOUNT_FIELDS.join("\n")
        return
      end

      require_args!('id')

      cmd_opts = {id: args[0], pool: gopts[:pool]}
      fmt_opts = {layout: :columns}

      fmt_opts[:header] = false if opts['hide-header']

      if opts[:output]
        cols = opts[:output].split(',').map(&:to_sym)

      else
        cols = MOUNT_FIELDS
      end

      osctld_fmt(:ct_mount_list, cmd_opts, cols, fmt_opts)
    end

    def mount_create
      require_args!('id')

      osctld_fmt(
        :ct_mount_create,
        id: args[0],
        pool: gopts[:pool],
        fs: opts[:fs],
        mountpoint: opts[:mountpoint],
        type: opts[:type],
        opts: opts[:opts],
      )
    end

    def mount_dataset
      require_args!('id', 'name')

      osctld_fmt(
        :ct_mount_dataset,
        id: args[0],
        pool: gopts[:pool],
        name: args[1],
        mountpoint: opts[:mountpoint],
        opts: opts[:opts],
      )
    end

    def mount_delete
      require_args!('id', 'mountpoint')

      osctld_fmt(
        :ct_mount_delete,
        id: args[0],
        pool: gopts[:pool],
        mountpoint: args[1]
      )
    end

    protected
    def set(option)
      require_args!('id')
      cmd_opts = {id: args[0], pool: gopts[:pool]}
      cmd_opts[option] = yield(args[1..-1])

      osctld_fmt(:ct_set, cmd_opts)
    end

    def unset(option)
      require_args!('id')
      cmd_opts = {id: args[0], pool: gopts[:pool]}
      cmd_opts[option] = block_given? ? yield(args[1..-1]) : true

      osctld_fmt(:ct_unset, cmd_opts)
    end
  end
end
