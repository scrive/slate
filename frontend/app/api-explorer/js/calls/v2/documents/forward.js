(function (window) {

new APICallV2({
  category: "signing",
  name: "Forward",
  description: "Forward a document to an email address.",
  sampleUrl: "/api/v2/documents/$document_id$/forward",
  method: "POST",
  getCallUrl: function () {
          return "/api/v2/documents/" + this.get("document_id") + "/forward";
        },
  needsAuthorization: true,
  equivalentCalls: {
    'v1': 'Forward'
  },
  params: [
          window.APIV2CallParamDocumentID,
          new APICallParam({
            type: "text",
            argName: "email",
            name: "Email",
            description: "The email address to forward the document to.",
            defaultValue: ""
          }),
          new APICallParam({
            type: "bool",
            argName: "no_content",
            optional: true,
            name: "No content",
            description: "When set to true only the signed document will be forwarded, with no other email content."
          }),
          window.APIV2CallParamObjectVersion
        ]
});

})(window);
