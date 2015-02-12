/** @jsx React.DOM */

define(['React','common/backbone_mixin','common/button','common/infotextinput', 'login/loginmodel' ,'legacy_code'], function(React, BackboneMixin, Button, InfoTextInput, LoginModel) {

return React.createClass({
    mixins: [BackboneMixin.BackboneMixin],
    getBackboneModels : function() {
      return [this.props.model];
    },
    propTypes: {
      model: React.PropTypes.object
    },
    sendPasswordReminderCallback : function(resp) {
      if (resp.send == true) {
        mixpanel.track('Password reminder sent');
        new FlashMessage({ content: localization.loginModal.passwordReminderSend, type : "success"});
      } else {
        var text = "";
        if (resp.badformat)
          text = localization.loginModal.invalidEmail;
        else if (resp.nouser)
          text = localization.loginModal.noUser;
        else if (resp.toomuch)
          text = localization.loginModal.tooMuch;
        mixpanel.track('Error',{Message: 'password reminder failed: ' + text});
        new FlashMessage({ content: text, type : "error"});
      }
    },
    trySendPasswordReminder : function() {
      var self = this;
      this.props.model.sendPasswordReminder(function(r) {self.sendPasswordReminderCallback(r);});
    },
    render: function() {
      var self = this;
      var model = this.props.model;
      return (
        <div>
          <div>
            <div className='position first' style={{marginBottom:"6px"}}>
              <InfoTextInput
                infotext={localization.loginModal.email}
                value={model.email()}
                onChange={function(v) {model.setEmail(v);}}
                inputtype="text"
                name="email"
                onEnter={this.trySendPasswordReminder}
                autocomplete={true}
                style={{"width" : "245px", "padding" : "7px 14px","fontSize" : "16px"}}
              />
            </div>
            <div className="position" style={{textAlign:"center", marginTop:"20px"}}>
              <Button
                cssClass="recovery-password-submit"
                type="main"
                text={localization.loginModal.sendNewPassword}
                style={{"width":"235px;"}}
                onClick={this.trySendPasswordReminder}
              />
            </div>
            <div className='position' style={{textAlign:"center",marginTop:"20px"}}>
              <div className='label-with-link'>
                <a onClick={function(){ model.goToLoginView();}}>
                  {localization.loginModal.login}
                </a>
              </div>
            </div>
          </div>
        </div>
      );
    }
  });

});
