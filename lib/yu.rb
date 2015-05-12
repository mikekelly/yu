require 'yu/version'
require 'commander'

module Yu
  class CLI
    include Commander::Methods

    def self.call(*args)
      new(*args).call
    end

    def call
      program :name, 'yu'
      program :version, VERSION
      program :description, 'Helps you manage your microservices'

      command :test do |c|
        c.syntax = 'yu test'
        c.description = 'Run tests for service(s)'
        c.action(method(:test))
      end

      command :build do |c|
        c.syntax = 'yu build'
        c.description = 'Build image for service(s)'
        c.action(method(:build))
      end

      command :shell do |c|
        c.syntax = 'yu shell'
        c.description = 'Start a shell container for a service'
        c.option '--test'
        c.action(method(:shell))
      end

      command :reset do |c|
        c.syntax = 'yu reset'
        c.description = 'Fresh build of images for all services and restart'
        c.option '--without-cache'
        c.action(method(:reset))
      end

      command :doctor do |c|
        c.syntax = 'yu doctor'
        c.description = 'Check your environment is ready to yu'
        c.action(method(:doctor))
      end

      command :restart do |c|
        c.syntax = 'yu restart'
        c.description = 'Restart containers for service(s)'
        c.action(method(:restart))
      end

      command :start do |c|
        c.syntax = 'yu start'
        c.description = 'Start containers containers for service(s)'
        c.action(method(:restart))
      end

      command :recreate do |c|
        c.syntax = 'yu recreate'
        c.description = 'Recreate containers for service(s)'
        c.action(method(:recreate))
      end

      global_option('-V', '--verbose', 'Verbose output') { $verbose_mode = true }

      run!
    end

    private

    def test(args, options)
      if args.none?
        target_services = testable_services
      else
        target_services = args.map(&method(:normalise_service_name_from_dir))
      end

      results = target_services.map do |service|
        info "Running tests for #{service}..."
        run_command(
          "docker-compose run --rm #{service} bin/test",
          exit_on_failure: false,
        )
      end

      exit 1 unless results.all?(&:success?)
    end

    def build(args, options)
      target_services = args.map(&method(:normalise_service_name_from_dir))
      if target_services.none?
        target_gemfiled_services = gemfiled_services
      else
        target_gemfiled_services = gemfiled_services & target_services
      end

      target_gemfiled_services.each(&method(:package_gems_for_service))
      info "Building images..."
      execute_command("docker-compose build #{target_services.join(" ")}")
    end

    def shell(args, options)
      case args.count
      when 0
        info "Please provide service"
        exit 1
      when 1
        target_service = normalise_service_name_from_dir(args.first)
        env_option = options.test ? "-e APP_ENV=test" : ""
        info "Loading #{"test" if options.test} shell for #{target_service}..."
        execute_command("docker-compose run --rm #{env_option} #{target_service} bash")
      else
        info "One at a time please!"
        exit 1
      end
    end

    def reset(args, options)
      info "Packaging gems in all services containing a Gemfile"
      gemfiled_services.each(&method(:package_gems_for_service))
      info "Killing any running containers"
      run_command("docker-compose kill")
      info "Removing all existing containers"
      run_command "docker-compose rm --force"
      info "Building fresh images"
      run_command "docker-compose build #{'--no-cache' if options.without_cache}"
      if File.exists? 'seed'
        info "Seeding system state"
        run_command "./seed"
      end
      info "Bringing containers up for all services"
      run_command "docker-compose up -d --no-recreate"
    end

    def doctor(args, options)
      run_command "docker", showing_output: false do
        info "Please ensure you have docker working"
        exit 1
      end
      run_command "docker-compose --version", showing_output: false do
        info "Please ensure you have docker-compose working"
        exit 1
      end
      run_command "docker-compose ps", showing_output: false do
        info "Your current directory does not contain a docker-compose.yml"
        exit 1
      end
      info "Everything looks good."
    end

    def restart(args, options)
      service_list = args.map(&method(:normalise_service_name_from_dir)).join(" ")
      run_command "docker-compose kill #{service_list}"
      run_command "docker-compose up -d --no-recreate #{service_list}"
    end

    def recreate(args, options)
      service_list = args.map(&method(:normalise_service_name_from_dir)).join(" ")
      run_command "docker-compose kill #{service_list}"
      run_command "docker-compose rm --force #{service_list}"
      run_command "docker-compose up -d #{service_list}"
    end

    def run_command(command, showing_output: true, exit_on_failure: true)
      unless showing_output || verbose_mode?
        command = "#{command} &>/dev/null"
      end

      pid = fork { execute_command(command) }
      _, process = Process.waitpid2(pid)

      process.tap do |result|
        unless result.success?
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

    def package_gems_for_service(service)
      info "Packaging gems for #{service}"
      run_command("cd #{service} && bundle package --all")
    end

    def gemfiled_services
      services_with_file("Gemfile")
    end

    def testable_services
      services_with_file("bin/test")
    end

    def normalise_service_name_from_dir(service_name_or_dir)
      File.basename(service_name_or_dir)
    end

    def services_with_file(file)
      Dir.glob("*/#{file}").map { |dir_path| dir_path.split("/").first }
    end

    def execute_command(command)
      info "Executing: #{command}" if verbose_mode?
      exec(command)
    end

    def info(message)
      say "[yu] #{message}"
    end

    def verbose_mode?
      !!$verbose_mode
    end
  end
end
