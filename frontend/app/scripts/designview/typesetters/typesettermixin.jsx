/** @jsx React.DOM */

define(["jquery", "Underscore", "Backbone", "React",
        "common/backbone_mixin", "common/selfunmountmixin",
        "common/editabletext", "legacy_code"],
  function ($, _, Backbone, React, BackboneMixin, SelfUnmountMixin, EditableText) {

  var Mixin = {
    mixins: [SelfUnmountMixin, BackboneMixin.BackboneMixin],

    propTypes: {
      model: React.PropTypes.instanceOf(Backbone.Model).isRequired,
      element: React.PropTypes.instanceOf(Element).isRequired,
      hideFunc: React.PropTypes.func.isRequired
    },

    getBackboneModels: function () {
      // All changes to placement propagate up to document. This is why we only need to listen on document changes
      return [this.props.model.field().signatory().document()];
    },

    componentDidUpdate: function () {
    },

    componentWillMount: function () {
      $(window).bind("scroll", this.place);
      $(window).bind("resize", this.place);
    },

    componentWillUnmount: function () {
      $(window).unbind("scroll", this.place);
      $(window).unbind("resize", this.place);
    },

    place: function () {
      this.forceUpdate();
    },

    update: function () {
      if (this.isMounted()) {
        this.forceUpdate();
      }
    },

    done: function () {
      var field = this.props.model.field();
      field.makeReady();
      this.props.hideFunc();
    },

    rename: function (name) {
      var field = this.props.model.field();
      var sig = field.signatory();
      var doc = sig.document();
      var global = field.type() !== "custom";

      var sigs = global ? doc.signatories() : [sig];
      var allnames = [];
      _.each(sigs, function (s) {
        _.each(s.fields(), function (f) {
          if (f !== field) {
            allnames.push(f.name());
          }
        });
      });

      if (name === "") {
        return true;
      }

      if (allnames.indexOf(name) < 0) {
        field.setName(name);
        return true;
      }

      new FlashMessage({type: "error", content: localization.designview.fieldWithSameNameExists});
    },

    render: function () {
      var field = this.props.model.field();

      var renderTitle = this.renderTitle;
      var renderBody = this.renderBody;

      if (typeof renderBody !== "function") {
        throw new Error("TypeSetterMixin requires a renderBody method");
      }

      var $el = $(this.props.element);
      var offset = $el.offset();
      var containerStyle = {
        position: "absolute",
        top: offset.top + this.verticalOffset,
        left: offset.left + $el.width() + this.horizontalOffset
      };

      return (
        <div className="fieldTypeSetter-container" style={containerStyle}>
          <div className="fieldTypeSetter-arrow" />
          <div className="fieldTypeSetter-body">
            <div className="title">
              {renderTitle ? renderTitle() : <EditableText onSave={this.rename} text={field.name()} />}
            </div>
            {renderBody()}
          </div>
        </div>
      );
    }
  };

  return Mixin;
});
