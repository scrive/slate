define(["legacy_code_for_signview", "backend", "util", "image", "React", "signview/fileview/signatureplacementplacedview"], function(legacy_code, backend, util, ImageShim, React, SignaturePlacementPlacedView) {

  var TestUtils = React.addons.TestUtils;

  /*
  var SignView = Backbone.Model.extend({
    hasExtraInputs: function () {
      return false;
    }
  });

  describe("signview/fileview/signatureplacementplacedview", function () {
    var server, doc;

    before(function (done) {
      server = backend.createServer();
      util.createDocument(function (d) {
        doc = d;
        done();
      });
    });

    describe("SignaturePlacementPlacedView", function () {
      it("should test component", function () {
        var placement = util.addPlacement(doc, undefined, 0, {
          type: "signature"
        });
        var field = placement.field();

        var container = TestUtils.renderIntoDocument(util.taskContextContainer(SignaturePlacementPlacedView, {
          model: placement,
          width: 800,
          height: 600,
          signview: new SignView(),
          arrow: function () {
            return {
              notCompletedTasks: function () { return []; },
              disable: function () { }
            }
          },
        }));

        var signaturePlacement = container.refs.comp;

        signaturePlacement.activateSignatureModal();

        var modal = $(".drawing-modal");

        assert.equal(modal.length, 1, "there should be one drawing modal");
      });
    });

    after(function () {
      server.restore();
    });
  });
  */
});
