require "rubygems"
gem "rspec"
require "selenium-webdriver"

require_relative "test_properties.rb"
require_relative "test_context.rb"
require_relative "email_helper.rb"
require_relative "login_helper.rb"
require_relative "doc_helper.rb"

class Helpers
  attr_accessor :wait
  attr_accessor :ctx
  attr_accessor :driver
  attr_accessor :emailhelper
  attr_accessor :loginhelper
  attr_accessor :dochelper
  attr_accessor :lang

  def initialize
    @wait = Selenium::WebDriver::Wait.new(:timeout => 60)
    @ctx = TestContext.new
    @driver = @ctx.createWebDriver
    @driver.manage.window.resize_to(1080, 800)
    @emailhelper = EmailHelper.new(@ctx, @driver, self)
    @loginhelper = LoginHelper.new(@ctx, @driver, self)
    @dochelper = DocHelper.new(@ctx, @driver, self)
    @lang = ENV['SELENIUM_TEST_LANG']
  end

  def quit
    @driver.quit
  end

  def click(css)
    @wait.until { (@driver.find_element :css => css).displayed? }
    (@driver.find_element :css => css).click
  end

  # Currently, nothing more than calling @wait.until, but handy to
  # have for extra instrumentation, catching exceptions etc.
  def wait_until (&block)
    return @wait.until { yield }
  end

  def screenshot(screenshot_name)
    @driver.save_screenshot('selenium_screenshots/' + @lang + '_' + screenshot_name + '.png')
  end
end
