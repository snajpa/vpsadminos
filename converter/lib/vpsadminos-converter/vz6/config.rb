module VpsAdminOS::Converter
  # Represents a config file for OpenVZ Legacy container
  class Vz6::Config
    def self.parse(ctid, path)
      f = File.open(path, 'r')
      c = new(ctid, f)
      f.close
      c
    end

    attr_reader :ctid

    def initialize(ctid, io)
      @ctid = ctid
      @items = {}

      parse(io)
    end

    # yield [Vz6::ConfigItem]
    def each(&block)
      @items.each_value(&block)
    end

    # @param k [String] config key
    # @return [Vz6::ConfigItem]
    def [](k)
      @items[k]
    end

    def consume(k)
      it = @items[k]
      return unless it

      it.consume
      it.value
    end

    protected
    def parse(io)
      io.each_line do |line|
        if /^\s*#/ =~ line || /^\s*$/ =~ line
          next

        elsif /^([A-Z_]+)="([^"]+)"/ =~ line
          it = Vz6::ConfigItem.new(ctid, $1, $2)
          @items[it.key] = it

        elsif /^([A-Z_]+)=([^\s]+)/ =~ line
          it = Vz6::ConfigItem.new(ctid, $1, $2)
          @items[it.key] = it

        else
          warn "Unknown line '#{line}'"
        end
      end
    end
  end
end
