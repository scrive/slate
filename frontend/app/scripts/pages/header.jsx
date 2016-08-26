var React = require("react");
var Backbone = require("backbone");
var NewButton = require("../common/button");
var Track = require("../common/track");




  var LoggedInHeader = React.createClass({
    propTypes: {
      archive : React.PropTypes.bool,
      account : React.PropTypes.bool
    },
    handleNewDocument : function() {
      Track.track_timeout("Click start new process",{}, function(e) {
        window.location.href = "/newdocument";
      });
      return false;
    },
    handleNewFromTemplate : function() {
      Track.track_timeout("Click create from template",{}, function(e) {
              window.location.href = "/fromtemplate";
        });
      return false;
    },
    handleLogout : function() {
      Track.track_timeout( "Click Logout",{}, function(e) {
              window.location.href = "/logout";
      });
      return false;
    },
    render: function() {
     return (
      <header className="site">
        <nav>
          <ul className="ct">
            <li id="branding">
              <a id="logo" className="page" href="/newdocument">
                {
                  <img
                    src={
                      window.cdnbaseurl + "/service_logo/" + window.brandingdomainid + "/" +
                      (window.brandinguserid || "_") + "/" + window.brandinghash}
                    style={{"margin":"0px"}}
                  />
                }
              </a>
            </li>
            <ul className="right-container">
              <li className="float-right" >
                <a className="page js-logout" onClick={this.handleLogout} href="#">{localization.header.logout}</a>
              </li>
              <li className="float-right" >
                <a className={"page" + (this.props.account ? " active" : "")} id='page-account'  href="/account">{localization.header.account}</a>
              </li>
              <li className="page-first float-right" >
                <a className={"s-archive page " + (this.props.archive ? "active" : "")} id='page-archive' href="/d">{localization.header.archive}</a>
              </li>
              <li className="session-create float-right fromtemplate">
                <NewButton
                  cssClass="fromtemplate"
                  type="main"
                  onClick={this.handleNewFromTemplate}
                  text={localization.header.template}
                />
              </li>
              <li className="session-create float-right">
                <NewButton
                  cssClass="js-create-document"
                  type="main"
                  onClick={this.handleNewDocument}
                  text={localization.header.send}
                />
              </li>
            </ul>
          </ul>
        </nav>
      </header>
     );
    }
  });

  var NotLoggedInHeader = React.createClass({
    propTypes: {
      httplink :  React.PropTypes.string,
      langprefix : React.PropTypes.string
    },
    // We don't have static pages for some languages. In that case we should redirect people to version in english.
    langprefixForStaticPages : function() {
      if (this.props.langprefix == "/en/" || this.props.langprefix == "/sv/" )
        return this.props.langprefix;
      return "/en/";
    },
    render: function() {
     return (
       <header className="site thin">
        <nav>
          <ul className="ct thin">
            <li id="branding">
              <a id="logo" className="page" href={this.props.httplink + this.props.langprefix}>
                <img src={window.cdnbaseurl + "/img/scrive-logo-dark.png"}  style={{"margin":"0"}} />
              </a>
            </li>
            <li className="session-login float-right">
              <a className="button scrive-main-button" id="page-signin" href={this.props.langprefix + "enter"}>{localization.header.login}</a>
              <a className="button action" id="page-signup" href={this.props.langprefix + "enter#sign-up"}>{localization.header.startFreeTrial}</a>
            </li>
            <li className="float-right"  >
                <a className="page"   href={this.props.httplink + this.langprefixForStaticPages() + "contact"}>{localization.header.contact}</a>
            </li>
            <li className="float-right" >
                <a className="page"  href={this.props.httplink + this.langprefixForStaticPages() + "about"}>{localization.header.about}</a>
            </li>
            <li className="float-right" >
                <a className="page"  href={this.props.httplink + this.langprefixForStaticPages() + "cases"}>{localization.header.cases}</a>
            </li>
            <li className="float-right" >
                <a className="page price-plan-page-link"  href={this.props.langprefix + "pricing"}>{localization.header.pricing}</a>
            </li>
            <li className="float-right" >
                <a className="page"  href={this.props.httplink + this.langprefixForStaticPages() + "legal"}>{localization.header.legal}</a>
            </li>
            <li className="float-right" >
                <a className="page"  href={this.props.httplink + this.langprefixForStaticPages() +"features"}>{localization.header.features}</a>
            </li>
            <li className="float-right" >
                <a className="page"  href={this.props.httplink + this.langprefixForStaticPages() +"partners"}>{localization.header.partners}</a>
            </li>
          </ul>
        </nav>
      </header>
     );
    }
  });




  module.exports = React.createClass({
    propTypes: {
      httplink :  React.PropTypes.string,
      langprefix : React.PropTypes.string,
      archive : React.PropTypes.bool,
      account : React.PropTypes.bool
    },
    render: function() {

      if (this.props.logged) {
        return (<LoggedInHeader
                  archive={this.props.archive}
                  account={this.props.account}
                />);
      } else {
        return (<NotLoggedInHeader
                  httplink={this.props.httplink}
                  langprefix={this.props.langprefix}
                />);
      }
    }
  });
