/* Arrows
 * There are 4 types of arrows: point-left, point-right, scroll-up, scroll-down
*/

(function(window){

var ArrowModel = Backbone.Model.extend({
  defaults : {
      type : undefined,
      text  : undefined,
      labelCss: undefined,
      point : undefined,
      blinks : 0 // Persistent blinking. If > 0 then arrow is in middle of blinking.
  },
  type : function(){
       return this.get("type");
  },
  blinks : function() {
      return this.get("blinks");
  },
  setBlinks : function(i) {
      return this.set({"blinks" : i});
  },
  text : function(){
       return this.get("text");
  },
  labelCss: function(){
       return this.get('labelCss');
  },
  point: function() {
       return this.get("point");
  },
  isPointLeft: function() {
      return this.type() ==  "point-left";
  },
  isPointRight: function() {
      return this.type() ==  "point-right";
  },
  isScrollUp: function() {
      return this.type() ==  "scroll-up";
  },
  isScrollDown: function() {
      return this.type() ==  "scroll-down";
  },
  scrollDone : function() {
      if (this.get("scrollDone") != undefined)
        this.get("scrollDone")();
  }
});


/* General arrow view - passes control to dedicated view based on something*/
var ArrowView =  function (args) {
        if (args.model.isPointLeft())
            return new PointLeftArrowView(args);
        else if (args.model.isPointRight())
            return new PointRightArrowView(args);
        else if (args.model.isScrollUp())
            return new ScrollUpArrowView(args);
        else if (args.model.isScrollDown())
            return new ScrollDownArrowView(args);
    };


/* Views for different arrows
 */
var PointLeftArrowView = Backbone.View.extend({
    initialize: function (args) {
        _.bindAll(this, 'render');
        this.model.view = this;
        this.render();
    },
    clear : function() {
        $(this.el).remove();
    },
    fixWidth : function() {
       var container = $(this.el);
       var desiredWidth = $('.front',container).width() + $('.label',container).width() + $('.back',container).width()+10;
       if (this.right != undefined && this.right + desiredWidth > $('body').width() && BrowserInfo.isPadDevice()) {
         var maxLabelWidth = $('body').width() - this.right - $('.front',container).width() - $('.back',container).width() - 2;
         if (maxLabelWidth < 0 ) maxLabelWidth = 0;
         $('.label',container).text("").css("min-width", maxLabelWidth + "px");
         container.width($('.front',container).width() + $('.label',container).width() + $('.back',container).width()+8);
       }
       else
        container.width(desiredWidth);

    },
    render: function () {
       var container = $(this.el);
       container.addClass('action-arrow').addClass('left');
       container.append($("<div class='front' />"));
       container.append($("<div class='label' />").text(this.model.text() || "" ).css(this.model.labelCss() || {}));
       container.append($("<div class='back' />"));

       if (this.model.point() != undefined) {
          this.right = ($(document).width() - this.model.point().offset().left );
          container.css("top", (this.model.point().offset().top + (this.model.point().outerHeight() / 2) - 19) + "px");
          container.css("right", this.right + "px");
       }
       return this;
    }
});


var PointRightArrowView = Backbone.View.extend({
    initialize: function (args) {
        _.bindAll(this, 'render');
        this.model.view = this;
        this.render();
    },
    clear : function() {
        $(this.el).remove();
    },
    fixWidth : function() {
       var container = $(this.el);
       var desiredWidth = $('.front',container).width() + $('.label',container).width() + $('.back',container).width() + 10;
       if (this.left != undefined && this.left + desiredWidth > $('body').width() && BrowserInfo.isPadDevice()) {
         var maxLabelWidth = $('body').width() - this.left - $('.front',container).width() - $('.back',container).width() - 2;
         if (maxLabelWidth < 0 ) maxLabelWidth = 0;
         $('.label',container).text("").css("min-width", maxLabelWidth + "px");
         container.width($('.front',container).width() + $('.label',container).width() + $('.back',container).width()+10);
       }
       else
        container.width(desiredWidth);
    },
    updatePosition: function() {
       var container = $(this.el);
       if (this.model.point() != undefined) {
          var p = this.model.point();
          var top = this.model.point().offset().top;
          var height = this.model.point().outerHeight();
          if (p.children().size() == 1 && p.children().offset().top < top)
            top = p.children().offset().top;
          if (p.children().size() == 1 && p.children().outerHeight() > height)
            height = p.children().outerHeight();
          this.left = (this.model.point().offset().left + this.model.point().outerWidth() + 6);
          container.css("top", (top + (height / 2) - 19) + "px");
          container.css("left", this.left + "px");
       }
    },
    render: function () {
       var container = $(this.el);
       container.addClass('action-arrow').addClass('right');
       container.append($("<div class='front' />"));
       container.append($("<div class='label' />").text(this.model.text() || "" ).css(this.model.labelCss() || {}));
       container.append($("<div class='back' />"));

       this.updatePosition();
       return this;
    }
});


var ScrollUpArrowView = Backbone.View.extend({
    events: {
        "click"  :  "scroll"
    },
    initialize: function (args) {
        _.bindAll(this, 'render', 'scroll');
        this.model.view = this;
        this.render();
    },
    clear : function() {
        $(window).unbind('resize',this.updateRightMarginFunction);
        $(this.el).remove();
    },
    updatePosition: function() {},
    render: function () {
        var view = this;
        $(this.el).addClass("up").addClass("arrow").css("cursor", "pointer");
        this.updateRightMarginFunction = function() {view.updateRightMargin();};
        $(window).resize( this.updateRightMarginFunction);
        this.updateRightMargin();
        return this;
    },
    updateRightMargin : function() {
      var space = $(window).width() - 941;
      var margin = 0;
      var bigarrowmargin = 0;
      if (space > 0) {
        margin = space / 2;
        bigarrowmargin = (space + 941 - 112) / 2;
      } else {
        bigarrowmargin = (941 - 112) / 2;
      }
      $(this.el).css("right", bigarrowmargin + "px");

    },
    scroll: function(){
        mixpanel.track('Click fat arrow up');
       var model = this.model;
       var task = this.model.point();
       if (task == undefined) return;
       $('html,body').animate({
          scrollTop: task.offset().top - 150
       }, 1000, function() {model.scrollDone();});
       return false;
    }

});

var ScrollDownArrowView = Backbone.View.extend({
    events: {
        "click"  :  "scroll"
    },
    clear : function() {
        $(window).unbind('resize',this.checkIfDownArrowInFooterFunction);
        $(window).unbind('scroll',this.checkIfDownArrowInFooterFunction);
        $(window).unbind('resize',this.updateRightMarginFunction);
        $(this.el).remove();
    },
    initialize: function (args) {
        _.bindAll(this, 'render', 'scroll');
        this.model.view = this;
        this.render();
    },
    updatePosition: function() {},
    render: function () {
        var view = this;
        $(this.el).addClass("down").addClass("arrow").css("cursor", "pointer");
        this.updateRightMargin();
        this.checkIfDownArrowInFooterFunction = function() {view.checkIfDownArrowInFooter();};
        this.updateRightMarginFunction = function() {view.updateRightMargin();};
        $(window).resize(this.checkIfDownArrowInFooterFunction);
        $(window).scroll(this.checkIfDownArrowInFooterFunction);
        $(window).resize(this.updateRightMarginFunction);
        return this;
    },
    updateRightMargin : function() {
      var space = $(window).width() - 941;
      var margin = 0;
      var bigarrowmargin = 0;
      if (space > 0) {
        margin = space / 2;
        bigarrowmargin = (space + 941 - 112) / 2;
      } else {
        bigarrowmargin = (941 - 112) / 2;
      }
      $(this.el).css("right", bigarrowmargin + "px");

    },
    checkIfDownArrowInFooter : function() {
      if ($(".pagefooter").size() == 0) return;
      var footertop = $(".pagefooter").offset().top;
      var downarrowbottom = $(this.el).offset().top + $(this.el).height();
      if (downarrowbottom + 100 > footertop) {
        $(this.el).css("display","none");
      } else {
        $(this.el).css("display","block");
      }
    },
    scroll: function(){
        mixpanel.track('Click fat arrow down');
        var model = this.model;
        var task = this.model.point();
        if (task == undefined) return;
        var scrollbottom = task.offset().top + task.height() + 150;
        $('html,body').animate({
          scrollTop: scrollbottom - (window.innerHeight ? window.innerHeight : $(window).height())
        }, 2000, function() {model.scrollDone();});
       return false;
    }

});




window.Arrow = {
    init: function (args) {
          var model = new ArrowModel({
                          type  : args.type,
                          text  : args.text,
                          labelCss : args.labelCss,
                          point : args.point,
                          scrollDone : args.scrollDone
                    });
          var view = new ArrowView({model : model, el : $("<div/>")});
          return new Object({
              model : function() {return model;},
              view  : function() {return view;},
              clear  : function() {
                  view.clear();
                  model.destroy();
              },
              updatePosition : function() {
                  view.updatePosition();
              },
              blink : function(count) {
                    var arrow = this;
                    var el = $(view.el);
                    model.setBlinks(count);
                    var startBlinking = function() {
                      var i = model.blinks();
                      if (i <= 0 ) return;
                      else if (i % 2 == 0 )
                          el.css({opacity: '0',
                                  filter: 'alpha(opacity=0)'});
                      else
                          el.css({opacity: '1',
                                  filter: 'alpha(opacity=1)'});
                      model.setBlinks(i-1);
                      setTimeout(startBlinking,200);
                      }
                    startBlinking();

              },
              /* We need to recalculate width after appending arrow to page */
              fixWidth: function() {
                   if (view.fixWidth != undefined) view.fixWidth();
              }
            });
        }
};

})(window);
