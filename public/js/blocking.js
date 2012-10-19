(function(window) {

    /*
      Holds information relevant to blocking for a user.
      
    */
    window.BlockingInfoModel = Backbone.Model.extend({
        defaults: {
            block: false,
            dunning: false
        },
        url: function() {
            return "/blockinginfo";
        },
        docsTotal: function() {
            if(this.isEnterprise())
                return 500000; 
            if(!this.isFree() && this.isActive())
                return 100; // # of docs it says in the TOS
            else 
                return 3;
        },
        docsUsed: function() {
            return Math.min(this.get('docsused'), this.docsTotal());
        },
        docsLeft: function() {
            return this.docsTotal() - this.docsUsed();
        },
        plan: function() {
            return this.get('plan');
        },
        status: function() {
            return this.get('status');
        },
        willCancel: function() {
            return this.get('canceled');
        },
        isEnterprise: function() {
            return this.plan() === 'enterprise';
        },
        isFree: function() {
            return this.plan() === 'free';
        },
        isActive: function() {
            return this.status() === 'active';
        },
        isCanceled: function() {
            return this.status() === 'canceled';
        },
        isDeactivated: function() {
            return this.status() === 'deactivated';
        },
        isOverdue: function() {
            return this.status() === 'overdue';
        },
        isDunning: function() {
            return this.get('dunning');
        },
        hasUsedAll: function() {
            return !this.isEnterprise()  && 
                   !this.isFree()        && 
                    this.isActive()      &&
                    this.docsLeft() <= 0;
        }
    });

    window.BlockingInfoView = Backbone.View.extend({
        className: 'blocking-info',
        initialize: function(args) {
            _.bindAll(this);
            this.model.bind('change reset fetch', this.render);
        },
        setStyle: function() {
            var view = this;
            var model = view.model;
            var $el = $(view.el);
            $el.removeClass('warn').removeClass('good');
            if(model.isFree() && model.docsLeft() > 0)
                $el.addClass('good');
            else if(model.isFree())
                $el.addClass('warn');
            else if(model.hasUsedAll())
                $el.addClass('warn');
            else if(model.isOverdue())
                $el.addClass('warn');
            else if(model.isDunning())
                $el.addClass('good');
            else if(model.isCanceled())
                $el.addClass('warn');
            else if(model.isDeactivated())
                $el.addClass('warn');
            else if(model.willCancel())
                $el.addClass('good');
        },
        headline: function() {
            var view = this;
            var model = view.model;
            if(model.isFree() && model.docsLeft() > 0)
                return localization.blocking.free.has.headline + model.docsUsed() + " / " + model.docsTotal();
            else if(model.isFree())
                return localization.blocking.free.hasNot.headline + model.docsUsed() + " / " + model.docsTotal();
            else if(model.hasUsedAll())
                return localization.blocking.usedall.headline;
            else if(model.isOverdue())
                return localization.blocking.overdue.headline;
            else if(model.isDunning())
                return localization.blocking.dunning.headline;
            else if(model.isCanceled())
                return localization.blocking.canceled.headline + model.docsUsed() + " / " + model.docsTotal();
            else if(model.isDeactivated())
                return localization.blocking.deactivated.headline + model.docsUsed() + " / " + model.docsTotal();
            else if(model.willCancel())
                return localization.blocking.willcancel.headline;
        },
        subtext1: function() {
            var view = this;
            var model = view.model;
            if(model.isFree() && model.docsLeft() > 0)
                return localization.blocking.free.has.subtext1;
            else if(model.isFree())
                return localization.blocking.free.hasNot.subtext1;
            else if(model.hasUsedAll())
                return localization.blocking.usedall.subtext1;
            else if(model.isOverdue())
                return localization.blocking.overdue.subtext1;
            else if(model.isDunning())
                return localization.blocking.dunning.subtext1;
            else if(model.isCanceled())
                return localization.blocking.canceled.subtext1;
            else if(model.isDeactivated())
                return localization.blocking.deactivated.subtext1;
            else if(model.willCancel())
                return localization.blocking.willcancel.subtext1;
        },
        subtext2: function() {
            var view = this;
            var model = view.model;
            if(model.isFree() && model.docsLeft() > 0)
                return ""; //localization.blocking.free.has.subtext2;
            else if(model.isFree())
                return ""; //localization.blocking.free.hasNot.subtext2;
            else if(model.hasUsedAll())
                return ""; //localization.blocking.usedall.subtext2;
            else if(model.isOverdue())
                return localization.blocking.overdue.subtext2;
            else if(model.isDunning())
                return localization.blocking.dunning.subtext2;
            else if(model.isCanceled())
                return localization.blocking.canceled.subtext2;
            else if(model.isDeactivated())
                return localization.blocking.deactivated.subtext2;
            else if(model.willCancel())
                return localization.blocking.willcancel.subtext2;
        },
        makeBox: function() {
            var view = this;
            var model = view.model;
            
            var container = $("<div />");
            container.append($("<div class='headline' />").html(this.headline()));
            container.append($("<div class='subheadline' />").html(this.subtext1()));
            container.append($("<div class='subheadline' />").html(this.subtext2()));

            view.setStyle();

            return container;
        },
        render: function() {
            var view = this;
            var model = view.model;
            var $el = $(view.el);
            $el.unbind('click');
            if(model.isFree() || 
               model.isOverdue() ||
               model.isDunning() || 
               model.isCanceled() || 
               model.isDeactivated() ||
               model.willCancel() ||
               model.hasUsedAll()) {
                $el.html(view.makeBox());
                $el.bind('click', function() {
                    view.clickAction();
                });
            }
        },
        clickAction: function() {
            var view = this;
            var model = view.model;
            if(model.isFree())
                view.paymentsPopup({
                    title: model.docsUsed() + " " + localization.blocking.free.click.title,
                    header: localization.blocking.free.click.header
                });
            else if(model.hasUsedAll())
                window.location = 'mailto:support@scrive.com';
            else if(model.isOverdue())
                window.location = '/payments/dashboard';
            else if(model.isDunning())
                window.location = '/payments/dashboard';
            else if(model.isCanceled())
                window.location = '/payments/dashboard';
            else if(model.isDeactivated())
                window.location = 'mailto:support@scrive.com';
            else if(model.willCancel())
                window.location = '/payments/dashboard';
        },
        paymentsPopup: function(opts) {
            var div = $('<div />').addClass('price-plan');
            Confirmation.popup({
                title: opts.title,
                content: div,
                acceptVisible: false,
                width: "906px"
            });
            PricePage({header : opts.header, showContact: false}).show(div);
        },
        createPopup: function() {
            var view = this;
            var model = view.model;

            if(model.isFree())
                view.freeCreatePopup();
            else if(model.isOverdue())
                view.overdueCreatePopup();
            else if(model.isCanceled())
                view.canceledCreatePopup();
            else if(model.isDeactivated())
                view.deactivatedCreatePopup();
            else
                view.payingCreatePopup();
        },
        csvMessage: function() {
            var view = this;
            var model = view.model;
           
            if(model.isFree())
                return view.freeCSVMessage();
            else if(model.isOverdue())
                return view.overdueCSVMessage();
            else if(model.isCanceled())
                return view.canceledCSVMessage();
            else if(model.isDeactivated())
                return view.deactivatedCSVMessage();
            else
                return view.payingCSVMessage();
        },
        freeCreatePopup: function() {
            this.paymentsPopup({
                title: this.model.docsUsed() + " " + localization.blocking.free.create.title,
                header: localization.blocking.free.create.header
            });
        },
        freeCSVMessage: function() {
            return localization.blocking.free.csv.header;
        },
        overdueCreatePopup: function() {
            var p = $('<p />');
            p.html(localization.blocking.overdue.create.body);
            Confirmation.popup({
                title: localization.blocking.overdue.create.title,
                content: p,
                acceptText: localization.blocking.button.doublecheck,
                acceptColor: "green",
                onAccept: function() {
                    window.location = "/payments/dashboard";
                }
            });
        },
        overdueCSVMessage: function() {
            return localization.blocking.overdue.csv.body;
        },
        canceledCreatePopup: function() {
            var p = $('<p />');
            p.html(localization.blocking.canceled.create.body);
            Confirmation.popup({
                title: localization.blocking.canceled.create.title,
                content: p,
                acceptText: localization.blocking.button.reinstate,
                acceptColor: "green",
                onAccept: function() {
                    window.location = "/payments/dashboard";
                }
            });
        },
        canceledCSVMessage: function() {
            return localization.blocking.canceled.csv.body;
        },
        deactivatedCreatePopup: function() {
            var p = $('<p />');
            p.html(localization.blocking.deactivated.create.body);
            Confirmation.popup({
                title: localization.blocking.deactivated.create.title,
                content: p,
                acceptText: localization.blocking.button.contact,
                acceptColor: "green",
                onAccept: function() {
                    window.location = "mailto:support@scrive.com";
                }
            });
        },
        deactivatedCSVMessage: function() {
            return localization.blocking.deactivated.csv.body;
        },
        payingCreatePopup: function() {
            var p = $('<p />');
            p.html(localization.blocking.paying.create.body);
            Confirmation.popup({
                title: localization.blocking.paying.create.title,
                content: p,
                acceptText: localization.blocking.button.contact,
                acceptColor: "green",
                onAccept: function() {
                    window.location = "mailto:support@scrive.com";
                }
            });
        },
        payingCSVMessage: function() {
            return localization.blocking.paying.csv.body;
        }
    });

    window.Blocking = function() {
        var model = new BlockingInfoModel({});
        var view = new BlockingInfoView({model:model});
        model.fetch({success:function() {
            model.trigger('fetch');
        }});
        return {
            model: model,
            show: function(selector) {
                $(selector).html(view.el);
            },
            shouldBlockDocs: function(n) {
                return n > model.docsLeft();
            },
            createPopup: function() {
                view.createPopup();
            },
            csvMessage: function() {
                return view.csvMessage();
            }
        }
    };

}(window));
