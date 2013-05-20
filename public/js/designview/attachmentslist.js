/* This is component for designing signatory attachments
 */

(function(window){

var DesignAttachmentsListView = Backbone.View.extend({
    initialize: function (args) {
        _.bindAll(this, 'render');
        this.model.bind('change:attachments', this.render);
        this.model.bind('change:signatories', this.render);

        this.model = args.model;
        this.render();
    },
    destroy : function() {
        this.model.unbind('change:attachments', this.render);
        this.model.unbind('change:signatories', this.render);
        this.off();
        this.remove();
    },
    aarow : function(a) {
      var self = this;
      var tr = $("<tr/>");
      var name = $("<td/>").text(a.name());
      var remove = $("<td/>").append($("<div class='design-view-action-participant-details-information-closer active'/>").click(function() {self.model.removeattachment(a);}));
      return tr.append(name).append(remove);
    },
    sarow : function(sig,a) {
      var text = sig.nameOrEmail();
      if (sig.isCsv())
        text = localization.csv.title;
      if (text == "")
        text = sig.nameInDocument();

      var tr = $("<tr/>");
      var name = $("<td/>").text(a.name() + " (Requested from " + text + ")");
      var remove = $("<td/>").append($("<div class='design-view-action-participant-details-information-closer active'/>").click(function() {sig.removeAttachment(a);}));
      return tr.append(name).append(remove);
    },
    render: function () {
        console.log("Rendering attachments list");
        var view = this;
        var document = this.model;
        this.container = $(this.el);
        this.container.empty();
        var authorattachments = document.authorattachments();
        var sattachments = _.flatten(_.map(document.signatories(),function(s) {return s.attachments()}));
        if (authorattachments.length != 0 || sattachments.length != 0 )
        {
            var table= $("<table/>");
            var th1 = $("<th class='name'>");
            var th2 = $("<th class='remove'>");
            var thead = $("<thead/>").append(th1).append(th2);
            var tbody = $("<tbody/>");
            _.each(authorattachments, function(a) { tbody.append(view.aarow(a));});
            _.each(document.signatories(),function(s) {_.each(s.attachments(),function(a) { tbody.append(view.sarow(s,a));}); });
            this.container.append(table.append(thead).append(tbody));        }
        return this;
    }
});


window.DesignAttachmentsList = function(args) {
    var view = new DesignAttachmentsListView({model : args.document, el : $("<div class=designview-attachemnts-list/>")});
    this.el = function() {return $(view.el);};
    this.destroy = function() { view.destroy();}

};


})(window);
