// ignore model in coverage for now.
/* istanbul ignore next */
define(["legacy_code", "Underscore", "Backbone", "React", "eleg/bankidsigning"],
  function (legacy_code, _, Backbone, React, BankIDSigning) {
  return Backbone.Model.extend({
    defaults: {
      doc: undefined,
      siglinkid: 0,
      type: "swedish",
      step: "identify",
      transaction: undefined,
      statusText: undefined,
      thisDevice: true
    },
    initialize: function (args) {
      _.bindAll(this, "identifySwedish", "identifyNorwegian", "cancel", "back");
    },
    doc: function () {
      return this.get("doc");
    },
    siglinkid: function () {
      return this.get("siglinkid");
    },
    transaction: function () {
      return this.get("transaction");
    },
    isSwedish: function () {
      return this.doc().currentSignatory().seBankIDAuthenticationToView();
    },
    isNorwegian: function () {
      return false;
    },
    isIdentify: function () {
      return this.get("step") === "identify";
    },
    isProcessing: function () {
      return this.get("step") === "processing";
    },
    isProblem: function () {
      return this.get("step") === "problem";
    },
    statusText: function () {
      return this.get("statusText");
    },
    thisDevice: function () {
      return this.get("thisDevice");
    },
    setIdentify: function () {
      this.set({step: "identify"});
    },
    setProcessing: function () {
      this.set({step: "processing"});
    },
    setProblem: function () {
      this.set({step: "problem"});
    },
    setStatusText: function (v) {
      this.set({statusText: v});
    },
    setTransaction: function (t) {
      this.set({transaction: t});
    },
    setThisDevice: function (v) {
      this.set({thisDevice: v});
    },
    identifySwedish: function () {
      var self = this;
      var bankID = new BankIDSigning({
        type: "auth",
        signatory: this.doc().currentSignatory(),
        onStatusChange: function () {
          self.setStatusText(bankID.statusMessage());
          self.trigger("change");
        },
        onSuccess: function () {
          window.location.reload();
        },
        onFail: function () {
          self.setStatusText(bankID.statusMessage());
          self.setProblem();
          return true;
        },
        onCriticalError: function (xhr) {
          self.setStatusText(bankID.statusMessage());
          self.setProblem();
          new ReloadDueToErrorModal(xhr);
        },
        thisDevice: self.thisDevice()
      });
      self.setTransaction(bankID);
      bankID.initiateTransaction();
      self.setStatusText(bankID.statusMessage());
      self.setProcessing();
    },
    identifyNorwegian: function (type, phoneNumber) {
      this.setProcessing();
    },

    cancel: function () {
      if (this.transaction()) {
        this.transaction().cancel();
      }
      this.setIdentify();
    },

    back: function () {
      this.setIdentify();
    }

  });
});
