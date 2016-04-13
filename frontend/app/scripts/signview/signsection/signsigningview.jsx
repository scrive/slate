var _ = require("underscore");
var Backbone = require("backbone");
var React = require("react");
var Button = require("../../common/button");
var HtmlTextWithSubstitution = require("../../common/htmltextwithsubstitution");
var ViewSize = require("../viewsize");
var $ = require("jquery");
var classNames = require("classnames");

  module.exports = React.createClass({
    propTypes: {
      model: React.PropTypes.instanceOf(Backbone.Model).isRequired,
      title: React.PropTypes.string.isRequired,
      name: React.PropTypes.string.isRequired,
      canSign: React.PropTypes.bool.isRequired,
      onBack: React.PropTypes.func.isRequired,
      onSign: React.PropTypes.func.isRequired
    },

    render: function () {
      var hasSignaturesPlaced = this.props.model.document().currentSignatory().hasPlacedSignatures();

      var divClass = classNames({
        "col-xs-6": !ViewSize.isSmall(),
        "col-xs-12": ViewSize.isSmall(),
        "center-block": true
      });

      return (
        <div className={divClass}>
          <h1>{hasSignaturesPlaced ? localization.process.signModalTitle : localization.process.signbuttontext}</h1>
          <p>
            <HtmlTextWithSubstitution
              secureText={hasSignaturesPlaced ? localization.signviewConfirmationSignaturesPlaced :
                                                localization.signviewConfirmation}
              subs={{".put-document-title-here": this.props.title, ".put-signatory-name-here": this.props.name}}
            />
          </p>
          <Button
            type="action"
            ref="signButton"
            className="button-block"
            onClick={this.props.onSign}
            text={hasSignaturesPlaced ? localization.process.signbuttontextfromsignaturedrawing :
                                        localization.process.signbuttontext}
          />
          <Button
            className="transparent-button button-block"
            onClick={this.props.onBack}
            text={localization.toStart.backFromSigningPage}
          />
        </div>
      );
    }
  });
