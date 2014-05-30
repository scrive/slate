define(['Backbone', 'legacy_code'], function() {

    /*
      Holds information relevant to blocking for a user.

    */
    window.BlockingInfoModel = Backbone.Model.extend({
        defaults: {
            block: false,
            dunning: false
        },
        url: function() {
            return "/api/frontend/paymentinfo";
        },
        docsTotal: function() {
            return this.get('docsTotal');
        },
        docsUsed: function() {
            return this.get('docsUsed');
        },
        docsLeft: function() {
            var ret = this.docsTotal() - this.docsUsed();
            if(ret < 0)
                return 0;
            return ret;
        },
        plan: function() {
            return this.get('plan');
        },
        status: function() {
            return this.get('status');
        },
        isAdminUser: function() {
            return this.get('adminuser');
        },
        willCancel: function() {
            return this.get('canceled');
        },
        isEnterprise: function() {
            return this.plan() === 'enterprise';
        },
        isTrial: function() {
            return this.plan() === 'trial';
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
                   !this.isTrial()       &&
                   !this.isFree()        &&
                    this.isActive()      &&
                    this.docsLeft() <= 0;
        },
        billingEnds: function() {
            return this.get('billingEnds') && moment.utc(this.get('billingEnds'));
        },
        daysLeft: function() {
            return Math.ceil(moment.duration(this.billingEnds() - moment()).asDays());
        },
        reload: function() {
            var model = this;
            model.fetch({success: function() {
                model.trigger('fetch');
                mixpanel.people.set({
                    'Payment Plan'        : model.plan(),
                    'Subscription status' : model.status(),
                    'Documents used'      : model.docsUsed(),
                    'Documents total'     : model.docsTotal(),
                    'Billing ends'        : model.billingEnds(),
                    'Dunning?'            : model.isDunning()
                });
            }});
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
            $el.removeClass('warn').removeClass('good').removeClass('hide');
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
            if(model.isFree() && model.docsLeft() > 0 ) {
                var res = $("<span>" + localization.blocking.free.has.headline + "</span>");
                $(".put-docs-used-here",res).text(model.docsUsed());
                return res;
            }
            else if(model.isFree())
                return localization.blocking.free.hasNot.headline;
            else if(model.hasUsedAll())
                return localization.blocking.usedall.headline;
            else if(model.isOverdue())
                return localization.blocking.overdue.headline;
            else if(model.isDunning())
                return localization.blocking.dunning.headline;
            else if(model.isCanceled()) {
                var res = $("<span>" + localization.blocking.canceled.headline  + "</span>");
                $(".put-docs-used-here",res).text(model.docsUsed());
                return res;
            }
            else if(model.isDeactivated())
                return localization.blocking.deactivated.headline;
            else if(model.willCancel()) {
                var res = $("<span>" + localization.blocking.willcancel.headline + "</span>");
                $(".put-days-left-here",res).text(model.daysLeft());
                return res;
            }
        },
        subtext1: function() {
            var view = this;
            var model = view.model;

            if(model.isFree() && model.docsLeft() > 0)
                return "";
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
                return "";
            else if(model.isFree())
                return "";
            else if(model.hasUsedAll())
                return "";
            else if(model.isOverdue())
                return localization.blocking.overdue.subtext2;
            else if(model.isDunning())
                return localization.blocking.dunning.subtext2;
            else if(model.isCanceled())
                return localization.blocking.canceled.subtext2;
            else if(model.isDeactivated())
                return "";
            else if(model.willCancel())
                return "";
            return "";
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
            mixpanel.track('Click blocking header');
            if(model.isFree()) {
                view.paymentsPopup({
                    title: localization.blocking.free.click.title
                });
            }
            else if(model.hasUsedAll())
                window.location = 'mailto:support@scrive.com';
            else if(model.isOverdue())
                window.location = '/account#subscription';
            else if(model.isDunning())
                window.location = '/account#subscription';
            else if(model.isCanceled())
                window.location = '/account#subscription';
            else if(model.isDeactivated())
                window.location = 'mailto:support@scrive.com';
            else if(model.willCancel())
                window.location = '/account#subscription';
        },
        paymentsPopup: function(opts) {
            var div = $('<div />').addClass('price-plan');
            new Confirmation({
                title: opts.title,
                content: div,
                acceptVisible: false,
                width: 980
            });
            var o = {hideContacts:true};
            if(opts.header)
                o.header = opts.header;
            PricePage(o).show(div);
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
                title: localization.blocking.free.create.title,
                header: localization.blocking.free.heading
            });
        },
        freeCSVMessage: function() {
            return localization.blocking.free.csv.header;
        },
        overdueCreatePopup: function() {
            var p = $('<p />');
            p.html(localization.blocking.overdue.create.body);
            new Confirmation({
                title: localization.blocking.overdue.create.title,
                content: p,
                acceptText: localization.blocking.button.doublecheck,
                acceptColor: "green",
                onAccept: function() {
                    window.location = "/account#subscription";
                }
            });
        },
        overdueCSVMessage: function() {
            return localization.blocking.overdue.csv.body;
        },
        canceledCreatePopup: function() {
            var p = $('<p />');
            p.html(localization.blocking.canceled.create.body);
            new Confirmation({
                title: localization.blocking.canceled.create.title,
                content: p,
                acceptText: localization.blocking.button.reinstate,
                acceptColor: "green",
                onAccept: function() {
                    window.location = "/account#subscription";
                }
            });
        },
        canceledCSVMessage: function() {
            return localization.blocking.canceled.csv.body;
        },
        deactivatedCreatePopup: function() {
            var p = $('<p />');
            p.html(localization.blocking.deactivated.create.body);
            new Confirmation({
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
            new Confirmation({
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
        model.reload();
        return {
            model: model,
            show: function(selector) {
                $(selector).html(view.el);
            },
            el : function() {
               return $(view.el);
            } ,
            shouldBlockDocs: function(n) {
                return n > model.docsLeft() && !model.isAdminUser();
            },
            createPopup: function() {
                view.createPopup();
            },
            csvMessage: function(no_of_parties) {
              var msg = $("<span>" + view.csvMessage() + "</span>");
              $(".put-no-of-parties-here",msg).text(no_of_parties);
              $(".put-docs-left-here",msg).text(model.docsLeft());
              return msg;
            },
            reload: function() {
                model.reload();
            },
            hide: function() {
                $(view.el).addClass('hide');
            },
            unHide: function() {
                $(view.el).removeClass('hide');
            }
        };
    };

});
