var backend = require("../../backend");
var util = require("../../util");
var ImageShim = require("../../image");
var React = require("react");
var CheckboxPlacementPlacedView = require("../../../scripts/signview/fileview/checkboxplacementplacedview");

  var TestUtils = React.addons.TestUtils;

  /*
  var SignView = Backbone.Model.extend({});

  describe("signview/fileview/checkboxplacementplacedview", function () {
    var server, doc;

    before(function (done) {
      server = backend.createServer();
      util.createDocument(function (d) {
        doc = d;
        done();
      });
    });

    describe("CheckboxPlacementPlacedView", function () {
      it("should test component", function () {
        var placement = util.addPlacement(doc, undefined, 0, {
          type: "checkbox"
        });

        var field = placement.field();

        var container = TestUtils.renderIntoDocument(util.taskContextContainer(CheckboxPlacementPlacedView, {
          model: placement,
          width: 800,
          height: 600,
          signview: new SignView(),
          arrow: function () { },
        }));

        var checkboxPlacement = container.refs.comp;

        assert.equal(field.value(), "", "checkbox should be unchecked");

        checkboxPlacement.toggleCheck();

        assert.equal(field.value(), "CHECKED", "checkbox should be checked");

        checkboxPlacement.toggleCheck();

        assert.equal(field.value(), "", "checkbox should be unchecked");
      });
    });

    after(function () {
      server.restore();
    });
  });
  */
