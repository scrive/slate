/* Signatory view of document
 */


(function(window) {

window.DocumentSignViewHeader = Backbone.View.extend({
 initialize: function(args) {
     this.mainview = args.mainview;
     _.bindAll(this, 'render' ,'refresh');
     this.model.document().bind('reset', this.render);
     this.model.document().bind('change', this.render);
     this.model.bind('change', this.render);
     this.mainview.bind('change:task', this.refresh);
     this.render();

  },
  tagName: "div",
  refresh : function() {
      var el = $(this.el);
      var tbd = $("<span/>");
      $(this.el).append(tbd);
      setTimeout(function() {tbd.remove();},1);
      if (!$.browser.msie) {
        var width = Math.max($('body').width(),$(document).width());
        if (width > 1020)
          el.css("min-width",width + "px");
        // remove poweredbyscrive triangle
        //var pbs = $(".poweredbyscrive",this.el);
        //if (pbs.size() > 0)
        //    pbs.css("left", width - pbs.width() - 1);
        var pti = $(".padTopIcon");
        if (pti.size() > 0)
            pti.css("left", width - pti.width() - 2);
      }
  },
  updateHeaderSenderPosition: function() {
    if ($(window).width() < 1150) {
        this.sender.addClass("shoved");
    } else {
        this.sender.removeClass("shoved");
    }
  },
  render: function() {
    var view = this;
    var model = this.model;
    var document = this.model.document();
    if (!document.ready()) return this;
    var maindiv = $(this.el);
    maindiv.empty();
      maindiv.removeClass();
      maindiv.attr("style","");
    maindiv.addClass("pageheader");

    if(inService) {
        maindiv.addClass('withstandardlogo');
        var content = $("<div class='content' />");
        var logowrapper = $("<div class='logowrapper' />");
        logowrapper.append("<a href='/'><div class='logo'></div></a>");
        if (document.barsbackgroundcolor() != undefined)
        {
            maindiv.css('background-image', 'none');
            maindiv.css('background-color', document.barsbackgroundcolor());
        }
        if (document.barsbackgroundtextcolor() != undefined)
            maindiv.css("color", document.barsbackgroundtextcolor());

    } 
      // alright, here's the deal: how do we determine if they should see our logo.
      // lukas and I were getting this bug where documents on his computer were not showing branding
      // and on mine, the same documents were. We spent a good half hour trying to figure out why. He
      // rebooted, we sent each other documents, etc.
      // It turns out that if you sent to an email address with a User, you didn't see branding on 
      // sign view. We can't tell the difference between a user that just saved and one that had an
      // account from long ago.
      // I'm making a ruling here: if companies are going to pay for branding, they don't want to
      // send out a contract with Scrive logo ever. Even if they have a Scrive account.
      // So now, we only show the Scrive logo just once after they save. If they reload, we show
      // the old logo. We should probably change that but it's late and Lukas will file another
      // bug if I make that change.
      // I will address this later when I fix up the post sign view.
      // -- Eric, 4 Aug 2012
      else if(document.currentSignatory() != undefined && document.currentSignatory().hasSigned() && model.justSaved()) {
        maindiv.addClass('withstandardlogo');
        var content = $("<div class='content' />");
        var logowrapper = $("<div class='logowrapper' />");
        logowrapper.append("<a href='/'><div class='logo'></div></a>");

    } else {
        // Remove powered by scrive triangle
        //maindiv.append($("<div class='poweredbyscrive'/>"));
        maindiv.addClass(document.logo() == undefined ? 'withstandardlogo' : 'withcustomlogo');
        if (document.barsbackgroundcolor() != undefined)
        {
            maindiv.css('background-image', 'none');
            maindiv.css('background-color', document.barsbackgroundcolor());
        }
        if (document.barsbackgroundtextcolor() != undefined)
            maindiv.css("color", document.barsbackgroundtextcolor());

        var content = $("<div class='content' />");
        var logowrapper = $("<div class='logowrapper' />");
        if (document.logo() == undefined)
            logowrapper.append("<a href='/'><div class='logo'></div></a>");
        else
            {
                var img = $("<img class='logo'></img>");
                img.load(function(){  view.refresh();  });
                img.attr('src',document.logo());
                logowrapper.append(img);
            }
    }
    
    this.sender = $("<div class='sender' />");
    var inner = $('<div class="inner" />');
      this.sender.append(inner);
    if(document.currentSignatory() != undefined && (document.currentSignatory().saved() || model.justSaved())) {
      var name = $("<div class='name' />").text("Scrive help desk");
      var phone = $("<div class='phone' />").text("+46 8 519 779 00");
      inner.append(name).append(phone);
    } else {
      var author = $("<div class='author' />").text((document.authoruser().fullname().trim()||document.authoruser().phone().trim())?localization.docsignview.contact:"");
      var name = $("<div class='name' />").text(document.authoruser().fullname());
      var phone = $("<div class='phone' />").text(document.authoruser().phone());
      inner.append(author).append(name).append(phone);
    }
    

    this.updateHeaderSenderPosition();
    $(window).resize(function() { view.updateHeaderSenderPosition();});

    content.append(logowrapper).append(this.sender).append("<div class='clearboth'/>");
    maindiv.append(content);
    return this;
  }
});

window.DocumentSignViewFooter = Backbone.View.extend({
  initialize: function(args) {
    this.mainview = args.mainview;
    _.bindAll(this, 'render' , 'refresh');
    this.model.document().bind('reset', this.render);
    this.model.document().bind('change', this.render);
    this.mainview.bind('change:task', this.refresh);
    this.render();
  },
  refresh : function() {
      var el = $(this.el);
      var tbd = $("<span/>");
      $(this.el).append(tbd);
      setTimeout(function() {tbd.remove();},1);
      if (!$.browser.msie) {
        var width = Math.max($('body').width(),$(document).width());
        if (width > 1020)
          el.css("min-width",width + "px");
      }   
  },
  tagName: "div",
  render: function() {
    var model = this.model;
    var document = this.model.document();
    if (!document.ready()) return this;
    var maindiv = $(this.el);
    maindiv.empty();
    maindiv.addClass("pagefooter");
    if (document.barsbackgroundcolor() != undefined)
    {
        maindiv.css('background-image', 'none');
        maindiv.css('background-color', document.barsbackgroundcolor());
    }

    if (document.barsbackgroundtextcolor() != undefined)
        maindiv.css("color", document.barsbackgroundtextcolor());

    var content = $("<div class='content' />");
    var dogtooth = $("<div class='dogtooth' />");
    var powerdiv = $("<div class='poweredbyscrive'/>").append($("<a href='/'>").text(localization.poweredByScrive).css("color", document.barsbackgroundtextcolor()));
    var sender = $("<div class='sender' />");

    if(document.currentSignatory() != undefined && (document.currentSignatory().saved() || model.justSaved())) {
      var name = $("<div class='name' />").text("Scrive help desk");
      var phone = $("<div class='phone' />").text("+46 8 519 779 00");
      sender.append(name).append(phone);
    } else {

      var name = $("<div class='name' />").text(document.authoruser().fullname());
      var position = $("<div class='position' />").text(document.authoruser().position());
      var company = $("<div class='company' />").text(document.authoruser().company());
      var phone = $("<div class='phone' />").text(document.authoruser().phone());
      var email = $("<div class='email' />").text(document.authoruser().email());
      sender.append(name).append(position).append(company).append(phone).append(email);
    }

    content.append(sender);
      if(!inService)
          content.append(powerdiv);
      content.append("<div class='clearboth'/>");
    maindiv.append(dogtooth.append(content));
    return this;
  }
});

})(window);
