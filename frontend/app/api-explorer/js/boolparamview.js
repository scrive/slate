
(function (window) {

window.BoolParamView  = Backbone.View.extend({
  initialize: function (args) {
    _.bindAll(this, "render");
    this.param = args.param;
    this.call = args.call;
    this.render();
  },
  render: function () {
    var self = this;
    var param = this.param;
    var call = this.call;
    var id = call.urlHash() + "-" + param.argName();

    var mainRow = $("<div class='row'>");
    $(this.el).append(mainRow);
    var input = $("<input type='checkbox' id='" + id + "'/>");
    input.attr("checked",  call.setParamValue(param) == "true");
    input.change(function () {
        if (input.is(":checked")) {
          call.setParamValue(param, "true");
        } else {
          call.setParamValue(param, undefined);
        }
      });

    var description = $("<p>");
    if(param.optional()) description.append($("<em>Optional.</em>"));
    description.append($("<p>").text(param.description()));

    mainRow.append(
             $("<div class='col-xs-6'>")
               .append($("<p class='checkbox'/>")
                 .append($("<label for='" + id + "'/>").append(input).append($("<strong/>").text(param.name())))
               )
             )
           .append(
             $("<div class='col-xs-6'>").append($("<p/>").append(description)));

    return this;
  }
});

})(window);
