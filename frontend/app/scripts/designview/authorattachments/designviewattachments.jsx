var Backbone = require("backbone");
var DesignViewAttachment = require("./designviewattachment");
var _ = require("underscore");
/* Model representing list of attachments created during design - not send to server yet */

  module.exports = Backbone.Model.extend({
    defaults: {
      attachments: []
    },

    initialize: function (args) {
      var self = this;
      var attachments = new Array();

      _.each(args.document.authorattachments(), function (attachment) {
          var newAttachment = new DesignViewAttachment({
              serverFileId: attachment.fileid(),
              name: attachment.name(),
              required: attachment.isRequired(),
              addToSealedFile: attachment.isAddToSealedFile(),
              documentid: args.document.documentid()
          });
          self.listenTo(newAttachment, "change", function () { self.trigger("change"); });
          attachments.push(newAttachment);
      });

      this.set({
        attachments: attachments,
        document: args.document
      });
    },

    attachments: function () {
      return this.get("attachments");
    },

    addAttachment: function (newAttachment) {
      var self = this;
      this.attachments().push(newAttachment);
      this.listenTo(newAttachment, "change", function () { self.trigger("change"); });
      this.trigger("change");
    },

    removeAttachment: function (attachment) {
      var newattachments = new Array();
      for (var i = 0; i < this.attachments().length; i++) {
        if (attachment !== this.attachments()[i]) {
          newattachments.push(this.attachments()[i]);
        }
      }
      this.set({attachments: newattachments});
      this.stopListening(attachment);
      this.trigger("change");
    },

    isEmpty: function () {
      return this.attachments().length == 0;
    },

    hasErrorMessages: function () {
      return _.any(this.attachments(), function (attachment) {
        return attachment.hasErrorMessage();
      });
    },

    clearErrorMessages: function () {
      return _.each(this.attachments(), function (attachment) {
        return attachment.clearErrorMessage();
      });
    }
  });
