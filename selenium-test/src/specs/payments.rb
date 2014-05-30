require "rubygems"
gem "rspec"
require_relative "../helpers.rb"

describe "subscribe with a credit card" do

  before(:each) do
    @h = Helpers.new
  end

  append_after(:each) do
    @h.quit
  end

  it "new user can pay with credit card on outside" do
    random_email = @h.emailhelper.random_email()

    puts "go to price plan page"
    @h.driver.get(@h.ctx.createKontrakcjaURL ("/" + @h.lang + "/pricing"))
    (@h.wait_until { (@h.driver.find_element :css => ".plan-container.team a.button.action-sign-up").displayed? })
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team a.button.action-sign-up" }).click
    
    puts "fill in a name"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .first_name input" }).send_keys "Random"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .last_name input" }).send_keys "Person"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .email input" }).send_keys random_email

    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .card_number input" }).send_keys "4111 1111 1111 1111"
    sel =(@h.wait_until { @h.driver.find_element :css => ".plan-container.team .field.expires .year select" })

    sel.find_elements( :css => ".year select option" ).find do |option|
      option.text == "20"
    end.click

    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .field.cvv input" }).send_keys "111"

    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team a.s-subscribe" }).click

    (@h.wait_until { @h.driver.find_element :css => ".modal-footer a .label"}).click

  end

  it "new user can pay with credit card on outside after typing stuff in wrong" do
    random_email = @h.emailhelper.random_email()

    puts "go to price plan page"
    @h.driver.get(@h.ctx.createKontrakcjaURL ("/" + @h.lang + "/pricing"))
    (@h.wait_until { (@h.driver.find_element :css => ".plan-container.team a.button.action-sign-up").displayed? })
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team a.button.action-sign-up" }).click
    
    puts "fill in a name"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .first_name input" }).send_keys "Random"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .last_name input" }).send_keys "Person"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .email input" }).send_keys random_email

    puts "fill in cc number (incorrect)"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .card_number input" }).send_keys "4111 1111 1111 1110"
    sel =(@h.wait_until { @h.driver.find_element :css => ".plan-container.team .field.expires .year select" })

    sel.find_elements( :css => "option" ).find do |option|
      option.text == "20"
    end.click

    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .field.cvv input" }).send_keys "111"

    puts "click"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .s-subscribe" }).click

    puts "erase the input"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .card_number input" }).send_keys "\xEE\x80\x83"
    #@h.driver.type({:css => ".plan-container.team .card_number input"}, "")
    puts "fill in cc number (correct)"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .card_number input" }).send_keys "1"

    puts "click subscribe"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .s-subscribe" }).click

    # if the test fails here please read http://wiki.scrive.lan/index.php?title=Selenium_Test_Introduction#Payments_tests_fail
    (@h.wait_until { @h.driver.find_element :css => ".modal-footer a.button"}).click

  end

  it "new user can pay on the inside with popup" do
    random_email = @h.emailhelper.random_email()

    @h.driver.get(@h.ctx.createKontrakcjaURL ("/" + @h.lang + "/signup"))

    puts "request an account and make sure you get a flash back"
    (@h.wait_until { @h.driver.find_element :css => ".signup input" }).send_keys random_email
    (@h.wait_until { @h.driver.find_element :css => ".signup a.button" }).click
    (@h.wait_until { @h.driver.find_element :css => ".flash-body" })

    puts "we should get an email to a page where we can accept the tos"
    @h.emailhelper.follow_link_in_latest_mail_for random_email
    puts "accept the tos"
    @h.wait_until { @h.driver.find_element :css => ".checkbox[name=tos]" }.click

    puts "fill in a name"
    (@h.wait_until { @h.driver.find_element :name => "fullname" }).send_keys "Random Person"

    puts "fill in the password details correctly"
    (@h.wait_until { @h.driver.find_element :name => "password" }).send_keys "password-123"
    (@h.wait_until { @h.driver.find_element :name => "password2" }).send_keys "password-123"

    puts "submit the signup form"
    (@h.wait_until { @h.driver.find_element :css => ".account-setup a.button" }).click

    puts "should see blocking header"
    (@h.wait_until { @h.driver.find_element :css => ".blocking-info" }).click
    puts "waiting for recurly form"
    (@h.wait_until { @h.driver.find_element :css => "form.recurly" })
    puts "sign up for teamplan"

    @h.driver.execute_script "$('.plan-container.team a.button-green.action-sign-up').click();"
    puts "fill in cc"
    #(@h.wait_until { @h.driver.find_element :css => ".plan-container.team .field.card_number input" }).send_keys "4111 1111 1111 1111"
    @h.driver.execute_script "$('.plan-container.team .field.card_number input').val('4111 1111 1111 1111');"
    puts "select expiration date"
    @h.driver.execute_script "$('.plan-container.team .field.expires .year select').val('20');"
    #sel =(@h.wait_until { @h.driver.find_element :css => ".plan-container.team .field.expires .year select" })

    #sel.find_elements( :css => "option" ).find do |option|
    #  option.text == "20"
    #end.click
    puts "fill in cvv"
    @h.driver.execute_script "$('.plan-container.team .field.cvv input').val('111');"
    #(@h.wait_until { @h.driver.find_element :css => ".plan-container.team .field.cvv input" }).send_keys "111"
    puts "click subscribe"

    @h.driver.execute_script "$('.plan-container.team .s-subscribe').click();"
    #(@h.wait_until { @h.driver.find_element :css => ".plan-container.team .s-subscribe" }).click
    # the page should reload now, so wait for the subscribe button to disappear
    (@h.wait_until { (@h.driver.find_elements :css => ".plan-container.team .s-subscribe").size == 0 })
    # and wait for the page to finish [re]loading
    @h.wait_until { @h.driver.find_element :css => "a.js-logout" }

    puts "blocking info should disappear"
    @h.wait_until { (@h.driver.find_element :css => ".blocking-info").text == ""}

  end

  it "new user can pay on the inside with subscription tab" do
    random_email = @h.emailhelper.random_email()

    @h.driver.get(@h.ctx.createKontrakcjaURL ("/" + @h.lang + "/signup"))

    puts "request an account and make sure you get a flash back"
    (@h.wait_until { @h.driver.find_element :css => ".signup input" }).send_keys random_email
    (@h.wait_until { @h.driver.find_element :css => ".signup a.button" }).click
    (@h.wait_until { @h.driver.find_element :css => ".flash-body" })

    puts "we should get an email to a page where we can accept the tos"
    @h.emailhelper.follow_link_in_latest_mail_for random_email
    puts "accept the tos"
    @h.wait_until { @h.driver.find_element :css => ".checkbox[name=tos]" }.click

    puts "fill in a name"
    (@h.wait_until { @h.driver.find_element :name => "fullname" }).send_keys "Random Person"

    puts "fill in the password details correctly"
    (@h.wait_until { @h.driver.find_element :name => "password" }).send_keys "password-123"
    (@h.wait_until { @h.driver.find_element :name => "password2" }).send_keys "password-123"

    puts "submit the signup form"
    (@h.wait_until { @h.driver.find_element :css => ".account-setup a.button" }).click

    puts "should be logged in and able to upload a document"
    @h.wait_until { @h.driver.find_element :css => "a.js-logout" }
    @h.driver.get(@h.ctx.createKontrakcjaURL "/account")

    (@h.wait_until { @h.driver.find_element :css => ".s-subscription" }).click
    (@h.wait_until { (@h.driver.find_element :css => ".plan-container.team a.button.action-sign-up").displayed? })
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team a.button.action-sign-up" }).click
    
    puts "fill in cc number"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .card_number input" }).send_keys "4111 1111 1111 1111"
    sel =(@h.wait_until { @h.driver.find_element :css => ".plan-container.team .field.expires .year select" })

    sel.find_elements( :css => "option" ).find do |option|
      option.text == "20"
    end.click

    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .field.cvv input" }).send_keys "111"

    puts "click"
    (@h.wait_until { @h.driver.find_element :css => ".plan-container.team .s-subscribe" }).click

    @h.wait_until { @h.driver.find_element :css => ".changebilling-form"}

  end

  #  it "allows a user to pay with a credit card" do

#    @h.loginhelper.login_as(@h.ctx.props.tester_email, @h.ctx.props.tester_password)
#    begin
#      @h.loginhelper.set_name(@h.ctx.props.tester_fstname, @h.ctx.props.tester_sndname)
#
#      (@h.wait_until { @h.driver.find_element :css => ".s-account" }).click
#      (@h.wait_until { @h.driver.find_element :css => ".s-subscription" }).click
#
#      (@h.wait_until { @h.driver.find_element :css => ".field.card_number input" }).send_keys "4111111111111111"
#      sel =(@h.wait_until { @h.driver.find_element :css => ".field.expires .year select" })
#      sel.click
#      sel.find_elements( :tag_name => "option" ).find do |option|
#        option.text == "20"
#      end.click
#
#      (@h.wait_until { @h.driver.find_element :css => ".field.cvv input" }).send_keys "111"
#
#      (@h.wait_until { @h.driver.find_element :css => ".s-subscribe" }).click
#      (@h.wait_until { @h.driver.find_element :css => ".payments"    }).send_keys [:control, :home]
#      
#      @h.wait_until { @h.driver.find_element :css => ".subscription-payments" }
#    end
#  end
end
