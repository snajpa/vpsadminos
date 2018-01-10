module OsCtld
  # Shared methods for objects that can have CGroup parameters set.
  #
  # The object must:
  #  - initialize @cgparams = []
  #  - have method `save_config`
  #  - have method `abs_cgroup_path(subsystem)`
  module CGroup::Params
    Param = Struct.new(:subsystem, :name, :value) do
      # Load from config
      def self.load(hash)
        new(hash['subsystem'], hash['name'], hash['value'])
      end

      # Load from client
      def self.import(hash)
        new(hash[:subsystem], hash[:parameter], hash[:value])
      end

      # Dump to config
      def dump
        Hash[to_h.map { |k,v| [k.to_s, v] }]
      end

      # Export to client
      def export
        {
          subsystem: subsystem,
          parameter: name,
          value: value,
        }
      end
    end

    attr_reader :cgparams

    # Process params from the client and return internal representation.
    # Invalid parameters raise an exception.
    def import_cgparams(params)
      params.map do |hash|
        p = Param.import(hash)

        # Check if the subsystem is valid
        subsys = CGroup.real_subsystem(p.subsystem)
        path = File.join(CGroup::FS, subsys)

        unless Dir.exist?(path)
          raise CGroupSubsystemNotFound,
            "CGroup subsystem '#{p.subsystem}' not found at '#{path}'"
        end

        # Check parameter
        param = File.join(path, p.name)

        unless File.exist?(param)
          raise CGroupParameterNotFound, "CGroup parameter '#{param}' not found"
        end

        p
      end
    end

    def set_cgparams(new_params, save: true)
      exclusively do
        new_params.each do |new_p|
          replaced = false

          cgparams.map! do |p|
            if p.subsystem == new_p.subsystem && p.name == new_p.name
              replaced = true
              new_p

            else
              p
            end
          end

          next if replaced

          cgparams << new_p
        end
      end

      save_config if save
    end

    def unset_cgparams(del_params, save: true)
      exclusively do
        del_params.each do |del_h|
          del_p = Param.import(del_h)

          cgparams.delete_if do |p|
            p.subsystem == del_p.subsystem && p.name == del_p.name
          end
        end
      end

      save_config if save
    end

    protected
    # Load params from config
    def load_cgparams(params)
      (params || []).map { |v| Param.load(v) }
    end

    # Dump params to config
    def dump_cgparams(params)
      cgparams.map(&:dump)
    end
  end
end
