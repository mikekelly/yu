# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'yu/version'

Gem::Specification.new do |spec|
  spec.name          = "yu"
  spec.version       = Yu::VERSION
  spec.authors       = ["Mike Kelly"]
  spec.email         = ["mikekelly321@gmail.com"]

  spec.summary       = %q{A simple docker container framework}
  spec.description   = %q{Framework for managing docker containers based on docker-compose}
  spec.homepage      = "https://github.com/mikekellly/yu"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "commander"
  spec.add_runtime_dependency "open4"

  spec.add_development_dependency "bundler", "~> 1.9"
  spec.add_development_dependency "rake", "~> 10.0"
end
