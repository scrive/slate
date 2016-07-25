var React = require("react");
var BackboneMixin = require("../common/backbone_mixin");
var List = require("../lists/list");
var moment = require("moment");
var HtmlTextWithSubstitution = require("../common/htmltextwithsubstitution");
var $ = require("jquery");

var Document = require("../../js/documents.js").Document;

module.exports = React.createClass({
    propTypes: {
      documentid: React.PropTypes.string.isRequired,
      expanded: React.PropTypes.bool
    },
    getDefaultProps: function() {
      return {
        expanded: false
      };
    },
    getInitialState: function() {
      return this.stateFromProps(this.props);
    },
    componentWillReceiveProps: function(props) {
      this.setState(this.stateFromProps(props));
    },
    stateFromProps : function(props) {
      return {expanded: props.expanded};
    },
    setExpanded : function(b) {
      this.setState({expanded : b});
    },
    expanded : function() {
      return this.state.expanded;
    },
    expandText : function() {
      var expandString = localization.history.expand.replace(/[0-9]+/,this.refs.list.list().length - 15);
      return "+ " + expandString;
    },
    ready : function() {
      return this.refs.list != undefined && this.refs.list.ready();
    },
    hideText : function() {
      return "- " + localization.history.hide;
    },
    checkIfHistoryChangedAndCallback : function(changedcallback,errorcallback) {
      this.refs.list != undefined && this.refs.list.checkIfChangedAndCallback(changedcallback,errorcallback);
    },
    render: function() {
      var self = this;
      return (
        <div className="document-history-container">
          <List.List
            url={"/api/frontend/documents/"+ this.props.documentid + "/history" }
            dataFetcher={function(d) {return d.events;}}
            ref='list'
            onReload={function() {self.forceUpdate();}}
            showLimit={this.state.expanded ? undefined : 15}
          >
            <List.Column
              name={localization.archive.documents.columns.status}
              width="46px"
              rendering={function(d) {
                return (
                <div className={"icon status "+d.field("status")}></div>
                );
              }}
            />
            <List.Column
              name={localization.history.time}
              width="150px"
              rendering={function(d) {
                return (
                  <span>
                      {/*if*/ (d.field("time") != undefined && d.field("time") != "" ) &&
                        <span>{moment(d.field("time")).toDate().toTimeAbrevWithMinutes()}</span>
                      }
                  </span>
                );
              }}
            />
            <List.Column
              name={localization.history.party}
              width="200px"
              rendering={function(d) {
                return (
                  <div>{d.field("party")}</div>
                );
              }}
            />
            <List.Column
              name={localization.history.description}
              width="460px"
              rendering={function(d) {
                return (
                <div style={{"marginRight":"30px"}}>
                  <HtmlTextWithSubstitution
                    secureText={d.field("text")} // We need to trust that backend server will not return anything dangerous here
                  />
                </div>
                );
              }}
            />
          </List.List>
          {/* if */ (this.refs.list != undefined && this.refs.list.ready() && this.refs.list.list().length > 15) &&
            (
              <div className="document-history-footer"  onClick={function() {self.setExpanded(!self.expanded());}}>
                <div className="option">
                  <div className="label">
                    {/* if */ (!this.expanded()) &&
                      (<span> { self.expandText() } </span>)
                    }
                    {/* else */ (this.expanded()) &&
                      (<span> { self.hideText() } </span>)
                    }
                  </div>
                </div>
              </div>
            )
          }
        </div>
      );
    }
});
