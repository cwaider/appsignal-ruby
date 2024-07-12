describe Appsignal::Loaders do
  before do
    Class.new(Appsignal::Loaders::Loader) do
      def on_load
        puts "do something on_load"
        register_config_defaults(
          :root_path => "/some/path",
          :env => "test env",
          :active => false
        )
      end
      register :test_loader
    end
  end
  after do
    Appsignal::Loaders.unregister :test_loader
  end

  it "registers a loader" do
    Appsignal.load(:test_loader)
    puts Appsignal::Config.loader_defaults
  end
end
