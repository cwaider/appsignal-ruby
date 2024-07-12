module Appsignal
  module Loaders
    class << self
      def loaders
        @loaders ||= {}
      end

      def register(name, klass)
        loaders[name] = klass
      end

      def unregister(name)
        loaders.delete(name)
      end

      def load(name)
        loader = loaders[name]
        return unless loader

        loader.new.on_load
      end
    end

    class Loader
      def self.register(name)
        Loaders.register(name, self)
      end

      def register_config_defaults(options)
        Appsignal::Config.merge_loader_defaults(options)
      end
    end
  end
end
