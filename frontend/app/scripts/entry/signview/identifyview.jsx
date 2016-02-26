var React = require("react");
var IdentifyView = require("../../signview/identify/identifyview");
var Document = require("../../../js/documents").Document;
var DocumentViewer = require("../../../js/documentviewer").DocumentViewer;
var $ = require("jquery");

$(function () {
  var doc = new Document({
    id: fromTemplate.documentId,
    viewer: new DocumentViewer({
      signatoryid : fromTemplate.sigLinkId
    })
  });

  // no design for loading.
  doc.recall(function () {
    React.render(React.createElement(IdentifyView, {
      doc: doc,
      siglinkid: fromTemplate.sigLinkId
    }), $(".global-table-cell")[0]);
  });
});
