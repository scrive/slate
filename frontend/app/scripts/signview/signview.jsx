define([
  "legacy_code",
  "Backbone",
  "React",
  "common/backbone_mixin",
  "common/onelementheightchange",
  "signview/signatories/docviewsignatories",
  "signview/attachments/signatoryattachmentsview",
  "signview/instructionsview/instructionsview",
  "signview/attachments/authorattachmentsview",
  "signview/extradetails/extradetailsview",
  "signview/signsection/signsectionview",
  "signview/signviewmodel",
  "signview/fileview/fileview",
  "signview/header",
  "signview/footer",
  "signview/postsignview",
  "signview/tasks/taskarrows",
  "signview/overlay"
], function (
  legacy_code,
  Backbone,
  React,
  BackboneMixin,
  onElementHeightChange,
  DocumentViewSignatories,
  SignatoryAttachmentsView,
  InstructionsView,
  AuthorAttachmentsView,
  ExtraDetailsView,
  SignSectionView,
  SignViewModel,
  FileView,
  Header,
  Footer,
  PostSignView,
  TaskArrows,
  Overlay
) {
  return React.createClass({
    mixins: [BackboneMixin.BackboneMixin],

    propTypes: {
      documentId: React.PropTypes.string.isRequired,
      sigLinkId: React.PropTypes.string.isRequired,
      allowSaveSafetyCopy: React.PropTypes.bool.isRequired,
      useStandardHeaders: React.PropTypes.bool.isRequired,
      authorFullname: React.PropTypes.string,
      authorPhone: React.PropTypes.string,
      link: React.PropTypes.object
    },

    getInitialState: function () {
      var viewer = new DocumentViewer({
        signatoryid: this.props.sigLinkId
      });

      var model = new SignViewModel({
        document: new Document({id: this.props.documentId, viewer: viewer}),
        allowsavesafetycopy: this.props.allowSaveSafetyCopy
      });

      return {model: model, overlay: false, pixelWidth: 950};
    },

    childContextTypes: {
      addTask: React.PropTypes.func.isRequired,
      removeTask: React.PropTypes.func.isRequired
    },

    // Contexts are an undocumented built in feature of React.
    // https://discuss.reactjs.org/t/documentation-on-context/130
    getChildContext: function () {
      var model = this.state.model;

      return {
        addTask: function (task) {
          model.addTask(task);
        },

        removeTask: function (task) {
          model.removeTask(task);
        }
      };
    },

    isReady: function () {
      return this.state.model.isReady();
    },

    componentDidMount: function () {
      var self = this;
      var model = self.state.model;
      model.recall();
      ReloadManager.pushBlock(model.blockReload);
      onElementHeightChange(self.getDOMNode(), function () {
        model.updateArrowPosition();
      });

      $(window).on("beforeunload", function () {
        if (!ReloadManager.isBlocking()) {
          $(window).scrollTop(0);
        }
      });
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

    render: function () {
      var self = this;
      var model = this.state.model;
      var doc = model.document();
      var isSmallScreen = BrowserInfo.isSmallScreen();

      return (
        <div className="signview">
          {/* if */ !this.props.useStandardHeaders && doc.showheader() && !isSmallScreen &&
            <Header
              document={doc}
              documentid={this.props.documentId}
              signatorylinkid={this.props.sigLinkId}
              link={this.props.link}
              authorFullname={this.props.authorFullname}
              authorPhone={this.props.authorPhone}
            />
          }
          {/* if */ model.hasArrows() &&
            <TaskArrows model={model} />
          }
          {/* if */ !model.isReady() &&
            <div className="main">
              <div className="section loading">
                <div className="col-xs-12 center">
                  <img src="/img/wait30trans.gif" />
                </div>
              </div>
            </div>
          }
          {/* else */ model.isReady() &&
            <div className="main">
              <Overlay on={this.state.overlay} />
              <InstructionsView
                model={doc}
                arrow={function () { return model.arrow(); }}
              />
              {/* if */ model.hasPostSignView() &&
                <PostSignView document={doc} />
              }
              <FileView
                ref="fileView"
                pixelWidth={this.state.pixelWidth}
                model={doc.mainfile()}
                signview={model}
                arrow={function () { return model.arrow(); }}
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
                <ExtraDetailsView model={doc.currentSignatory()} signview={model} />
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
              {/* if */ doc.showfooter() && !isSmallScreen &&
                <Footer/>
              }
            </div>
          }
        </div>
      );
    }
  });
});
