/** @jsx React.DOM */

define(['React', 'common/backbone_mixin', 'login/loginmodel','login/brandedloginview', 'login/brandedforgotpasswordview','login/brandedsignupview', 'legacy_code'], function(React, BackboneMixin, LoginModel, BrandedLoginView, BrandedForgotPasswordView, BrandedSignupView) {

return React.createClass({
    propTypes: {
        view: React.PropTypes.string,
        defaultView: React.PropTypes.string,
        email : React.PropTypes.string,
        password : React.PropTypes.string,
        referer : React.PropTypes.string,
        autofocus: React.PropTypes.bool,
        pad : React.PropTypes.bool,
        nolink : React.PropTypes.string,
        langprefix : React.PropTypes.string
    },
    getInitialState: function() {
      return this.stateFromProps(this.props);
    },
    componentWillReceiveProps: function(props) {
      this.setState(this.stateFromProps(props));
    },
    stateFromProps : function(props) {
      var model = new LoginModel({
        view: props.view,
        defaultView: props.defaultView,
        email : props.email,
        password : props.password,
        referer : props.referer,
        pad : props.pad,
        autofocus: props.autofocus,
        nolinks : props.nolinks,
        langprefix : props.langprefix
      });
      return {model: model};
    },
    mixins: [BackboneMixin.BackboneMixin],
    getBackboneModels : function() {
      return [this.state.model];
    },
    render: function() {
      var view = function () {
        if (this.state.model.loginView()) {
          return <BrandedLoginView model={this.state.model}/>;
        }

        if (this.state.model.reminderView()) {
          return <BrandedForgotPasswordView model={this.state.model}/>;
        }

        if (this.state.model.signupView()) {
          return <BrandedSignupView model={this.state.model}/>;
        }

        console.warn("no or incorrect view selected in branded login");
      }.call(this);

      return <div>{view}</div>;
    }
  });
});
