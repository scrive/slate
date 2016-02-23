var backend = require("../../backend");
var util = require("../../util");
var ImageShim = require("../../image");
var React = require("react");
var FileView = require("../../../scripts/signview/fileview/fileview");

  var TestUtils = React.addons.TestUtils;

  var SignView = Backbone.Model.extend({});

  describe("signview/fileview/fileview", function () {
    var server, doc, oldImage;

    before(function (done) {
      server = backend.createServer();
      oldImage = window.Image;
      window.Image = ImageShim;
      util.createDocument(function (d) {
        doc = d;
        done();
      });
    });

    describe("FileView", function () {
      it("should test component", function () {
        var placement = util.addPlacement(doc);
        var field = placement.field();
        var file = doc.mainfile();

        var fileView = TestUtils.renderIntoDocument(React.createElement(FileView, {
          model: file,
          signview: new SignView(),
          pixelWidth: 950,
          arrow: function () { }
        }));
      });
    });

    after(function () {
      window.Image = oldImage;
      server.restore();
    });
  });
