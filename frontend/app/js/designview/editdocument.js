/*
  Anything you see in the second tab in design view.

*/
define(['Backbone', 'legacy_code'], function() {

    // expected model: DesignViewModel
    var DesignViewDraggablesView = Backbone.View.extend({
        className: 'design-view-action-document-draggables',
        initialize: function(args) {
            var view = this;
            _.bindAll(view);
            view.render();
            view.model.document().bind('change:signatories', view.render);
        },
        render: function() {
            var view = this;

            var div = $('<div />');

            div.append(view.help1());
            div.append(view.help2());
            div.append(view.text());
            div.append(view.signature());
            div.append(view.checkbox());


            view.$el.html(div.children());

            return view;
        },
        help1: function() {
            var div = $("<div class='design-view-action-document-draggables-help help1'/>");
            div.append($("<div class='wrapper'>")
              .append($("<div class='icon'/>"))
              .append($("<div class='text-wrapper'/>").append($("<span class='text'/>").text(localization.designview.draggablehelp1))));
            return div;
        },
        help2: function() {
            var div = $("<div class='design-view-action-document-draggables-help help2'/>");
            div.append($("<div class='wrapper'>")
              .append($("<div class='icon' />"))
              .append($("<div class='text-wrapper'/>").append($("<span class='text'/>").text(localization.designview.draggablehelp2))));


            return div;
        },

	createDraggable: function(fieldOrPlacementFN, buttonText, cssClass, fontSize, onFieldAdded) {
          var div = $("<div class='design-view-action-document-draggable design-view-action-document-draggable-" + cssClass + "' />");
          var wra = $("<div class='design-view-action-document-draggable-wrapper'/>");
          var innerWrapper = $("<div class='design-view-action-document-draggable-inner-wrapper'/>");
          var iconWrapper = $("<div class='design-view-action-document-draggable-icon-wrapper' />");
          var imgdiv = $("<div class='design-view-action-document-draggable-icon' />");
          var txt = $("<div class='design-view-action-document-draggable-text'/>");
          var document = this.model.document();
          var isDisabledCallback = function(field) {
            if (field.type() !== 'signature') {
              // we only block d&d when there are no signing parties for signatures
              return true;
            }
            if (document.signatoriesWhoSign().length > 0) {
              return true;
            } else {
              new FlashMessage({type: 'error', content: localization.designview.dndDisabled});
              return false;
            }
          };
          draggebleField(div, fieldOrPlacementFN, undefined, undefined, true,fontSize,onFieldAdded, isDisabledCallback);

          div.append(wra);
          wra.append(innerWrapper);
          innerWrapper.append(iconWrapper);
          innerWrapper.append(txt);
          iconWrapper.append(imgdiv);
          txt.append($('<span>').text(buttonText));

          return div;
	},
        checkbox: function() {
            var model = this.model;
	    var fieldOrPlacementFN = function() {
                return new Field({fresh: false,
                                  type: 'checkbox',
                                  value : "checked",
                                  signatory: model.document().author(),
                                  name: "temp-checkbox"
                });
            };

        return this.createDraggable(fieldOrPlacementFN, localization.designview.checkbox, 'checkbox',undefined,function(f) { f.setName(model.document().newCheckboxName());});
        },
        signature: function() {
            var model = this.model;
            var fieldOrPlacementFN = function() {
                return new Field({
                  fresh:false,
                  ddSignature : true,
                  type:'signature',
                  signatory: model.document().signatoriesWhoSign()[0],
                  name: "temp-signature"});
            };

	    return this.createDraggable(fieldOrPlacementFN, localization.designview.signatureBox, 'signature', undefined, function(f) { f.setName(model.document().newSignatureName());});
        },
        text: function() {
            var model = this.model;
	    var fieldOrPlacementFN = function() {
                return new Field({signatory: model.document().author(),
				  name: 'fake',
				  type: 'fake',
				  value: localization.designview.freeTextBox});
            };

	    return this.createDraggable(fieldOrPlacementFN, localization.designview.freeTextBox, 'textbox', 16);
	}
	});



    window.DesignViewDraggablesView = function(args) {
        return new DesignViewDraggablesView(args);
    };

});
