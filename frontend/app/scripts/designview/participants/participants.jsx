var React = require("react");
var BackboneMixin = require("../../common/backbone_mixin");
var Participant = require("./participant");
var AddParticipants = require("./addparticipants");
var $ = require("jquery");
var _ = require("underscore");

module.exports = React.createClass({
  mixins: [BackboneMixin.BackboneMixin],
  getBackboneModels: function () {
    return [this.props.document];
  },
  getInitialState: function () {
    return {
      participantDetail: undefined,
      needsToScroll: false,
      closingSig: undefined
    };
  },
  componentWillUnmount: function () {
    // this.setState({participantDetail: undefined});;
  },
  maxHeight: function () {
    var heightOfNavigationTabs = 350;  // Height of navigation tabs on page.
    return Math.max(250, $(window).height() - heightOfNavigationTabs);
  },
  // Height of participants needs to be computed for scrollbar.
  // Height of whole secton and each field is hardcoded
  participantsHeight: function () {
    var heightOfUnexpandedSignatory = 60;  // Height each signatory description when signatory is not expanded
    var heightOfSignatoryPadding = 14; // height of paddings between each signatory
    var heightOfField = 50; // Height each field row
    var heightOfParticipantSettings = 172; // Height of 6 selects at bottom of signatory
    var heightOfParticipantBorder = 4;
    var height = 0;

    height += this.props.document.signatories().length * heightOfUnexpandedSignatory;

    if (this.state.participantDetail != undefined) {
      height += heightOfParticipantBorder + heightOfParticipantSettings;
      height += heightOfSignatoryPadding;
      var fields = 0;
      var nameIncluded = false;
      _.each(this.state.participantDetail.fields(), function (f) {
        if (f.isFstName() || f.isSndName()) {
          if (!nameIncluded) {
            nameIncluded = true;
            fields++;
          }
        } else if (f.isText() || f.isBlank()) {
          fields++;
        }
      });

      height += Math.ceil((fields + 1) / 3) * heightOfField;
    }
    return height;
  },
  currentHeight: function () {
    return Math.min(this.participantsHeight(), this.maxHeight()) + "px";
  },
  hasScrollbar: function () {
    return this.maxHeight() < this.participantsHeight();
  },
  // Whenever we update - we check if we need to scroll to the bottom/signatory
  // This is used when adding new signatories/opening existing
  componentDidUpdate: function () {
    if (this.state.needsToScroll) {
      this.scrollToOpenParticipant();
      this.setState({needsToScroll: false});
    }
  },
  scrollToOpenParticipant: function () {
    var self = this;
    var openParticipant;
    var openParticipantNumber;
    var closingParticipant;
    var closingParticipantNumber;
    _.map(this.props.document.signatories(), function (s, i) {
      if (self.state.participantDetail === s) {
        openParticipant = self.refs["participant-" + i];
        openParticipantNumber = i;
      } else if (self.state.closingSig === s) {
        closingParticipant = self.refs["participant-" + i];
        closingParticipantNumber = i;
      }
    });

    if (openParticipant === undefined || !this.hasScrollbar() ||
        !this.isMounted() || this.refs["participants-box"] === undefined) {
      return;
    }
    var openParticipantNode = openParticipant.getDOMNode();

    var participantsBox = $(this.refs["participants-box"].getDOMNode());
    var lowestVisiblePositionInBox = participantsBox.height() + participantsBox.scrollTop();
    var highestVisiblePositionInBox = participantsBox.scrollTop();
    var topOfOpenParticipantBox = openParticipantNode.offsetTop;
    if (closingParticipantNumber !== undefined && closingParticipantNumber < openParticipantNumber) {
      // signatory that is higher than the one currently being opened is being closed
      // we have to calculate where should we scroll after the animation is done
      var heightOfUnexpandedSignatory = 60;  // Height each signatory description when signatory is not expanded
      topOfOpenParticipantBox = closingParticipant.getDOMNode().offsetTop +
                               (openParticipantNumber - closingParticipantNumber) * heightOfUnexpandedSignatory;
    }

    // This should be $(openParticipantNode).outerHeight(), but before the animation ends it"s lower than is should be
    var bottomOfOpenParticipantBox = topOfOpenParticipantBox + 345;

    if (bottomOfOpenParticipantBox > lowestVisiblePositionInBox ||
        topOfOpenParticipantBox < highestVisiblePositionInBox) {
      participantsBox.animate({scrollTop: topOfOpenParticipantBox}, "500");
    }
    this.setState({closingSig: undefined});
  },
  setParticipantDetail: function (newParticipantDetail) {
    this.setState({participantDetail: newParticipantDetail});
  },
  render: function () {
    var self = this;
    if (!this.props.document.ready()) {
      return <div/>;
    } else {
      return (
        <div className="design-view-action-participant-container">
          <div
            ref="participants-box"
            className="design-view-action-participant-container-participants-box"
            style={{
              height: self.currentHeight(),
              overflow: self.hasScrollbar() ? "auto" : "hidden" // Can"t use auto due to transitions
            }}
          >
            {
              _.map(this.props.document.signatories(), function (s, i) {
                return (
                  <Participant
                    key={s.cid}
                    ref={"participant-" + i}
                    model={s}
                    number={i}
                    document={self.props.document}
                    currentParticipantDetail={self.state.participantDetail}
                    setParticipantDetail={self.setParticipantDetail}
                    onExpand={function (oldSig) {self.setState({needsToScroll: true, closingSig: oldSig})}}
                  />
                );
              })
            }
          </div>
          <div className="design-view-action-participant-new-box">
            <AddParticipants
              ref="add-participants"
              document={self.props.document}
              currentParticipantDetail={self.state.participantDetail}
              setParticipantDetail={self.setParticipantDetail}
              onAddSingle={function () {self.setState({needsToScroll: true});}}
              />
          </div>
        </div>
      );
    }
  }
});
