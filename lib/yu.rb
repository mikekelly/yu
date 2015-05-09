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
      program :description, 'TODO'

      command :test do |c|
        c.syntax = 'yu test'
        c.description = 'Just a test'
        c.action do |args, options|
          say 'Hello world'
        end
      end

      run!
    end
  end
end
