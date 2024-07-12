module Appsignal
  module Loaders
    class SinatraLoader < Loader
      def on_load
        Appsignal.internal_logger.debug("Loading Sinatra (#{Sinatra::VERSION}) integration")

        require "appsignal/rack/sinatra_instrumentation"

        app_settings = ::Sinatra::Application.settings
        register_config_defaults(
          :root_path => app_settings.root || Dir.pwd,
          :env => app_settings.environment
        )

        ::Sinatra::Base.use(::Rack::Events, [Appsignal::Rack::EventHandler.new])
        ::Sinatra::Base.use(Appsignal::Rack::SinatraBaseInstrumentation)
      end
    end

    register :sinatra, SinatraLoader
  end
end
