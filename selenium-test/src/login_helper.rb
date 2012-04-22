require "rubygems"
gem "rspec"
require "selenium-webdriver"

class LoginHelper

  def initialize(ctx, driver, wait)
    @driver = driver
    @ctx = ctx
    @wait = wait
  end

  def login_as(email, password)
    @driver.get(@ctx.createKontrakcjaURL "/")

    (@wait.until { @driver.find_element :css => "a.login-button" }).click

    @wait.until { @driver.find_element :id => "loginForm" }

    (@wait.until { @driver.find_element :name => "email" }).send_keys email
    (@wait.until { @driver.find_element :name => "password" }).send_keys password

    (@wait.until { @driver.find_element :css => "#loginForm a.submit" }).click
    (@wait.until { @driver.find_element :css => "a.logout" })

    if (@driver.find_elements :id => "toscontainer").length>0 then
      (@wait.until { @driver.find_element :css => "input#tos" }).click
      (@wait.until { @driver.find_element :css => "#toscontainer a.submit" }).click
    end

    @wait.until { @driver.find_element :css => "a.documenticon" }
  end

  def set_name(fstname, sndname)
    (@wait.until { @driver.find_element :xpath => "//a[@href='/account']" }).click
    (@wait.until { @driver.find_element :xpath => "//input[@name='fstname']" }).clear
    (@wait.until { @driver.find_element :xpath => "//input[@name='fstname']" }).send_keys fstname
    (@wait.until { @driver.find_element :xpath => "//input[@name='sndname']" }).clear
    (@wait.until { @driver.find_element :xpath => "//input[@name='sndname']" }).send_keys sndname
    (@wait.until { @driver.find_element :xpath => "//a[contains(@class,'green') and contains(@class,'submit')]" }).click
  end

  def logout
    puts "logout"
    (@wait.until { (@driver.find_element :css => "a.logout") }).click
    @wait.until { @driver.find_element :css => "a.login-button" }
    puts "logged out"
  end
end
