require 'yu/version'
require 'commander'
require 'open3'

module Yu
  class CLI
    include Commander::Methods

    def self.call(*args)
      new(*args).call
    end

    def call
      program :name, 'yu'
      program :version, VERSION
      program :description, 'TODO'

      command :test do |c|
        c.syntax = 'yu test'
        c.description = 'Run container tests'
        c.action(method(:test))
      end

      command :build do |c|
        c.syntax = 'yu build'
        c.description = 'Build container(s)'
        c.action(method(:build))
      end

      command :shell do |c|
        c.syntax = 'yu shell'
        c.description = 'Start a shell container'
        c.option '--test'
        c.action(method(:shell))
      end

      global_option('-V', '--verbose', 'Verbose output') { $verbose_mode = true }

      run!
    end

    private

    def test(args, options)
      if args.none?
        target_containers = testable_containers
      else
        target_containers = args.map(&method(:normalise_container_name_from_dir))
      end

      results = target_containers.map do |container|
        info "Running tests for #{container}..."
        run_command(
          "docker-compose run --rm #{container} bin/test",
          showing_output: true,
          exit_on_failure: false,
        )
      end

      exit 1 unless results.all?(&:success?)
    end

    def build(args, options)
      target_containers = args.map(&method(:normalise_container_name_from_dir))
      if target_containers.none?
        target_gemfiled_containers = gemfiled_containers
      else
        target_gemfiled_containers = gemfiled_containers & target_containers
      end

      target_gemfiled_containers.each(&method(:package_gems_for_container))
      exec("docker-compose build #{target_containers.join(" ")}")
    end

    def shell(args, options)
      case args.count
      when 0
        info "Please provide container"
        exit 1
      when 1
        target_container = normalise_container_name_from_dir(args.first)
        env_option = options.test ? "-e APP_ENV=test" : ""
        exec("docker-compose run --rm #{env_option} #{target_container} bash")
      else
        info "One at a time please!"
        exit 1
      end
    end

    def package_gems_for_container(container)
      info "Packaging gems for #{container}"
      run_command("cd #{container} && bundle package --all", showing_output: true)
    end

    def gemfiled_containers
      containers_with_file("Gemfile")
    end

    def testable_containers
      containers_with_file("bin/test")
    end

    def normalise_container_name_from_dir(container_name_or_dir)
      File.basename(container_name_or_dir)
    end

    def run_command(command, showing_output: false, exit_on_failure: true)
      info "Running command: #{command}" if verbose_mode?
      _, out_and_err, wait_thread = Open3.popen2e(command)
      while line = out_and_err.gets
        puts line if showing_output || verbose_mode?
      end

      wait_thread.value.tap do |terminated_process|
        unless terminated_process.success?
          if block_given?
            yield
          else
            if exit_on_failure
              info "Command failed: #{command}"
              info "Exiting..."
              exit 1
            end
          end
        end
      end
    end

    def containers_with_file(file)
      Dir.glob("**/#{file}").map { |dir_path| dir_path.split("/").first }
    end

    def verbose_mode?
      !!$verbose_mode
    end

    def info(message)
      say "[yu] #{message}"
    end
  end
end
