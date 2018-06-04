
(function (window) {

window.AbstractAPICall = Backbone.Model.extend({
  defaults: {
    method: "GET",
    needsAuthorization: true,
    category: "other",
    isInternal: false,
    tryToUseDocumentIDWithCopy: false,
    expectBinaryResponse: false,
    expectImageResponse: false,
    expectPDFResponse: false
  },
  name: function () {
          return this.get("name");
        },
  description: function () {
          return this.get("description");
        },
  sampleUrl: function () {
          return this.get("sampleUrl");
        },
  method: function () {
          return this.get("method");
        },
  apiVersion: function () {
          return this.get("apiVersion");
        },
  isInternal: function () {
          return this.get("isInternal");
        },
  needsAuthorization: function () {
          return this.get("needsAuthorization");
        },
  hasCategory: function (c) {
          if (typeof this.get("category") == "string" || this.get("category") instanceof String) {
            return c == this.get("category");
          } else if (this.get("category") instanceof Array) {
            return _.contains(this.get("category"), c);
          }
        },
  hasFileParams: function () {
          return _.any(this.params(), function (p) {
            return p.type() == "file";
          });
        },
  equivalentInVersion: function (v) {
          var eqs = this.get("equivalentCalls");
          if (eqs != undefined) {
            return eqs[v];
          }
          return undefined;
        },
  tryToUseDocumentIDWithCopy: function () {
          return this.get("tryToUseDocumentIDWithCopy");
        },
  expectBinaryResponse: function () {
          return this.get("expectBinaryResponse");
        },
  expectImageResponse: function () {
          return this.get("expectImageResponse");
        },
  expectPDFResponse: function () {
          return this.get("expectPDFResponse");
        },
  urlHash: function () {
          return this.apiVersion() + "-" + this.name().replace(/\s+/g, "-").toLowerCase();
        },
  params: function () {
          return this.get("params");
        },
  createCall: function (props) {
          props = props || {};
          props.callPrototype = this;
          return new (this.get("constructor_"))(props);
        }
});

window.ApiCallInstance = AbstractAPICall.extend({
  defaults: {
    send: false,
    details: undefined,
    resultContent: undefined,
    resultContentLength: undefined,
    resultContentType: undefined,
    responseStatusCode: undefined
  },
  initialize: function (args) {
    var self = this;
    _.each(args.params, function (p) {
      self.setParamValue(p, p.defaultValue());
    });
  },
  unsend: function () {
          this.set({
            send: false,
            details: undefined,
            resultContent: undefined,
            resultContentLength: undefined,
            resultContentType: undefined,
            responseStatusCode: undefined
          });
          this.trigger("send");
        },
  isSent: function () {
          return this;
        },
  callPrototype: function () {
          return this.get("callPrototype");
        },
  getParamValue: function (p) {
          return this.get(p.argName());
        },
  includeParam: function (p) {
          return !p.optional() || (this.getParamValue(p) !== "" || this.getParamSendEmpty(p));
        },
  setParamValue: function (p, v) {
          this.set(p.argName(), v);
          if (p.useLocalStorage()) {
            LocalStorage.set("param", p.argName(), v);
          }
        },
  getParamSendEmpty: function (p) {
          return this.get(p.argName() + "-sendEmpty");
        },
  setParamSendEmpty: function (p, v) {
          this.set(p.argName() + "-sendEmpty", v);
        },
  getCallArgs: function () {
          var self = this;
          var args = {};
          _.each(this.params(), function (p) {
            if (p.sendAsParam() && self.includeParam(p)) {
              args[p.argName()] = self.getParamValue(p);
            }
          });
          return args;
        },
  attachFileParamsToForm: function (form, p) {
    var multifile = this.getParamValue(p);
    this.slaves = _.filter(multifile.slaves, function (s) { return s != undefined; });
    this.slavesParents = _.map(this.slaves, function (s) { return $(s).parent(); });
    var upto = this.getParamSendEmpty(p) ? this.slaves.length : this.slaves.length - 1;
    for (var i = 0; i < upto; i++) {
      form.append($(this.slaves[i]).attr("name", p.argName(i)));
    }
  },
  detachFileParamsFromForm: function (form) {
    for (var i = 0; i < this.slaves.length && i < this.slavesParents.length; i++) {
      this.slavesParents[i].append(this.slaves[i]);
    }
  },
  getCallArgsWithFilesForm: function () {
          var self = this;
          var form = $("<form method='post' style='display:none;' enctype='multipart/form-data'/>");
          $("body").append(form);
          _.each(this.params(), function (p) {
            if (p.sendAsParam()) {
              if (p.type() == "file") {
                self.attachFileParamsToForm(form, p);
              } else if (self.includeParam(p)) {
                form.append($("<input type='text'/>").attr("name", p.argName()).val(self.getParamValue(p)));
              }
            }
          });
          return form;
        },
  authorization: function () {
    return this.get("oauth").authorizationForRequests();
  },
  responseStatusCode: function () { return this.get("responseStatusCode"); },
  details: function () { return this.get("details"); },
  resultContent: function () { return this.get("resultContent"); },
  resultContentLength: function () { return this.get("resultContentLength"); },
  resultContentType: function () { return this.get("resultContentType"); },
  getDetails: function (jqXHR) {
          return {
            "Status Code":
              "<span class='code " + ((jqXHR.status >= 400 || jqXHR.status == 0) ? "error" : "") + "'>" +
                jqXHR.status +
              "</span>" +
              " " + jqXHR.statusText,
            "Request URL": Scrive.serverUrl() + this.getCallUrl(),
            "Request Method": this.method(),
            "Authorisation needed": this.needsAuthorization() ? "Yes" : "No",
            "Date": jqXHR.getResponseHeader("Date")
          };
        },
  send: function (args) {
          var self = this;
          args = args || {};
          args.type = this.method();

          var form;
          if (!self.hasFileParams()) {
            args.data = this.getCallArgs();
          } else {
            form = this.getCallArgsWithFilesForm();
            args.processData = false;
            args.contentType = false;
            args.data = new FormData(form[0]);
          }
          args.headers = {"Client-Name": "api-explorer",
                          "Client-Time": new Date().toISOString()
                        };
          if (this.needsAuthorization()) {
            args.headers.authorization = this.authorization();
          }
          args.cache = false;
          if (this.expectBinaryResponse()) {
            if (this.expectImageResponse() || this.expectPDFResponse()) {
                  args.dataType = "binary";
                  args.processData = false;
                  args.responseType = "arraybuffer";
              }
          }
          args.success = function (data, textStatus, jqXHR) {
            self.set("details", self.getDetails(jqXHR));
            self.set("resultContent", data);
            self.set("resultContentLength", jqXHR.getResponseHeader("Content-Length"));
            self.set("resultContentType", jqXHR.getResponseHeader("content-type"));
            self.set("responseStatusCode", jqXHR.status);
            if (form != undefined) {
              self.detachFileParamsFromForm(form);
              form.remove();
            }
            self.trigger("send");
            setTimeout(function () { $(".response-result, .request-details").addClass("success"); }, 10);
            setTimeout(function () { $(".response-result, .request-details").removeClass("success"); }, 210);
          };
          args.error = function (jqXHR, textStatus, errorThrown) {
            self.set("details", self.getDetails(jqXHR));
            self.set("resultContent", jqXHR.responseText);
            self.set("resultContentLength", jqXHR.getResponseHeader("Content-Length"));
            self.set("resultContentType", jqXHR.getResponseHeader("content-type"));
            self.set("responseStatusCode", jqXHR.status);
            if (form != undefined) {
              self.detachFileParamsFromForm(form);
              form.remove();
            }
            self.trigger("send");
            setTimeout(function () { $(".response-result, .request-details").addClass("error"); }, 10);
            setTimeout(function () { $(".response-result, .request-details").removeClass("error"); }, 210);
          };
          $.ajax(Scrive.serverUrl() + this.getCallUrl(), args);
        }
});

window.APICalls = new (Backbone.Model.extend({
  defaults: {
          calls: []
        },
  initialize: function (args) {
        },
  calls: function () {
    return this.get("calls");
  },
  authorization: function () {
          this.get("oauth");
        },
  apiV1Calls: function (includeInternal) {
          return _.filter(this.calls(), function (c) {
            if (includeInternal) {
                return c.apiVersion() == "v1";
            } else {
                return c.apiVersion() == "v1" && !c.isInternal();
            }
          });
        },
  apiV2Calls: function (includeInternal) {
          return _.filter(this.calls(), function (c) {
            if (includeInternal) {
                return c.apiVersion() == "v2";
            } else {
                return c.apiVersion() == "v2" && !c.isInternal();
            }
          });
        },
  registerNewCall: function (props, constructor) {
          props.constructor_ = constructor;
          this.calls().push(new AbstractAPICall(props));
        }
}))();

var APICall = function (props) {
  var staticPropNames = [
    "name",
    "apiVersion",
    "description",
    "sampleUrl",
    "method",
    "isInternal",
    "needsAuthorization",
    "params",
    "category",
    "equivalentCalls",
    "tryToUseDocumentIDWithCopy",
    "expectBinaryResponse",
    "expectImageResponse",
    "expectPDFResponse"
  ];
  var staticProps = {};
  var dynamicProps = {};
  _.each(_.keys(props), function (k) {
    if (_.contains(staticPropNames, k)) {
      staticProps[k] = props[k];
    } else {
      dynamicProps[k] = props[k];
    }
  });
  var constructor = function (instanceProps) {
    return new (ApiCallInstance.extend(dynamicProps))($.extend(instanceProps, staticProps));
  };
  APICalls.registerNewCall(staticProps, constructor);
};

window.APICallV1 = function (props) {
  props.apiVersion = "v1";
  return APICall(props);
};

window.APICallV2 = function (props) {
  props.apiVersion = "v2";
  return APICall(props);
};

})(window);
