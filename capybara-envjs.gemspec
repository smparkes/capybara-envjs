# -*- mode: ruby; encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'capybara/envjs/version'

Gem::Specification.new do |s|
  s.name = "capybara-envjs"
  s.rubyforge_project = "capybara-envjs"
  s.version = Capybara::Envjs::VERSION

  s.authors = ["Steven Parkes"]
  s.email = ["smparkes@smparkes.net"]
  s.description = "capybara-envjs is a Capybara driver for the envjs gem. It is similar to Capybara's rack-test driver in that it runs tests against your rack application directly but fully supports javascript in your application."

  s.files = Dir.glob("{lib,spec}/**/*") + %w(README.rdoc CHANGELOG.rdoc)
  s.extra_rdoc_files = ["README.rdoc"]

  s.homepage = "http://github.com/smparkes/capybara-envjs"
  s.rdoc_options = ["--main", "README.rdoc"]
  s.require_paths = ["lib"]
  s.rubygems_version = "1.3.6"
  s.summary = "Capybara driver for envjs"

  s.add_runtime_dependency("capybara", "~> 0.4.0")
  s.add_runtime_dependency("envjs", ">= 0.3.7")

  s.add_development_dependency("bundler", "~> 1.0")
  s.add_development_dependency("rspec", "~> 2.0")
  s.add_development_dependency("rack-test", ">= 0.5.4")
  s.add_development_dependency("sinatra", "~> 1.0")
end
