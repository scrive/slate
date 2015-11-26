define(["Backbone", "React", "common/backbone_mixin", "designview/typesetters/texttypesetterview",
        "designview/editdocument/draggablemixin", "designview/fileview/hastypesettermixin",
        "common/infotextinput", "legacy_code"],
  function (Backbone, React, BackboneMixin, TextTypeSetterView, DraggableMixin, HasTypeSetterMixin, InfoTextInput) {

  return React.createClass({
    propTypes: {
      model: React.PropTypes.instanceOf(FieldPlacement).isRequired,
      pageWidth: React.PropTypes.number.isRequired,
      pageHeight: React.PropTypes.number.isRequired
    },

    mixins: [BackboneMixin.BackboneMixin, DraggableMixin, HasTypeSetterMixin],

    getBackboneModels: function () {
      return [this.getPlacement()];
    },

    getPlacement: function () {
      return this.props.model;
    },

    getTypeSetterClass: function () {
      return TextTypeSetterView;
    },

    getInitialState: function () {
      return {editing: false};
    },

    componentDidMount: function () {
      this.initDraggable();
    },

    initDraggable: function () {
      var self = this;
      var placement = this.getPlacement();
      var document = placement.field().signatory().document();

      self.initializeDraggable({
        el: $(self.getDOMNode()),
        verticalOffset: -1,
        xAxisOffset: FieldPlacementGlobal.textPlacementXOffset,
        yAxisOffset:  FieldPlacementGlobal.textPlacementYOffset,
        dropXOffset: FieldPlacementGlobal.textPlacementXOffset,
        dropYOffset:  FieldPlacementGlobal.textPlacementYOffset,
        onStart: self.closeTypeSetter,
        onDropOnPage: function (page, x, y, pageW, pageH) {
          var oldPage = document.file().page(placement.page());
          var newPage = document.file().page(page);
          placement.set({
            page: page,
            xrel: x / pageW,
            yrel: y / pageH
          });
          oldPage.removePlacement(placement);
          newPage.addPlacement(placement);
        },
        onDropOutside: function () {
          placement.remove();
          placement.removeField();
        }
      });
    },

    openTypeSetterAndCloseOther: function () {
      if (!this.hasTypeSetter()) {
        this.props.closeAllTypeSetters();
        this.openTypeSetter();
      } else if (!this.editorIsAvailable()) {
        this.closeTypeSetter();
      }
    },

    editorIsAvailable: function () {
      var field = this.getPlacement().field();
      return !field.isCsvField() && !field.isAuthorUnchangeableField();
    },

    render: function () {
      var self = this;
      var placement = this.getPlacement();
      var field = placement.field();
      var signatory = field.signatory();
      var fontSize = Math.floor(placement.fsrel() * this.props.pageWidth);
      var hasEditor =  self.hasTypeSetter() && self.editorIsAvailable();
      return (
        <div
          className={"placedfield " + ("js-" + field.type()) + (field.isValid(true) ? "" : " invalid") }
          style={{
            left: Math.floor(placement.xrel() * this.props.pageWidth + 1.5) - FieldPlacementGlobal.textPlacementXOffset,
            top: Math.floor(placement.yrel() * this.props.pageHeight + 1.5) - FieldPlacementGlobal.textPlacementYOffset,
            fontSize: fontSize + "px"
          }}
          onClick={self.openTypeSetterAndCloseOther}
        >
          <div className="placedfield-placement-wrapper">
            { /* if */ hasEditor &&
              <InfoTextInput
                className={
                  "text-field-placement-setter-field-editor " +
                  FieldPlacementGlobal.signatoryCSSClass(signatory)
                }
                infotext={field.nicename()}
                value={field.value()}
                autoGrowth={true}
                focus={true}
                style={{
                  fontSize: fontSize + "px",
                   lineHeight: fontSize + FieldPlacementGlobal.textPlacementExtraLineHeight + "px",
                   height: fontSize + FieldPlacementGlobal.textPlacementExtraLineHeight + "px",
                   verticalAlign: "top",
                   padding: FieldPlacementGlobal.textPlacementSpacingString
                }}
                inputStyle={{
                  fontSize: fontSize + "px",
                  lineHeight: fontSize + FieldPlacementGlobal.textPlacementExtraLineHeight + "px",
                  height: fontSize + FieldPlacementGlobal.textPlacementExtraLineHeight + "px",
                  verticalAlign: "top"
                }}
                suppressSpace={field.isFstName()}
                onChange={function (val) {
                  field.setValue(val.trim());
                }}
                onEnter={self.closeTypeSetter}
                onAutoGrowth={self.forceUpdateTypeSetterIfMounted}
              />
            }

            { /* else */ !hasEditor &&
              <div
                className={"placedfieldvalue value " + FieldPlacementGlobal.signatoryCSSClass(signatory)}
                style={{
                  padding: FieldPlacementGlobal.textPlacementSpacingString,
                  fontSize: fontSize + "px",
                  lineHeight: fontSize + FieldPlacementGlobal.textPlacementExtraLineHeight + "px"
                }}
              >
                {field.nicetext()}
              </div>
            }
          </div>
        </div>
      );
    }
  });
});
