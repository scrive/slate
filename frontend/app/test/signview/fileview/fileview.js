define(["legacy_code", "backend", "util", "image", "React", "signview/fileview/fileview"], function(legacy_code, backend, util, ImageShim, React, FileView) {

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
      it("should test component", function (done) {
        var placement = util.addPlacement(doc);
        var field = placement.field();
        var file = doc.mainfile();

        var fileView = TestUtils.renderIntoDocument(React.createElement(FileView, {
          model: file,
          signview: new SignView(),
          arrow: function () { },
          onReady: function () {
            assert.ok(fileView.readyFirstPage(), "first page should be ready");
            done();
          }
        }));
      });
    });

    after(function () {
      window.Image = oldImage;
      server.restore();
    });
  });
});
