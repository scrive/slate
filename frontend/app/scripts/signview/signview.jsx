var Backbone = require("backbone");
var React = require("react");
var BackboneMixin = require("../common/backbone_mixin");
var DocumentViewSignatories = require("./signatories/docviewsignatories");
var SignatoryAttachmentsView = require("./attachments/signatoryattachmentsview");
var AuthorAttachmentsView = require("./attachments/authorattachmentsview");
var ExtraDetailsView = require("./extradetails/extradetailsview");
var SignSectionView = require("./signsection/signsectionview");
var SignViewModel = require("./signviewmodel");
var FileView = require("./fileview/fileview");
var Header = require("./header");
var Footer = require("./footer");
var PostSignView = require("./postsignview");
var Overlay = require("./overlay");
var ViewSize = require("./viewsize");
var Document = require("../../js/documents.js").Document;
var $ = require("jquery");
var ReloadManager = require("../../js/reloadmanager.js").ReloadManager;
var PadSigningView = require("./padsigningview");
var Arrow = require("./navigation/arrow");
var TaskList = require("./navigation/task_list");

  module.exports = React.createClass({
    mixins: [BackboneMixin.BackboneMixin],

    propTypes: {
      documentId: React.PropTypes.string.isRequired,
      documentData: React.PropTypes.object,
      sigLinkId: React.PropTypes.string.isRequired,
      allowSaveSafetyCopy: React.PropTypes.bool.isRequired,
      loggedInAsAuthor: React.PropTypes.bool.isRequired,
      authorFullname: React.PropTypes.string,
      authorPhone: React.PropTypes.string,
      link: React.PropTypes.object
    },

    getInitialState: function () {
      var model = new SignViewModel({
        document: new Document({id: this.props.documentId,
                                initialdocumentdata: this.props.documentData,
                                siglinkid: this.props.sigLinkId}),
        allowsavesafetycopy: this.props.allowSaveSafetyCopy,
        loggedInAsAuthor: this.props.loggedInAsAuthor
      });

      return {model: model, overlay: false, showArrow: true, pixelWidth: 1040};
    },

    childContextTypes: {
      document: React.PropTypes.instanceOf(Document).isRequired,
      taskList: React.PropTypes.instanceOf(TaskList).isRequired,
      hideArrow: React.PropTypes.func.isRequired,
      showArrow: React.PropTypes.func.isRequired,
      blinkArrow: React.PropTypes.func.isRequired,
      zoomToPoint: React.PropTypes.func.isRequired,
      goToCurrentTask: React.PropTypes.func.isRequired
    },

    // Contexts are an undocumented built in feature of React.
    // https://discuss.reactjs.org/t/documentation-on-context/130
    getChildContext: function () {
      var self = this;

      return {
        document: self.state.model.document(),

        taskList: self.state.model.tasks(),

        hideArrow: function () {
          self.setState({showArrow: false});
        },

        showArrow: function () {
          self.setState({showArrow: true});
        },

        blinkArrow: function () {
          if (self.refs.arrow) {
            self.refs.arrow.blink();
          }
        },

        zoomToPoint: function (zoomPoint, zoom) {
          self.refs.fileView.zoomToPoint(zoomPoint, zoom);
        },

        goToCurrentTask: function () {
          var arrow = self.refs.arrow;

          if (arrow) {
            arrow.goto();
          }
        }
      };
    },

    isReady: function () {
      return this.state.model.isReady();
    },

    componentDidMount: function () {
      var self = this;
      var model = self.state.model;
      $(window).resize(this.handleResize);
      $(window).on("orientationchange", this.handleOrientationChange);
      model.recall();
      ReloadManager.pushBlock(model.blockReload);
    },

    componentDidUpdate: function () {
      var model = this.state.model;
      if (model.isReady() && model.hasSignSection() && !model.hasDonePostRenderTasks()) {
        model.sendTrackingData();
        model.takeFirstScreenshotWithDelay();
      }
    },

    getBackboneModels: function () {
      var model = this.state.model;
      var doc = model.document();
      var attachments = [];

      if (doc.currentSignatory()) {
        attachments = doc.currentSignatory().attachments();
        attachments = attachments.concat(doc.authorattachments());
      }

      return [model, doc].concat(attachments);
    },

    enableOverlay: function () {
      this.setState({overlay: true});
    },

    disableOverlay: function () {
      this.setState({overlay: false});
    },

    handleOrientationChange: function () {
      // force redraw to fix chrome on ios not redrawing everything
      this.forceUpdate();
    },

    handleResize: function () {
      this.forceUpdate();
    },

    render: function () {
      var self = this;
      var model = this.state.model;
      var doc = model.document();

      return (
        <div className="signview">
          {/* if */ doc.showheader() &&
            <Header
              document={doc}
              documentid={this.props.documentId}
              link={this.props.link}
              authorFullname={this.props.authorFullname}
              authorPhone={this.props.authorPhone}
            />
          }
          <div id="default-place-for-arrows" />
          {/* if */ model.hasArrows() && model.tasks().active() &&
            <Arrow ref="arrow" show={this.state.showArrow} task={model.tasks().active()} />
          }
          {/* if */ !model.isReady() &&
            <div className="main">
              <div className="section loading">
                <div className="col-xs-12 center">
                  <div className="waiting4data" />
                </div>
              </div>
            </div>
          }
          {/* else */ model.isReady() &&
            <div className="main">
              <Overlay on={this.state.overlay} />
              {/* if */ this.props.loggedInAsAuthor && model.hasPadSigning() &&
                <PadSigningView sigs={doc.signatoriesThatCanSignNowOnPad()} />
              }
              {/* if */ model.hasPostSignView() &&
                <PostSignView document={doc} />
              }
              <FileView
                ref="fileView"
                pixelWidth={this.state.pixelWidth}
                dimControls={this.state.overlay}
                model={doc.mainfile()}
                signview={model}
              />
              {/* if */ model.hasAuthorAttachmentsSection() &&
                <AuthorAttachmentsView
                  model={doc}
                  canStartFetching={self.refs.fileView != undefined && self.refs.fileView.ready()}
                />
              }
              {/* if */ model.hasSignatoriesAttachmentsSection() &&
                <SignatoryAttachmentsView model={doc} />
              }
              {/* if */ model.hasExtraDetailsSection() &&
                <ExtraDetailsView
                  model={doc.currentSignatory()}
                  signview={model}
                  isVertical={ViewSize.isSmall() || ViewSize.isMedium()}
                />
              }
              {/* if */ model.hasSignatoriesSection() &&
                <DocumentViewSignatories model={doc} />
              }
              {/* if */ model.hasSignSection() &&
                <SignSectionView
                  pixelWidth={this.state.pixelWidth}
                  model={model}
                  enableOverlay={this.enableOverlay}
                  disableOverlay={this.disableOverlay}
                />
              }
              {/* if */ doc.showfooter() &&
                <Footer/>
              }
            </div>
          }
        </div>
      );
    }
  });
