require 'capybara'
require 'capybara/driver/envjs_driver'

if Object.const_defined? :Cucumber
  require 'capybara/envjs/cucumber'
end
