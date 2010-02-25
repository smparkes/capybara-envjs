require File.expand_path('../spec_helper', File.dirname(__FILE__))

describe Capybara::Driver::Envjs do
  driver = nil
  before do
    @driver = (driver ||= Capybara::Driver::Envjs.new(TestApp))
  end
  after do
    @driver.browser["window"].location = "about:blank"
  end

  it_should_behave_like "driver"
  it_should_behave_like "driver with javascript support"
  it_should_behave_like "driver with header support"
  it_should_behave_like "driver with node path support"
  
end
