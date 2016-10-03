var _ = require("underscore");
var Backbone = require("backbone");
var React = require("react");
var BackboneMixin = require("../../common/backbone_mixin");
var TaskMixin = require("../navigation/task_mixin");
var Button = require("../../common/button");
var Checkbox = require("../../common/checkbox");
var AuthorAttachmentView = require("./authorattachmentview");
var AuthorAttachment = require("../../../js/authorattachment.js").AuthorAttachment;
var Task = require("../navigation/task");
var $ = require("jquery");
var classNames = require("classnames");
var AuthorAttachmentFileViewer = require("./authorattachmentfileviewer");
var Document = require("../../../js/documents.js").Document;

  module.exports = React.createClass({
    mixins: [BackboneMixin.BackboneMixin, TaskMixin],

    getBackboneModels: function () {
      return [this.props.model];
    },

    propTypes: {
      model: React.PropTypes.instanceOf(AuthorAttachment).isRequired,
      canStartFetching: React.PropTypes.bool.isRequired
    },

    getInitialState: function () {
      return {showPages: false};
    },

    createTasks: function () {
      var self = this;

      if (self.props.model.isRequired() && self.props.canSign) {
        return [new Task({
          type: "author-attachment",
          isComplete: function () {
            return self.props.model.isAccepted();
          },
          onArrowClick: function () {
            self.props.model.setAccepted(true);
          },
          tipSide: "left",
          el: $(self.getDOMNode()),
          pointSelector: ".checkbox",
          margin: 5
        })];
      } else {
        return [];
      }
    },

    componentDidMount: function () {
      this.tryToStartFetchingAttachmntFilePages();
    },

    componentWillUpdate: function () {
      this.tryToStartFetchingAttachmntFilePages();
    },

    tryToStartFetchingAttachmntFilePages: function () {
      if (this.props.model.pages() == undefined && this.props.canStartFetching && !this.fetchingStarted) {
        this.fetchingStarted = true;
        var currentSignatory = this.props.model.document().currentSignatory();
        this.props.model.fetch({
          data: {signatory_id: currentSignatory && currentSignatory.signatoryid()},
          processData: true,
          cache: false
        });
      }
    },

    mandatoryCheckboxLabel: function () {
      var textSpan = $("<span/>").html(localization.docsignview.authorAttachmentsUnderstoodContent);
      $(".put-attachment-name-here", textSpan).text(this.props.model.name());
      return textSpan.text();
    },
    contextTypes: {
      document: React.PropTypes.instanceOf(Document)
    },
    childContextTypes: {
      document: React.PropTypes.instanceOf(Document)
    },
    getChildContext: function () {
      return {
        document: this.context.document
      };
    },
    render: function () {
      var self = this;
      var model = this.props.model;
      var canSign = this.props.canSign;
      var showPages = this.state.showPages;
      var isPagesLoaded = model.pages() !== undefined;

      var buttonClass = classNames({
        "for-signing": canSign
      });

      var fullClass = classNames({
        "col-sm-5": true,
        "full-height": model.isRequired() && canSign
      });

      return (
        <span>
          <div className="section author-attachment">
            <div className="col-sm-6 left">
              <h1>
                <span className="paperclip"/>
                {model.name()}
              </h1>
              {/* if */ model.isRequired() && canSign && !showPages &&
                <Checkbox
                  ref="checkbox"
                  className="large-checkbox branded-checkbox"
                  checked={model.isAccepted()}
                  label={this.mandatoryCheckboxLabel()}
                  onChange={function (v) { model.setAccepted(v); }}
                />
              }
            </div>
            <div className="col-sm-6 right">
              <div className="button-group small-buttons">
                <Button
                  className={buttonClass}
                  text={showPages ? localization.signviewHide : localization.reviewPDF}
                  onClick={function () {
                    self.setState({showPages: !showPages});
                  }}
                />
              </div>
            </div>
          </div>

          {/* if */ showPages &&
            <AuthorAttachmentFileViewer
              attachment={model}
              ready={isPagesLoaded}
            />
          }

          {/* if */ showPages &&
            <div className="section author-attachment">
              <div className="positioned">
                <div className={fullClass}>
                  <div className="vertical">
                    <div className="middle">
                      {/* if */ model.isRequired() && canSign &&
                        <Checkbox
                          ref="checkbox"
                          className="large-checkbox branded-checkbox"
                          checked={model.isAccepted()}
                          label={this.mandatoryCheckboxLabel()}
                          onChange={function (v) { model.setAccepted(v); }}
                        />
                      }
                    </div>
                  </div>
                </div>
                <div className="col-sm-7 right hide-button">
                  <div className="button-group small-buttons">
                    <Button
                      className={buttonClass}
                      text={localization.signviewHide}
                      onClick={function () {
                        self.setState({showPages: !showPages});
                      }}
                    />
                    {/* if */ model.document().showpdfdownload() &&
                      <Button
                        className="download-button"
                        text={localization.download}
                        href={model.downloadLink(true)}
                      />
                    }
                  </div>
                </div>
                <div className="clearfix" />
              </div>
            </div>
          }
        </span>
      );
    }
  });
