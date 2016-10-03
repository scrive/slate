var React = require("react");
var Backbone = require("backbone");
var BackboneMixin = require("../../common/backbone_mixin");
var Checkbox = require("../../common/checkbox");
var Theme = require("../../themes/theme");
var SignviewPreview = require("../../themes/previews/signing");
var $ = require("jquery");
var Confirmation = require("../../../js/confirmations.js").Confirmation;

var SignviewSettingsModel = Backbone.Model.extend({
  initialize: function (args) {
    var self = this;
    var theme = new Theme({url: "/account/company/companybranding/signviewtheme"});
    theme.bind("change", function () {
      self.trigger("change");
    });
    this.set({
      theme: theme,
      showHeader: args.document.showheader() == undefined ? true : args.document.showheader(),
      showRejectOption: args.document.showrejectoption() == undefined ? true : args.document.showrejectoption(),
      allowRejectReason: args.document.allowrejectreason() == undefined ? true : args.document.allowrejectreason(),
      showPDFDownload: args.document.showpdfdownload() == undefined ? true : args.document.showpdfdownload(),
      showFooter: args.document.showfooter() == undefined ? true : args.document.showfooter()
    });
    theme.fetch({cache: false});
  },
  document: function () {
    return this.get("document");
  },
  theme: function () {
    return this.get("theme");
  },
  showHeader: function () {
    return this.get("showHeader");
  },
  setShowHeader: function (b) {
    this.set({"showHeader": b, "showPDFDownload": b});
  },
  setShowHeaderAndPdfDownload: function (b) {
    this.set({"showHeader": b, "showPDFDownload": b});
  },
  showRejectOption: function () {
    return this.get("showRejectOption");
  },
  setShowRejectOption: function (b) {
    this.set("showRejectOption", b);
  },
  allowRejectReason: function () {
    return this.get("allowRejectReason");
  },
  setAllowRejectReason: function (b) {
    this.set("allowRejectReason", b);
  },
  setShowRejectOptionAndAllowRejectReason: function (b) {
    this.set({"allowRejectReason": b, "showRejectOption": b});
  },
  showPDFDownload: function () {
    return this.get("showPDFDownload");
  },
  setShowPdfDownload: function (b) {
    this.set("showPDFDownload", b);
  },
  showFooter: function () {
    return this.get("showFooter");
  },
  setShowFooter: function (b) {
    this.set("showFooter", b);
  },
  ready: function () {
    return this.document().ready() && this.theme().ready();
  }
});

var SignviewSettingsView = React.createClass({
    mixins: [BackboneMixin.BackboneMixin],
    getBackboneModels: function () {
      return [this.props.model];
    },
    render: function () {
      var self = this;
      var model = self.props.model;
      if (!model.ready()) {
        return (<div/>);
      } else {
        return (
          <div className="signviewsettings">
            <div className="options">
              <Checkbox
                checked={model.showHeader()}
                label={localization.designview.signviewsettings.showheader}
                onChange={function (c) { model.setShowHeaderAndPdfDownload(c); }}
              />
              <div className="indented">
                <Checkbox
                  checked={model.showPDFDownload()}
                  label={localization.designview.signviewsettings.showpdfdownload}
                  onChange={function (c) {
                    if (c) {
                      model.setShowHeaderAndPdfDownload(c);
                    } else {
                      model.setShowPdfDownload(c);
                    }
                  }}
                />
              </div>
              <Checkbox
                checked={model.showRejectOption()}
                label={localization.designview.signviewsettings.showrejectoption}
                onChange={function (c) {
                  if (!c) {
                    model.setShowRejectOptionAndAllowRejectReason(c);
                  } else {
                    model.setShowRejectOptionAndAllowRejectReason(c);
                  }
                }}
              />
              <div className="indented">
                <Checkbox
                  checked={model.allowRejectReason()}
                  label={localization.designview.signviewsettings.allowrejectreason}
                  onChange={function (c) {
                    if (c) {
                      model.setShowRejectOptionAndAllowRejectReason(c);
                    } else {
                      model.setAllowRejectReason(c);
                    }
                  }}
                />
              </div>
              <Checkbox
                checked={model.showFooter()}
                label={localization.designview.signviewsettings.showfooter}
                onChange={function (c) { model.setShowFooter(c); }}
              />
            </div>
            <div className="container">
              <SignviewPreview
                showHeader={model.showHeader()}
                showRejectOption={model.showRejectOption()}
                allowRejectReason={model.allowRejectReason()}
                showPDFDownload={model.showPDFDownload()}
                showFooter={model.showFooter()}
                model={model.theme()}
              />
            </div>
          </div>
        );
      }
    }
});

module.exports = function (args) {
  var document = args.document;
  var model = new SignviewSettingsModel({document: document});
  var settingsView = $("<div/>");
  React.render(React.createElement(SignviewSettingsView, {
    model: model
  }), settingsView[0]);
  var popup = new Confirmation({
    content: settingsView,
    title: localization.designview.signviewsettings.title,
    icon: undefined,
    acceptText: localization.save,
    width: 940,
    onAccept: function () {
      document.setShowheader(model.showHeader());
      document.setShowrejectoption(model.showRejectOption());
      document.setAllowrejectreason(model.allowRejectReason());
      document.setShowpdfdownload(model.showPDFDownload());
      document.setShowfooter(model.showFooter());
      document.save();
      if (args.onClose !== undefined) {
        args.onClose();
      }
      return true;
    },
    onReject: function () {
      if (args.onClose !== undefined) {
        args.onClose();
      }
   }
 });
};
