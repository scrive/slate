(function(window){

window.Calendar = Backbone.Model.extend({
    defaults: {
        on : $('<div/>'),
        change : function() {return false},
        value : 0,
        maxValue : 90
    },
    initialize : function(args){
        var activator  = this.get("on");
        var onchange = this.get("change");
        activator.dateinput({
            format: 'dd-mm-yy',
            value : new Date(new Date().getTime() + args.days * 24 * 60 * 60 * 1000),
            change: function() {
                var ONE_DAY = 1000 * 60 * 60 * 24;
                var date_ms = activator.data("dateinput").getValue().getTime();
                var difference_ms = Math.abs(date_ms - new Date().getTime());
                var dist = Math.floor(difference_ms / ONE_DAY) + 1;
                onchange(dist);
            },
            min: 0,
            max: this.get("maxValue"),
            onShow : function(a,b,c) {
              $("#calroot").css("top",activator.offset().top);
            }
        });
    },
    setDays : function(days) {
            this.get("on").data("dateinput").setValue(new Date());
            this.get("on").data("dateinput").addDay(days);
    }
});





})(window);
