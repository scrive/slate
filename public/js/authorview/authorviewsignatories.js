(function(window){

var AuthorViewSignatoriesModel = Backbone.Model.extend({
  defaults : function() { return {
     signatoriesViews : [],
     currentSignview  : undefined
    };
  },
  initialize: function (args) {
    var self = this;
    var signatoriesViews = this.get("signatoriesViews");
    _.each(this.signatories(), function(sig) {
      signatoriesViews.push(new AuthorViewSignatory({signatory: sig, authorviewsignatories : self }));
    });
    this.set({currentSignview : this.get('signatoriesViews')[0]}, {silent : true});
  },
  signatories: function() {
    return this.document().signatories();
  },
  currentIndex : function() {
    for(var i = 0;i < this.get("signatoriesViews").length ; i++ )
      if (this.get("signatoriesViews")[i] == this.get("currentSignview")) return i;
  },
  setCurrentIndex : function(i) {
      if (this.get("signatoriesViews")[i] != undefined)
        this.setCurrentSignview(this.get("signatoriesViews")[i]);
  },
  authorview :function() {
     return this.get("authorview");
  },
  document :function() {
     return this.authorview().document();
  },
  hasList : function() {
     return this.signatoriesViews().length > 2;
  },
  isSingleSignatory : function() {
     return this.signatoriesViews().length ==1;
  },
  signatoriesViews : function() {
     return this.get("signatoriesViews");
  },
  signatoryView : function(i)
  {
    if (i == undefined)  return this.get("currentSignview");
    return this.signatoriesViews()[i];
  },
  setCurrentSignview : function(sv) {
    this.set({currentSignview : sv});
  },
  destroy : function() {
    _.each(this.signatoriesViews(), function(s) {s.destroy();});
    this.clear();
  }
});

var AuthorViewSignatoriesView = Backbone.View.extend({
  initialize: function (args) {
        _.bindAll(this, 'render');
        this.render();
        this.listenTo(this.model,'change', this.render);
  },
  destroy : function() {
    this.stopListening();
    this.model.off();
    this.model.destroy();
    $(this.el).remove();
  },
  list : function() {
      var self = this;
      var model = this.model;
      this.listDiv = $("<div class='list spacing'>");
      _.each(this.model.signatoriesViews(), function(sigview, index) {
          var sigdiv     = $("<div class='sig' />");
          if(index === 0)
              sigdiv.addClass('first');
          var name       = $("<div class='name' />").text(sigview.nameOrEmailOrMobile());
          var line       = $("<div class='line' />");
          var middle1    = $("<div class='middle'/>");
          var middle2    = $("<div class='middle' style='min-width: 150px;'/>");
          var middle3    = $("<div class='middle details' style='white-space: nowrap;'/>");
          var statusicon = $("<div class='icon status'/>").addClass(sigview.status());
          var status     = $("<div class='statustext' />").addClass(sigview.status()).html(sigview.signatoryViewerySummary());
          var details    = $('<a class="clickable" href="#" />').text(localization.docsignview.showDetails);
          middle1.append(statusicon);
          middle2.append(status);
          middle3.append(details);
          line.append(middle1).append(middle2).append(middle3);
          details.click(function() {
              model.setCurrentSignview(sigview);
              return false;
          });
          sigdiv.append(name).append(line);
          self.listDiv.append(sigdiv);
      });
    return this.listDiv;
  },
  render: function() {
      var view = this;
      var box = $(this.el);
      if (this.listDiv!= undefined) this.listDiv.remove();
      box.children().detach();
      box.addClass('section').addClass('signatories').addClass('spacing');

      var header = $("<h2 style='width: 100px;' />");
      box.append(header.text(localization.authorview.signatoriesTitle));

      var table = $("<table class='signatories-box' style='float: right;' />");
      var tbody = $("<tbody/>");
      var tr = $("<tr style='height: 220px;'/>");
      var td1 = $("<td class='signatory-box' />");
      var tdseparator = $("<td class='signatory-box-separator'/>");
      var td2 = $("<td class='signatory-box' />");
      var box1 = $('<div class="column spacing" />');
      var box2 = $('<div class="column spacing" />');
      table.append(tbody.append(tr.append(td1.append(box1)).append(tdseparator).append(td2.append(box2))));
      box.append(table);

      if (this.model.isSingleSignatory()) {
         td1.remove();
         box2.append(this.model.signatoryView().el());
      }
      else if (this.model.hasList()) {
         box1.append(this.list());
         box2.append(this.model.signatoryView().el());

      } else {
         box1.append(this.model.signatoryView(0).el());
         box2.append(this.model.signatoryView(1).el());
      }

      return this;
  }

});

window.AuthorViewSignatories = function(args) {
          var model = new AuthorViewSignatoriesModel(args);
          var view =  new AuthorViewSignatoriesView({model : model, el : $("<div/>")});
          this.el = function() {return $(view.el);};
          this.currentIndex = function() { return model.currentIndex() };
          this.setCurrentIndex = function(i) { model.setCurrentIndex(i);};
          this.destroy = function() {return view.destroy();};

};


})(window);
