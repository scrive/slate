(function(window) {

  var SignupModel = Backbone.Model.extend({
    email: function() {
      return this.get('email');
    },
    setEmail: function(email) {
      this.set('email', email);
    },
    signup: function() {
      var model = this;

      new Submit({
        method: 'POST',
        url: "/signup",
        ajax: true,
        email: model.email(),
        ajaxsuccess: function(rs) {
          resp = JSON.parse(rs);
          if (resp.sent === true) {
            var content = localization.payments.outside.confirmAccountCreatedUserHeader;
            new FlashMessage({content: content, color: 'green'});
          } else if (resp.sent === false) {
            new FlashMessage({content: localization.accountSetupModal.flashMessageUserAlreadyActivated, color: 'red'});
          }
        }
      }).send();
    }
  });

  var SignupView = Backbone.View.extend({
    initialize: function() {
      this.render();
    },
    validationCallback: function(t, e, v) {
      $("<div class='validate-message failed-validation' />").css({'font-size': 8, 'font-weight': 'bold', color: 'red'}).append(v.message()).appendTo(e.parent());
    },
    clearValidationMessages : function() {
      $(".validate-message",this.el).remove();
    },
    render: function () {
        var self = this;
        var model = this.model;

        var content = $("<div class='short-input-container recovery-container'/>");
        var wrapper = $("<div class='short-input-container-body-wrapper'/>");
        var body = $("<div class='short-input-container-body'/>");
        content.append(wrapper.append(body));

        var emailInput = InfoTextInput.init({
          infotext: localization.signupModal.fillinemail,
          value: model.email(),
          onChange: function(v) {self.clearValidationMessages(); model.setEmail(v);},
          cssClass : "big-input",
          inputtype: 'text',
          name: 'email'
        });

              
        var signupButton = Button.init({
            size  : 'small',
            color : 'blue',
            text: localization.signupModal.modalAccountSetupFooter,
            onClick: function() {
              self.clearValidationMessages(); 
              if (emailInput.input().validate(new EmailValidation({callback: self.validationCallback, message: localization.validation.wrongEmail})))
                model.signup();
            }
          });
        
        body.append($("<div class='position first'/>").append($("<h1>").text(localization.signupModal.startNow)));
        body.append($("<div class='position'/>").append(emailInput.input()).append(signupButton.input()));
        $(this.el).append(content);
      }
  });

  window.Signup = function(args) {
    var model = new SignupModel(args);
    var view =  new SignupView({model: model, el: $("<div class='signup short-input-section'/>")});
    this.el = function() {return $(view.el);}
  };

})(window);
