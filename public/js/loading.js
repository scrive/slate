/* Loading dialog
 *
 * Open with LoadingDialog.open(string with html/jquery object, string with html/jquery object);
 * Close with LoadingDialog.close();
*/

(function(){

window.LoadingDialog = {
    open: function (message, submessage) {
      submessage = submessage || '';
      var spinner = $("<img src='/img/wait30trans.gif' style='margin:30px'/>");
      return ScreenBlockingDialog.open({header: message,
                                        subheader: submessage,
                                        content: spinner});
    },
    close : function() {
      return ScreenBlockingDialog.close();
    }
};
})();
