describe Appsignal do
  include EnvironmentMetadataHelper
  around { |example| keep_transactions { example.run } }

  let(:transaction) { http_request_transaction }

  describe "._config=" do
    it "sets the config" do
      config = project_fixture_config
      expect(Appsignal.internal_logger).to_not receive(:level=)

      Appsignal._config = config
      expect(Appsignal.config).to eq config
    end
  end

  describe ".configure" do
    context "when active" do
      it "doesn't update the config" do
        start_agent
        Appsignal::Testing.store[:config_called] = false
        expect do
          Appsignal.configure do |_config|
            Appsignal::Testing.store[:config_called] = true
          end
        end.to_not(change { [Appsignal.config, Appsignal.active?] })
        expect(Appsignal::Testing.store[:config_called]).to be(false)
      end

      it "logs a warning" do
        start_agent
        logs =
          capture_logs do
            Appsignal.configure do |_config|
              # Do something
            end
          end
        expect(logs).to contains_log(
          :warn,
          "AppSignal is already started. Ignoring `Appsignal.configure` call."
        )
      end
    end

    context "with config but not started" do
      it "reuses the already loaded config if the env is the same" do
        Appsignal._config = Appsignal::Config.new(
          project_fixture_path,
          :my_env,
          :ignore_actions => ["My action"]
        )

        Appsignal.configure(:my_env) do |config|
          expect(config.ignore_actions).to eq(["My action"])
          config.active = true
          config.name = "My app"
          config.push_api_key = "key"
        end
        expect(Appsignal.config.valid?).to be(true)
        expect(Appsignal.config.env).to eq("my_env")
        expect(Appsignal.config[:active]).to be(true)
        expect(Appsignal.config[:name]).to eq("My app")
        expect(Appsignal.config[:push_api_key]).to eq("key")
      end

      it "loads a new config if the env is not the same" do
        Appsignal._config = Appsignal::Config.new(
          project_fixture_path,
          :my_env,
          :name => "Some name",
          :push_api_key => "Some key",
          :ignore_actions => ["My action"]
        )

        Appsignal.configure(:my_env2) do |config|
          expect(config.ignore_actions).to be_empty
          config.active = true
          config.name = "My app"
          config.push_api_key = "key"
        end
        expect(Appsignal.config.valid?).to be(true)
        expect(Appsignal.config.env).to eq("my_env2")
        expect(Appsignal.config[:active]).to be(true)
        expect(Appsignal.config[:name]).to eq("My app")
        expect(Appsignal.config[:push_api_key]).to eq("key")
      end

      it "calls configure if not started yet" do
        Appsignal.configure(:my_env) do |config|
          config.active = false
          config.name = "Some name"
        end
        Appsignal.start
        expect(Appsignal.started?).to be_falsy

        Appsignal.configure(:my_env) do |config|
          expect(config.ignore_actions).to be_empty
          config.active = true
          config.name = "My app"
          config.push_api_key = "key"
        end
        expect(Appsignal.config.valid?).to be(true)
        expect(Appsignal.config.env).to eq("my_env")
        expect(Appsignal.config[:active]).to be(true)
        expect(Appsignal.config[:name]).to eq("My app")
        expect(Appsignal.config[:push_api_key]).to eq("key")
      end
    end

    context "when not active" do
      it "starts with the configured config" do
        Appsignal.configure(:test) do |config|
          config.push_api_key = "key"
        end

        Appsignal.start
        expect(Appsignal.config[:push_api_key]).to eq("key")
      end

      it "uses the given env" do
        ENV["APPSIGNAL_APP_ENV"] = "env_env"
        Appsignal.configure(:env_arg)

        Appsignal.start
        expect(Appsignal.config.env).to eq("env_arg")
      end

      it "loads the config without a block being given" do
        Dir.chdir project_fixture_path do
          Appsignal.configure(:test)
        end

        expect(Appsignal.config.env).to eq("test")
        expect(Appsignal.config[:push_api_key]).to eq("abc")
      end

      it "allows customization of config in the block" do
        Appsignal.configure(:test) do |config|
          config.push_api_key = "key"
        end

        expect(Appsignal.config.valid?).to be(true)
        expect(Appsignal.config.env).to eq("test")
        expect(Appsignal.config[:push_api_key]).to eq("key")
      end

      it "loads the default config" do
        Appsignal.configure do |config|
          Appsignal::Config::DEFAULT_CONFIG.each do |option, value|
            expect(config.send(option)).to eq(value)
          end
        end
      end

      it "loads the config from the YAML file" do
        Dir.chdir project_fixture_path do
          Appsignal.configure(:test) do |config|
            expect(config.name).to eq("TestApp")
          end
        end
      end

      it "recognizes valid config" do
        Appsignal.configure(:my_env) do |config|
          config.push_api_key = "key"
        end

        expect(Appsignal.config.valid?).to be(true)
      end

      it "recognizes invalid config" do
        Appsignal.configure(:my_env) do |config|
          config.push_api_key = ""
        end

        expect(Appsignal.config.valid?).to be(false)
      end

      it "sets the environment when given as an argument" do
        Appsignal.configure(:my_env)

        expect(Appsignal.config.env).to eq("my_env")
      end

      it "reads the environment from the environment" do
        ENV["APPSIGNAL_APP_ENV"] = "env_env"
        Appsignal.configure do |config|
          expect(config.env).to eq("env_env")
        end

        expect(Appsignal.config.env).to eq("env_env")
      end

      it "allows modification of previously unset config options" do
        expect do
          Appsignal.configure do |config|
            config.ignore_actions << "My action"
            config.request_headers << "My allowed header"
          end
        end.to_not(change { Appsignal::Config::DEFAULT_CONFIG })

        expect(Appsignal.config[:ignore_actions]).to eq(["My action"])
        expect(Appsignal.config[:request_headers])
          .to eq(Appsignal::Config::DEFAULT_CONFIG[:request_headers] + ["My allowed header"])
      end
    end
  end

  describe ".start" do
    context "with no config set beforehand" do
      let(:stdout_stream) { std_stream }
      let(:stdout) { stdout_stream.read }
      let(:stderr_stream) { std_stream }
      let(:stderr) { stderr_stream.read }
      before { ENV["APPSIGNAL_LOG"] = "stdout" }

      it "does nothing when config is not set and there is no valid config in the env" do
        expect(Appsignal::Extension).to_not receive(:start)
        capture_std_streams(stdout_stream, stderr_stream) { Appsignal.start }

        expect(stdout).to contains_log(
          :error,
          "appsignal: Not starting, no valid config for this environment"
        )
      end

      it "should create a config from the env" do
        ENV["APPSIGNAL_PUSH_API_KEY"] = "something"
        expect(Appsignal::Extension).to receive(:start)
        capture_std_streams(stdout_stream, stderr_stream) { Appsignal.start }

        expect(Appsignal.config[:push_api_key]).to eq("something")
        expect(stderr).to_not include("[ERROR]")
        expect(stdout).to_not include("[ERROR]")
      end
    end

    context "when config is loaded" do
      before { Appsignal._config = project_fixture_config }

      it "should initialize logging" do
        Appsignal.start
        expect(Appsignal.internal_logger.level).to eq Logger::INFO
      end

      it "should start native" do
        expect(Appsignal::Extension).to receive(:start)
        Appsignal.start
      end

      it "freezes the config" do
        Appsignal.start

        expect_frozen_error do
          Appsignal.config[:ignore_actions] << "my action"
        end
        expect_frozen_error do
          Appsignal.config.config_hash[:ignore_actions] << "my action"
        end
        expect_frozen_error do
          Appsignal.config.config_hash.merge!(:option => :value)
        end
        expect_frozen_error do
          Appsignal.config[:ignore_actions] = "my action"
        end
      end

      def expect_frozen_error(&block)
        expect(&block).to raise_error(FrozenError)
      end

      context "when allocation tracking has been enabled" do
        before do
          Appsignal.config.config_hash[:enable_allocation_tracking] = true
          capture_environment_metadata_report_calls
        end

        unless DependencyHelper.running_jruby?
          it "installs the allocation event hook" do
            expect(Appsignal::Extension).to receive(:install_allocation_event_hook)
              .and_call_original
            Appsignal.start
            expect_environment_metadata("ruby_allocation_tracking_enabled", "true")
          end
        end
      end

      context "when allocation tracking has been disabled" do
        before do
          Appsignal.config.config_hash[:enable_allocation_tracking] = false
          capture_environment_metadata_report_calls
        end

        it "should not install the allocation event hook" do
          expect(Appsignal::Extension).not_to receive(:install_allocation_event_hook)
          Appsignal.start
          expect_not_environment_metadata("ruby_allocation_tracking_enabled")
        end
      end

      context "when minutely metrics has been enabled" do
        before do
          Appsignal.config.config_hash[:enable_minutely_probes] = true
        end

        it "should start minutely" do
          expect(Appsignal::Probes).to receive(:start)
          Appsignal.start
        end
      end

      context "when minutely metrics has been disabled" do
        before do
          Appsignal.config.config_hash[:enable_minutely_probes] = false
        end

        it "should not start minutely" do
          expect(Appsignal::Probes).to_not receive(:start)
          Appsignal.start
        end
      end

      describe "loaders" do
        it "starts loaded loaders" do
          Appsignal::Testing.store[:loader_loaded] = 0
          Appsignal::Testing.store[:loader_started] = 0
          define_loader(:start_loader) do
            def on_load
              Appsignal::Testing.store[:loader_loaded] += 1
            end

            def on_start
              Appsignal::Testing.store[:loader_started] += 1
            end
          end
          Appsignal::Loaders.load(:start_loader)
          Appsignal::Loaders.start

          expect(Appsignal::Testing.store[:loader_loaded]).to eq(1)
          expect(Appsignal::Testing.store[:loader_started]).to eq(1)
        end
      end

      describe "environment metadata" do
        before { capture_environment_metadata_report_calls }

        it "collects and reports environment metadata" do
          Appsignal.start
          expect_environment_metadata("ruby_version", "#{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}")
          expect_environment_metadata("ruby_engine", RUBY_ENGINE)
          if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.3.0")
            expect_environment_metadata("ruby_engine_version", RUBY_ENGINE_VERSION)
          end
        end
      end
    end

    context "with debug logging" do
      before { Appsignal._config = project_fixture_config("test") }

      it "should change the log level" do
        Appsignal.start
        expect(Appsignal.internal_logger.level).to eq Logger::DEBUG
      end
    end
  end

  describe ".load" do
    before do
      TestLoader = define_loader(:appsignal_loader)
    end
    after do
      Object.send(:remove_const, :TestLoader)
    end

    it "loads a loader" do
      expect(Appsignal::Loaders.instances).to be_empty
      Appsignal.load(:appsignal_loader)
      expect(Appsignal::Loaders.instances)
        .to include(:appsignal_loader => instance_of(TestLoader))
    end
  end

  describe ".forked" do
    context "when not active" do
      it "does nothing" do
        expect(Appsignal::Extension).to_not receive(:start)

        Appsignal.forked
      end
    end

    context "when active" do
      before do
        Appsignal._config = project_fixture_config
      end

      it "starts the logger and extension" do
        expect(Appsignal).to receive(:_start_logger)
        expect(Appsignal::Extension).to receive(:start)

        Appsignal.forked
      end
    end
  end

  describe ".stop" do
    it "calls stop on the extension" do
      expect(Appsignal.internal_logger).to receive(:debug).with("Stopping AppSignal")
      expect(Appsignal::Extension).to receive(:stop)
      Appsignal.stop
      expect(Appsignal.active?).to be_falsy
    end

    it "stops the minutely probes" do
      Appsignal::Probes.start
      expect(Appsignal::Probes.started?).to be_truthy
      Appsignal.stop
      expect(Appsignal::Probes.started?).to be_falsy
    end

    context "with context specified" do
      it "should log the context" do
        expect(Appsignal.internal_logger).to receive(:debug).with("Stopping AppSignal (something)")
        expect(Appsignal::Extension).to receive(:stop)
        Appsignal.stop("something")
        expect(Appsignal.active?).to be_falsy
      end
    end
  end

  describe ".started?" do
    subject { Appsignal.started? }

    context "when started with active config" do
      before { start_agent }

      it { is_expected.to be_truthy }
    end

    context "when started with inactive config" do
      before do
        Appsignal._config = project_fixture_config("nonsense")
      end

      it { is_expected.to be_falsy }
    end
  end

  describe ".active?" do
    subject { Appsignal.active? }

    context "without config" do
      it { is_expected.to be_falsy }
    end

    context "with inactive config" do
      before do
        Appsignal._config = project_fixture_config("nonsense")
      end

      it { is_expected.to be_falsy }
    end

    context "with active config" do
      before do
        Appsignal._config = project_fixture_config
      end

      it { is_expected.to be_truthy }
    end
  end

  describe ".add_exception" do
    it "should alias this method" do
      expect(Appsignal).to respond_to(:add_exception)
    end
  end

  describe ".get_server_state" do
    it "should call server state on the extension" do
      expect(Appsignal::Extension).to receive(:get_server_state).with("key")

      Appsignal.get_server_state("key")
    end

    it "should get nil by default" do
      expect(Appsignal.get_server_state("key")).to be_nil
    end
  end

  context "not active" do
    before { Appsignal._config = project_fixture_config("not_active") }

    describe ".listen_for_error" do
      let(:error) { ExampleException.new("specific error") }

      it "reraises the error" do
        expect do
          Appsignal.listen_for_error { raise error }
        end.to raise_error(error)
      end

      it "does not create a transaction" do
        expect do
          expect do
            Appsignal.listen_for_error { raise error }
          end.to raise_error(error)
        end.to_not(change { created_transactions.count })
      end
    end

    describe ".send_error" do
      let(:error) { ExampleException.new("specific error") }

      it "does not raise an error" do
        Appsignal.send_error(error)
      end

      it "does not create a transaction" do
        expect do
          Appsignal.send_error(error)
        end.to_not(change { created_transactions.count })
      end
    end

    describe ".set_error" do
      let(:error) { ExampleException.new("specific error") }

      it "does not raise an error" do
        Appsignal.set_error(error)
      end

      it "does not create a transaction" do
        expect do
          Appsignal.set_error(error)
        end.to_not(change { created_transactions.count })
      end
    end

    describe ".report_error" do
      let(:error) { ExampleException.new("specific error") }

      it "does not raise an error" do
        Appsignal.report_error(error)
      end

      it "does not create a transaction" do
        expect do
          Appsignal.report_error(error)
        end.to_not(change { created_transactions.count })
      end
    end

    describe ".set_namespace" do
      it "does not raise an error" do
        Appsignal.set_namespace("custom")
      end
    end

    describe ".tag_request" do
      it "does not raise an error" do
        Appsignal.tag_request(:tag => "tag")
      end
    end

    describe ".set_custom_data" do
      it "does not raise an error" do
        Appsignal.set_custom_data(:data => "value")
      end
    end
  end

  context "with config and started" do
    before { start_agent }
    around { |example| keep_transactions { example.run } }

    describe ".monitor" do
      it "creates a transaction" do
        expect do
          Appsignal.monitor(:action => "MyAction")
        end.to(change { created_transactions.count }.by(1))

        transaction = last_transaction
        expect(transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)
        expect(transaction).to have_action("MyAction")
        expect(transaction).to_not have_error
        expect(transaction).to_not include_events
        expect(transaction).to_not have_queue_start
        expect(transaction).to be_completed
      end

      it "returns the block's return value" do
        expect(Appsignal.monitor(:action => nil) { :return_value }).to eq(:return_value)
      end

      it "sets a custom namespace via the namespace argument" do
        Appsignal.monitor(:namespace => "custom", :action => nil)

        expect(last_transaction).to have_namespace("custom")
      end

      it "doesn't overwrite custom namespace set in the block" do
        Appsignal.monitor(:namespace => "custom", :action => nil) do
          Appsignal.set_namespace("more custom")
        end

        expect(last_transaction).to have_namespace("more custom")
      end

      it "sets the action via the action argument using a string" do
        Appsignal.monitor(:action => "custom")

        expect(last_transaction).to have_action("custom")
      end

      it "sets the action via the action argument using a symbol" do
        Appsignal.monitor(:action => :custom)

        expect(last_transaction).to have_action("custom")
      end

      it "doesn't overwrite custom action set in the block" do
        Appsignal.monitor(:action => "custom") do
          Appsignal.set_action("more custom")
        end

        expect(last_transaction).to have_action("more custom")
      end

      it "doesn't set the action when value is nil" do
        Appsignal.monitor(:action => nil)

        expect(last_transaction).to_not have_action
      end

      it "doesn't set the action when value is :set_later" do
        Appsignal.monitor(:action => :set_later)

        expect(last_transaction).to_not have_action
      end

      it "reports exceptions that occur in the block" do
        expect do
          Appsignal.monitor :action => nil do
            raise ExampleException, "error message"
          end
        end.to raise_error(ExampleException, "error message")

        expect(last_transaction).to have_error("ExampleException", "error message")
      end

      context "with already active transction" do
        let(:err_stream) { std_stream }
        let(:stderr) { err_stream.read }
        let(:transaction) { http_request_transaction }
        before do
          set_current_transaction(transaction)
          transaction.set_action("My action")
        end

        it "doesn't create a new transaction" do
          logs = nil
          expect do
            logs =
              capture_logs do
                capture_std_streams(std_stream, err_stream) do
                  Appsignal.monitor(:action => nil)
                end
              end
          end.to_not(change { created_transactions.count })

          warning = "An active transaction around this 'Appsignal.monitor' call."
          expect(logs).to contains_log(:warn, warning)
          expect(stderr).to include("appsignal WARNING: #{warning}")
        end

        it "does not overwrite the parent transaction's namespace" do
          silence { Appsignal.monitor(:namespace => "custom", :action => nil) }

          expect(transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)
        end

        it "does not overwrite the parent transaction's action" do
          silence { Appsignal.monitor(:action => "custom") }

          expect(transaction).to have_action("My action")
        end

        it "doesn't complete the parent transaction" do
          silence { Appsignal.monitor(:action => nil) }

          expect(transaction).to_not be_completed
        end
      end
    end

    describe ".monitor_and_stop" do
      it "calls Appsignal.stop after the block" do
        allow(Appsignal).to receive(:stop)
        Appsignal.monitor_and_stop(:namespace => "custom", :action => "My Action")

        transaction = last_transaction
        expect(transaction).to have_namespace("custom")
        expect(transaction).to have_action("My Action")
        expect(transaction).to be_completed

        expect(Appsignal).to have_received(:stop).with("monitor_and_stop")
      end
    end

    describe ".tag_request" do
      before { start_agent }

      context "with transaction" do
        let(:transaction) { http_request_transaction }
        before { set_current_transaction(transaction) }

        it "sets tags on the current transaction" do
          Appsignal.tag_request("a" => "b")

          transaction._sample
          expect(transaction).to include_tags("a" => "b")
        end
      end

      context "without transaction" do
        let(:transaction) { nil }

        it "does not set tags on the transaction" do
          expect(Appsignal.tag_request).to be_falsy
          Appsignal.tag_request("a" => "b")

          expect_any_instance_of(Appsignal::Transaction).to_not receive(:set_tags)
        end
      end

      it "also listens to tag_job" do
        expect(Appsignal.method(:tag_job)).to eq(Appsignal.method(:tag_request))
      end

      it "also listens to set_tags" do
        expect(Appsignal.method(:set_tags)).to eq(Appsignal.method(:tag_request))
      end
    end

    describe ".set_params" do
      before { start_agent }

      context "with transaction" do
        let(:transaction) { http_request_transaction }
        before { set_current_transaction(transaction) }

        it "sets parameters on the transaction" do
          Appsignal.set_params("param1" => "value1")

          transaction._sample
          expect(transaction).to include_params("param1" => "value1")
        end

        it "overwrites the params if called multiple times" do
          Appsignal.set_params("param1" => "value1")
          Appsignal.set_params("param2" => "value2")

          transaction._sample
          expect(transaction).to include_params("param2" => "value2")
        end

        it "sets parameters with a block on the transaction" do
          Appsignal.set_params { { "param1" => "value1" } }

          transaction._sample
          expect(transaction).to include_params("param1" => "value1")
        end
      end

      context "without transaction" do
        it "does not set tags on the transaction" do
          Appsignal.set_params("a" => "b")

          expect_any_instance_of(Appsignal::Transaction).to_not receive(:set_params)
        end
      end
    end

    describe ".set_session_data" do
      before { start_agent }

      context "with transaction" do
        let(:transaction) { http_request_transaction }
        before { set_current_transaction(transaction) }

        it "sets session data on the transaction" do
          Appsignal.set_session_data("data" => "value1")

          transaction._sample
          expect(transaction).to include_session_data("data" => "value1")
        end

        it "overwrites the session data if called multiple times" do
          Appsignal.set_session_data("data" => "value1")
          Appsignal.set_session_data("data" => "value2")

          transaction._sample
          expect(transaction).to include_session_data("data" => "value2")
        end

        it "sets session data with a block on the transaction" do
          Appsignal.set_session_data { { "data" => "value1" } }

          transaction._sample
          expect(transaction).to include_session_data("data" => "value1")
        end
      end

      context "without transaction" do
        it "does not set session data on the transaction" do
          Appsignal.set_session_data("a" => "b")

          expect_any_instance_of(Appsignal::Transaction).to_not receive(:set_session_data)
        end
      end
    end

    describe ".set_headers" do
      before { start_agent }

      context "with transaction" do
        let(:transaction) { http_request_transaction }
        before { set_current_transaction(transaction) }

        it "sets request headers on the transaction" do
          Appsignal.set_headers("PATH_INFO" => "/some-path")

          transaction._sample
          expect(transaction).to include_environment("PATH_INFO" => "/some-path")
        end

        it "overwrites the request headers if called multiple times" do
          Appsignal.set_headers("PATH_INFO" => "/some-path1")
          Appsignal.set_headers("PATH_INFO" => "/some-path2")

          transaction._sample
          expect(transaction).to include_environment("PATH_INFO" => "/some-path2")
        end

        it "sets request headers with a block on the transaction" do
          Appsignal.set_headers { { "PATH_INFO" => "/some-path" } }

          transaction._sample
          expect(transaction).to include_environment("PATH_INFO" => "/some-path")
        end
      end

      context "without transaction" do
        it "does not set request headers on the transaction" do
          Appsignal.set_headers("PATH_INFO" => "/some-path")

          expect_any_instance_of(Appsignal::Transaction).to_not receive(:set_headers)
        end
      end
    end

    describe ".set_custom_data" do
      before { start_agent }

      context "with transaction" do
        let(:transaction) { http_request_transaction }
        before { set_current_transaction transaction }

        it "sets custom data on the current transaction" do
          Appsignal.set_custom_data(
            :user => { :id => 123 },
            :organization => { :slug => "appsignal" }
          )

          transaction._sample
          expect(transaction).to include_custom_data(
            "user" => { "id" => 123 },
            "organization" => { "slug" => "appsignal" }
          )
        end
      end

      context "without transaction" do
        it "does not set tags on the transaction" do
          Appsignal.set_custom_data(
            :user => { :id => 123 },
            :organization => { :slug => "appsignal" }
          )

          expect_any_instance_of(Appsignal::Transaction).to_not receive(:set_custom_data)
        end
      end
    end

    describe ".add_breadcrumb" do
      before { start_agent }

      context "with transaction" do
        let(:transaction) { http_request_transaction }
        before { set_current_transaction(transaction) }

        it "adds the breadcrumb to the transaction" do
          Appsignal.add_breadcrumb(
            "Network",
            "http",
            "User made network request",
            { :response => 200 },
            fixed_time
          )

          transaction._sample
          expect(transaction).to include_breadcrumb(
            "http",
            "Network",
            "User made network request",
            { "response" => 200 },
            fixed_time
          )
        end
      end

      context "without transaction" do
        let(:transaction) { nil }

        it "does not add a breadcrumb to any transaction" do
          expect(Appsignal.add_breadcrumb("Network", "http")).to be_falsy
        end
      end
    end

    describe "custom stats" do
      let(:tags) { { :foo => "bar" } }

      describe ".set_gauge" do
        it "should call set_gauge on the extension with a string key and float" do
          expect(Appsignal::Extension).to receive(:set_gauge)
            .with("key", 0.1, Appsignal::Extension.data_map_new)
          Appsignal.set_gauge("key", 0.1)
        end

        it "should call set_gauge with tags" do
          expect(Appsignal::Extension).to receive(:set_gauge)
            .with("key", 0.1, Appsignal::Utils::Data.generate(tags))
          Appsignal.set_gauge("key", 0.1, tags)
        end

        it "should call set_gauge on the extension with a symbol key and int" do
          expect(Appsignal::Extension).to receive(:set_gauge)
            .with("key", 1.0, Appsignal::Extension.data_map_new)
          Appsignal.set_gauge(:key, 1)
        end

        it "should not raise an exception when out of range" do
          expect(Appsignal::Extension).to receive(:set_gauge).with(
            "key",
            10,
            Appsignal::Extension.data_map_new
          ).and_raise(RangeError)
          expect(Appsignal.internal_logger).to receive(:warn)
            .with("Gauge value 10 for key 'key' is too big")

          Appsignal.set_gauge("key", 10)
        end
      end

      describe ".increment_counter" do
        it "should call increment_counter on the extension with a string key" do
          expect(Appsignal::Extension).to receive(:increment_counter)
            .with("key", 1, Appsignal::Extension.data_map_new)
          Appsignal.increment_counter("key")
        end

        it "should call increment_counter with tags" do
          expect(Appsignal::Extension).to receive(:increment_counter)
            .with("key", 1, Appsignal::Utils::Data.generate(tags))
          Appsignal.increment_counter("key", 1, tags)
        end

        it "should call increment_counter on the extension with a symbol key" do
          expect(Appsignal::Extension).to receive(:increment_counter)
            .with("key", 1, Appsignal::Extension.data_map_new)
          Appsignal.increment_counter(:key)
        end

        it "should call increment_counter on the extension with a count" do
          expect(Appsignal::Extension).to receive(:increment_counter)
            .with("key", 5, Appsignal::Extension.data_map_new)
          Appsignal.increment_counter("key", 5)
        end

        it "should not raise an exception when out of range" do
          expect(Appsignal::Extension).to receive(:increment_counter)
            .with("key", 10, Appsignal::Extension.data_map_new).and_raise(RangeError)
          expect(Appsignal.internal_logger).to receive(:warn)
            .with("Counter value 10 for key 'key' is too big")

          Appsignal.increment_counter("key", 10)
        end
      end

      describe ".add_distribution_value" do
        it "should call add_distribution_value on the extension with a string key and float" do
          expect(Appsignal::Extension).to receive(:add_distribution_value)
            .with("key", 0.1, Appsignal::Extension.data_map_new)
          Appsignal.add_distribution_value("key", 0.1)
        end

        it "should call add_distribution_value with tags" do
          expect(Appsignal::Extension).to receive(:add_distribution_value)
            .with("key", 0.1, Appsignal::Utils::Data.generate(tags))
          Appsignal.add_distribution_value("key", 0.1, tags)
        end

        it "should call add_distribution_value on the extension with a symbol key and int" do
          expect(Appsignal::Extension).to receive(:add_distribution_value)
            .with("key", 1.0, Appsignal::Extension.data_map_new)
          Appsignal.add_distribution_value(:key, 1)
        end

        it "should not raise an exception when out of range" do
          expect(Appsignal::Extension).to receive(:add_distribution_value)
            .with("key", 10, Appsignal::Extension.data_map_new).and_raise(RangeError)
          expect(Appsignal.internal_logger).to receive(:warn)
            .with("Distribution value 10 for key 'key' is too big")

          Appsignal.add_distribution_value("key", 10)
        end
      end
    end

    describe ".internal_logger" do
      subject { Appsignal.internal_logger }

      it { is_expected.to be_a Logger }
    end

    describe ".log_formatter" do
      subject { Appsignal.log_formatter.call("Debug", Time.parse("2015-07-08"), nil, "log line") }

      it "formats a log" do
        expect(subject).to eq "[2015-07-08T00:00:00 (process) ##{Process.pid}][Debug] log line\n"
      end

      context "with prefix" do
        subject do
          Appsignal.log_formatter("prefix").call("Debug", Time.parse("2015-07-08"), nil, "log line")
        end

        it "adds a prefix" do
          expect(subject)
            .to eq "[2015-07-08T00:00:00 (process) ##{Process.pid}][Debug] prefix: log line\n"
        end
      end
    end

    describe ".config" do
      subject { Appsignal.config }

      it { is_expected.to be_a Appsignal::Config }
      it "should return configuration" do
        expect(subject[:endpoint]).to eq "https://push.appsignal.com"
      end
    end

    describe ".send_error" do
      let(:error) { ExampleException.new("error message") }
      let(:err_stream) { std_stream }
      let(:stderr) { err_stream.read }
      around do |example|
        keep_transactions { example.run }
      end

      it "sends the error to AppSignal" do
        expect { Appsignal.send_error(error) }.to(change { created_transactions.count }.by(1))

        transaction = last_transaction
        expect(transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)
        expect(transaction).to_not have_action
        expect(transaction).to have_error("ExampleException", "error message")
        expect(transaction).to_not include_tags
        expect(transaction).to be_completed
      end

      context "when given error is not an Exception" do
        let(:error) { "string value" }

        it "logs an error message" do
          logs = capture_logs { Appsignal.send_error(error) }
          expect(logs).to contains_log(
            :error,
            "Appsignal.send_error: Cannot send error. " \
              "The given value is not an exception: #{error.inspect}"
          )
        end

        it "does not send the error" do
          expect { Appsignal.send_error(error) }.to_not(change { created_transactions.count })
        end
      end

      context "when given a block" do
        it "yields the transaction and allows additional metadata to be set" do
          keep_transactions do
            Appsignal.send_error(StandardError.new("my_error")) do |transaction|
              transaction.set_action("my_action")
              transaction.set_namespace("my_namespace")
            end
          end
          expect(last_transaction).to have_namespace("my_namespace")
          expect(last_transaction).to have_action("my_action")
          expect(last_transaction).to have_error("StandardError", "my_error")
        end
      end
    end

    describe ".listen_for_error" do
      around { |example| keep_transactions { example.run } }

      it "records the error and re-raise it" do
        expect do
          expect do
            Appsignal.listen_for_error do
              raise ExampleException, "I am an exception"
            end
          end.to raise_error(ExampleException, "I am an exception")
        end.to change { created_transactions.count }.by(1)

        # Default namespace
        expect(last_transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)
        expect(last_transaction).to have_error("ExampleException", "I am an exception")
        expect(last_transaction).to_not include_tags
      end

      context "with tags" do
        it "adds tags to the transaction" do
          expect do
            expect do
              Appsignal.listen_for_error("foo" => "bar") do
                raise ExampleException, "I am an exception"
              end
            end.to raise_error(ExampleException, "I am an exception")
          end.to change { created_transactions.count }.by(1)

          # Default namespace
          expect(last_transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)
          expect(last_transaction).to have_error("ExampleException", "I am an exception")
          expect(last_transaction).to include_tags("foo" => "bar")
        end
      end

      context "with a custom namespace" do
        it "adds the namespace to the transaction" do
          expect do
            expect do
              Appsignal.listen_for_error(nil, "custom_namespace") do
                raise ExampleException, "I am an exception"
              end
            end.to raise_error(ExampleException, "I am an exception")
          end.to change { created_transactions.count }.by(1)

          # Default namespace
          expect(last_transaction).to have_namespace("custom_namespace")
          expect(last_transaction).to have_error("ExampleException", "I am an exception")
          expect(last_transaction).to_not include_tags
        end
      end
    end

    describe ".set_error" do
      let(:err_stream) { std_stream }
      let(:stderr) { err_stream.read }
      let(:error) { ExampleException.new("I am an exception") }
      let(:transaction) { http_request_transaction }
      around { |example| keep_transactions { example.run } }

      context "when there is an active transaction" do
        before { set_current_transaction(transaction) }

        it "adds the error to the active transaction" do
          Appsignal.set_error(error)

          transaction._sample
          expect(transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)
          expect(transaction).to have_error("ExampleException", "I am an exception")
          expect(transaction).to_not include_tags
        end

        context "when the error is not an Exception" do
          let(:error) { Object.new }

          it "does not set an error" do
            silence { Appsignal.set_error(error) }

            transaction._sample
            expect(transaction).to_not have_error
            expect(transaction).to_not include_tags
          end

          it "logs an error" do
            logs = capture_logs { Appsignal.set_error(error) }
            expect(logs).to contains_log(
              :error,
              "Appsignal.set_error: Cannot set error. " \
                "The given value is not an exception: #{error.inspect}"
            )
          end
        end

        context "when given a block" do
          it "yields the transaction and allows additional metadata to be set" do
            Appsignal.set_error(StandardError.new("my_error")) do |t|
              t.set_action("my_action")
              t.set_namespace("my_namespace")
            end

            expect(transaction).to have_namespace("my_namespace")
            expect(transaction).to have_action("my_action")
            expect(transaction).to have_error("StandardError", "my_error")
          end
        end
      end

      context "when there is no active transaction" do
        it "does nothing" do
          Appsignal.set_error(error)

          expect(transaction).to_not have_error
        end
      end
    end

    describe ".report_error" do
      let(:err_stream) { std_stream }
      let(:stderr) { err_stream.read }
      let(:error) { ExampleException.new("error message") }
      before { start_agent }
      around { |example| keep_transactions { example.run } }

      context "when the error is not an Exception" do
        let(:error) { Object.new }

        it "does not set an error" do
          silence { Appsignal.report_error(error) }

          expect(last_transaction).to_not have_error
        end

        it "logs an error" do
          logs = capture_logs { Appsignal.report_error(error) }
          expect(logs).to contains_log(
            :error,
            "Appsignal.report_error: Cannot set error. " \
              "The given value is not an exception: #{error.inspect}"
          )
        end
      end

      context "when there is no active transaction" do
        it "creates a new transaction" do
          expect do
            Appsignal.report_error(error)
          end.to(change { created_transactions.count }.by(1))
        end

        it "completes the transaction" do
          Appsignal.report_error(error)

          expect(last_transaction).to be_completed
        end

        context "when given a block" do
          it "yields the transaction and allows additional metadata to be set" do
            Appsignal.report_error(error) do |t|
              t.set_action("my_action")
              t.set_namespace("my_namespace")
              t.set_tags(:tag1 => "value1")
            end

            transaction = last_transaction
            expect(transaction).to have_namespace("my_namespace")
            expect(transaction).to have_action("my_action")
            expect(transaction).to have_error("ExampleException", "error message")
            expect(transaction).to include_tags("tag1" => "value1")
            expect(transaction).to be_completed
          end
        end
      end

      context "when there is an active transaction" do
        let(:transaction) { http_request_transaction }
        before { set_current_transaction(transaction) }

        it "adds the error to the active transaction" do
          Appsignal.report_error(error)

          expect(last_transaction).to eq(transaction)
          transaction._sample
          expect(transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)
          expect(transaction).to have_error("ExampleException", "error message")
        end

        it "does not complete the transaction" do
          Appsignal.report_error(error)

          expect(last_transaction).to_not be_completed
        end

        context "when given a block" do
          it "yields the transaction and allows additional metadata to be set" do
            Appsignal.report_error(error) do |t|
              t.set_action("my_action")
              t.set_namespace("my_namespace")
              t.set_tags(:tag1 => "value1")
            end

            transaction._sample
            expect(transaction).to have_namespace("my_namespace")
            expect(transaction).to have_action("my_action")
            expect(transaction).to have_error("ExampleException", "error message")
            expect(transaction).to include_tags("tag1" => "value1")
            expect(transaction).to_not be_completed
          end
        end
      end
    end

    describe ".set_action" do
      around { |example| keep_transactions { example.run } }

      context "with current transaction" do
        before { set_current_transaction(transaction) }

        it "sets the namespace on the current transaction" do
          Appsignal.set_action("custom")

          expect(transaction).to have_action("custom")
        end

        it "does not set the action if the action is nil" do
          Appsignal.set_action(nil)

          expect(transaction).to_not have_action
        end
      end

      context "without current transaction" do
        it "does not set ther action" do
          Appsignal.set_action("custom")

          expect(transaction).to_not have_action
        end
      end
    end

    describe ".set_namespace" do
      around { |example| keep_transactions { example.run } }

      context "with current transaction" do
        before { set_current_transaction(transaction) }

        it "should set the namespace to the current transaction" do
          Appsignal.set_namespace("custom")

          expect(transaction).to have_namespace("custom")
        end

        it "does not update the namespace if the namespace is nil" do
          Appsignal.set_namespace(nil)

          expect(transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)
        end
      end

      context "without current transaction" do
        it "does not update the namespace" do
          expect(transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)

          Appsignal.set_namespace("custom")

          expect(transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)
        end
      end
    end

    describe ".instrument" do
      it_behaves_like "instrument helper" do
        let(:instrumenter) { Appsignal }
        before { set_current_transaction(transaction) }
      end
    end

    describe ".instrument_sql" do
      around { |example| keep_transactions { example.run } }
      before { set_current_transaction(transaction) }

      it "creates an SQL event on the transaction" do
        result =
          Appsignal.instrument_sql "name", "title", "body" do
            "return value"
          end

        expect(result).to eq "return value"
        expect(transaction).to include_event(
          "name" => "name",
          "title" => "title",
          "body" => "body",
          "body_format" => Appsignal::EventFormatter::SQL_BODY_FORMAT
        )
      end
    end

    describe ".ignore_instrumentation_events" do
      around { |example| keep_transactions { example.run } }
      let(:transaction) { http_request_transaction }

      context "with current transaction" do
        before { set_current_transaction(transaction) }

        it "does not record events on the transaction" do
          expect(transaction).to receive(:pause!).and_call_original
          expect(transaction).to receive(:resume!).and_call_original

          Appsignal.instrument("register.this.event") { :do_nothing }
          Appsignal.ignore_instrumentation_events do
            Appsignal.instrument("dont.register.this.event") { :do_nothing }
          end

          expect(transaction).to include_event("name" => "register.this.event")
          expect(transaction).to_not include_event("name" => "dont.register.this.event")
        end
      end

      context "without current transaction" do
        let(:transaction) { nil }

        it "does not crash" do
          Appsignal.ignore_instrumentation_events { :do_nothing }
        end
      end
    end
  end

  describe "._start_logger" do
    let(:out_stream) { std_stream }
    let(:output) { out_stream.read }
    let(:log_path) { File.join(tmp_dir, "log") }
    let(:log_file) { File.join(log_path, "appsignal.log") }
    let(:log_level) { "debug" }

    before do
      FileUtils.mkdir_p(log_path)
      # Clear state from previous test
      Appsignal.internal_logger = nil
      if Appsignal.instance_variable_defined?(:@in_memory_logger)
        Appsignal.remove_instance_variable(:@in_memory_logger)
      end
    end
    after { FileUtils.rm_rf(log_path) }

    def initialize_config
      Appsignal._config = project_fixture_config(
        "production",
        :log_path => log_path,
        :log_level => log_level
      )
      Appsignal.internal_logger.error("Log in memory line 1")
      Appsignal.internal_logger.debug("Log in memory line 2")
      expect(Appsignal.in_memory_logger.messages).to_not be_empty
    end

    context "when the log path is writable" do
      context "when the log file is writable" do
        let(:log_file_contents) { File.read(log_file) }

        before do
          capture_stdout(out_stream) do
            initialize_config
            Appsignal._start_logger
            Appsignal.internal_logger.error("Log to file")
          end
          expect(Appsignal.internal_logger).to be_a(Appsignal::Utils::IntegrationLogger)
        end

        it "logs to file" do
          expect(File.exist?(log_file)).to be_truthy
          expect(log_file_contents).to include "[ERROR] Log to file"
          expect(output).to be_empty
        end

        context "with log level info" do
          let(:log_level) { "info" }

          it "amends info log level and higher memory log messages to log file" do
            expect(log_file_contents).to include "[ERROR] appsignal: Log in memory line 1"
            expect(log_file_contents).to_not include "[DEBUG]"
          end
        end

        context "with log level debug" do
          let(:log_level) { "debug" }

          it "amends debug log level and higher memory log messages to log file" do
            expect(log_file_contents).to include "[ERROR] appsignal: Log in memory line 1"
            expect(log_file_contents).to include "[DEBUG] appsignal: Log in memory line 2"
          end
        end

        it "clears the in memory log after writing to the new logger" do
          expect(Appsignal.instance_variable_get(:@in_memory_logger)).to be_nil
        end
      end

      context "when the log file is not writable" do
        before do
          FileUtils.touch log_file
          FileUtils.chmod 0o444, log_file

          capture_stdout(out_stream) do
            initialize_config
            Appsignal._start_logger
            Appsignal.internal_logger.error("Log to not writable log file")
            expect(Appsignal.internal_logger).to be_a(Appsignal::Utils::IntegrationLogger)
          end
        end

        it "logs to stdout" do
          expect(File.writable?(log_file)).to be_falsy
          expect(output).to include "[ERROR] appsignal: Log to not writable log file"
        end

        it "amends in memory log to stdout" do
          expect(output).to include "[ERROR] appsignal: Log in memory"
        end

        it "clears the in memory log after writing to the new logger" do
          expect(Appsignal.instance_variable_get(:@in_memory_logger)).to be_nil
        end

        it "outputs a warning" do
          expect(output).to include \
            "[WARN] appsignal: Unable to start internal logger with log path '#{log_file}'.",
            "[WARN] appsignal: Permission denied"
        end
      end
    end

    context "when the log path and fallback path are not writable" do
      before do
        FileUtils.chmod 0o444, log_path
        FileUtils.chmod 0o444, Appsignal::Config.system_tmp_dir

        capture_stdout(out_stream) do
          initialize_config
          Appsignal._start_logger
          Appsignal.internal_logger.error("Log to not writable log path")
        end
        expect(Appsignal.internal_logger).to be_a(Appsignal::Utils::IntegrationLogger)
      end
      after do
        FileUtils.chmod 0o755, Appsignal::Config.system_tmp_dir
      end

      it "logs to stdout" do
        expect(File.writable?(log_path)).to be_falsy
        expect(output).to include "[ERROR] appsignal: Log to not writable log path"
      end

      it "amends in memory log to stdout" do
        expect(output).to include "[ERROR] appsignal: Log in memory"
      end

      it "outputs a warning" do
        expect(output).to include \
          "appsignal: Unable to log to '#{log_path}' " \
            "or the '#{Appsignal::Config.system_tmp_dir}' fallback."
      end
    end

    context "when on Heroku" do
      before do
        capture_stdout(out_stream) do
          initialize_config
          Appsignal._start_logger
          Appsignal.internal_logger.error("Log to stdout")
        end
        expect(Appsignal.internal_logger).to be_a(Appsignal::Utils::IntegrationLogger)
      end
      around { |example| recognize_as_heroku { example.run } }

      it "logs to stdout" do
        expect(output).to include "[ERROR] appsignal: Log to stdout"
      end

      it "amends in memory log to stdout" do
        expect(output).to include "[ERROR] appsignal: Log in memory"
      end

      it "clears the in memory log after writing to the new logger" do
        expect(Appsignal.instance_variable_get(:@in_memory_logger)).to be_nil
      end
    end

    describe "#logger#level" do
      subject { Appsignal.internal_logger.level }

      context "when there is no config" do
        before do
          capture_stdout(out_stream) do
            Appsignal._start_logger
          end
        end

        it "sets the log level to info" do
          expect(subject).to eq Logger::INFO
        end
      end

      context "when there is a config" do
        context "when log level is configured to debug" do
          before do
            capture_stdout(out_stream) do
              initialize_config
              Appsignal.config[:log_level] = "debug"
              Appsignal._start_logger
            end
          end

          it "sets the log level to debug" do
            expect(subject).to eq Logger::DEBUG
          end
        end
      end
    end
  end
end
