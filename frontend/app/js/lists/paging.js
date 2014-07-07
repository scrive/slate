/*
 * Pagination for lists + persistance
 */

define(['Backbone', 'legacy_code'], function() {

    window.Paging = Backbone.Model.extend({
        defaults: {
            // first visible item index
            itemMin: 0,
            // last visible item index. If itemMax < itemMin, there are no items
            itemMax: 0,
            pageCurrent: 0,
            pageSize: 0,
            // Maximal number of pages that are sown
            maxNextPages : 5,
            showLimit : undefined,
            showOnlyForMultiplePages : false
        },
        disabled: function() {
            return this.get("disabled") != undefined && this.get("disabled") == true;
        },
        itemMin: function() {
            return this.get("itemMin");
        },
        itemMax: function() {
            return this.get("itemMax");
        },
        maxNextPages:function() {
            return this.get("maxNextPages");
        },
        pageCurrent: function() {
            return this.get("pageCurrent");
        },
        pageSize: function() {
            return this.get("pageSize");
        },
        changePage: function(i) {
            this.set({ "pageCurrent": i });
        },
        changePageFunction: function(i) {
            var paging = this;
            return function() { paging.changePage(i); };
        },
        updateWithServerResponse: function(resp) {
            this.set(resp);
        },
        showLimit : function() {
            if (this.get("showLimit") != undefined && this.get("pageSize") != undefined)
                return Math.min(this.get("showLimit"),this.get("pageSize"));
            else if (this.get("showLimit") != undefined)
                return this.get("showLimit");
            else
                return this.get("pageSize");
        },
        setShowLimit : function(i) {
            this.set({ "showLimit": i });
        },
        hasManyPages : function() {
            return this.pageSize() <= this.itemMax();
        },
        // Returns true, if there are no positions for current page, but there are some for earlier pages.
        shouldSwitchToEarlierPage : function() {
           return this.pageCurrent() > 0 && (this.itemMax() <  (this.pageCurrent()) * this.pageSize());
        },
        showOnlyForMultiplePages : function() {
            return this.get("showOnlyForMultiplePages");
        }
    });

    window.PagingView = Backbone.View.extend({
        model: Paging,
        initialize: function(args) {
            _.bindAll(this, 'render');
            var view = this;
            this.model.bind('change', function(){view.render();});
            this.render();
        },
        render: function() {
            $(this.el).empty();
            var paging = this.model;
            var main = $("<div class='pages'>");
            var pages = $("<div />");
            var maxNextPages = paging.maxNextPages();
            var maxPage = paging.pageCurrent() + maxNextPages - 1;
            if (paging.hasManyPages() || !paging.showOnlyForMultiplePages()) {

              var writePage = function(t,n) {
                  var a = $("<span class='page-change' />").text(t);
                  a.click(paging.changePageFunction(n));
                  pages.append(a);
                  return a;
              };

              for(var i=0;i < maxPage && i*paging.pageSize() <= paging.itemMax();i++) {
                  var a = writePage((i+1)+"", i);
                  if (i == paging.pageCurrent())
                      a.addClass("current");
              }
              if (maxPage*paging.pageSize() < paging.itemMax())
                  writePage(" > ", maxPage);
            }

            main.append(pages);

            $(this.el).append(main);
        }
    });

});
