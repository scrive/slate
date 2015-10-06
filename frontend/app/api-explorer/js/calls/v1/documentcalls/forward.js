
(function (window) {

new APICallV1({
  category: "signing",
  name: "Forward",
  description: "Forward the confirmation email for any signed document to the given email address.",
  sampleUrl: "/api/v1/forward/$documentid$",
  method: "POST",
  getCallUrl: function () {
          return "/api/v1/forward/" + this.get("documentid");
        },
  needsAuthorization: true,
  equivalentCalls: {
    "v2": "Forward"
  },
  params: [
          new APICallParam({
            type: "text",
            argName: "documentid",
            name: "Document id",
            sendAsParam: false,
            useLocalStorage: true,
            description: "Id of document.",
            defaultValue: ""
          }),
          new APICallParam({
            type: "text",
            argName: "email",
            name: "Email",
            description: "Email address to forward the document.",
            defaultValue: ""
          }),
          new APICallParam({
            type: "bool",
            argName: "nocontent",
            name: "No content",
            description: "If set, email will contain attachments, but the email content will be blank.",
            defaultValue: ""
          })
        ]
});

})(window);
