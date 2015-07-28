require 'pathname'
require 'erb'
require 'ostruct'

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
      program :description, 'A container framework based on docker-compose'

      default_command :help

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
        c.action(method(:start))
      end

      command :recreate do |c|
        c.syntax = 'yu recreate'
        c.description = 'Recreate containers for service(s)'
        c.action(method(:recreate))
      end

      command :service do |c|
        c.syntax = 'yu service'
        c.description = 'Create service from template'
        c.action(method(:service))
      end

      command :run do |c|
        c.syntax = 'yu run'
        c.description = 'Create a temp container to run a command'
        c.option '--test'
        c.action(method(:run))
      end

      global_option('-V', '--verbose', 'Verbose output') { $verbose_mode = true }
      global_option('--no-rm', 'Do not remove containers used for running commands') { $dont_remove_containers = true }

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
          "docker-compose run #{"--rm" if remove_containers?} #{service} bin/test",
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
        execute_command("docker-compose run #{"--rm" if remove_containers?} #{env_option} #{target_service} bash")
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
      run_seed
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

    def start(args, options)
      service_list = args.map(&method(:normalise_service_name_from_dir)).join(" ")
      run_command "docker-compose up -d --no-recreate #{service_list}"
    end

    def restart(args, options)
      service_list = args.map(&method(:normalise_service_name_from_dir)).join(" ")
      run_command "docker-compose kill #{service_list}"
      run_command "docker-compose up -d --no-recreate #{service_list}"
    end

    def recreate(args, options)
      # TODO: check all services have vendor/cache
      service_list = args.map(&method(:normalise_service_name_from_dir)).join(" ")
      run_command "docker-compose kill #{service_list}"
      run_command "docker-compose rm --force #{service_list}"
      run_seed
      run_command "docker-compose up -d --no-recreate #{service_list}"
    end

    def run(args, options)
      command = args.join(" ")
      env_option = options.test ? "-e APP_ENV=test" : ""
      execute_command "docker-compose run #{"--rm" if remove_containers?} #{env_option} #{command}"
    end

    def service(args, options)
      service_names = args.map(&method(:normalise_service_name_from_dir))
      existing_services = get_existing_services(service_names)
      if existing_services.any?
        info "The following services already exist in the project: #{existing_services.join(', ')}"
      else
        service_names.each do |service_name|
          info "Generating service scaffold for #{service_name}..."
          copy_template_into_dir(service_name)
          render_and_remove_erb_files(service_name: service_name)
          append_partial_to_docker_compose_yml(service_name)
        end
      end
    end

    def run_seed
      if File.exists? 'seed'
        info "Seeding system state"
        run_command "./seed"
      end
    end

    def get_existing_services(service_names)
      service_names.select { |service_name| Pathname(service_name).exist? }
    end

    def copy_template_into_dir(options={})
      service_name = options.fetch(:service_name)

      run_command("cp -aR #{template_dir} #{service_name}")
    end

    def render_and_remove_erb_files(options)
      service_name = options.fetch(:service_name)
      template_context = OpenStruct.new(options).instance_eval { binding }

      Dir.glob("#{service_name}/**/{*,.*}.erb").each do |erb_file_path|
        template_string = File.read(erb_file_path)
        template = ERB.new(template_string)
        rendered_content = template.result(template_context)
        target_file_path = erb_file_path.match(/(.*)\.erb$/)[1]

        File.write(target_file_path, rendered_content)
        run_command "rm #{erb_file_path}"
      end
    end

    def append_partial_to_docker_compose_yml(service_name)
      partial_path = "#{service_name}/_docker-compose.yml"
      run_command "cat #{partial_path} >> docker-compose.yml"
      run_command "rm #{partial_path}"
    end

    def template_dir
      relative_path = Pathname(__FILE__).dirname + "templates/ruby_base"
      relative_path.realpath
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
      run_command("cd #{service} && bundle package --all --no-install")
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

    def remove_containers?
      !$dont_remove_containers
    end
  end
end
