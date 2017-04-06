var $ = require("jquery");
var BrowserInfo = require("./browserinfo.js").BrowserInfo;

/* Getting some information about browsers */


var BrowserInfo = exports.BrowserInfo = {
    doesNotSupportHoverPseudoclassSelector : function() {
       return $.browser.opera;
    },
    isPadDevice : function() {
       return  BrowserInfo.isIpad() || BrowserInfo.isIphone() || BrowserInfo.isAndroid();
    },
    isIpad : function(){
        return navigator.userAgent.match(/iPad/i) != null;
    },
    isIphone : function(){
        return navigator.userAgent.match(/iPhone/i) != null;
    },
    isWindowsPhone : function() {
        return navigator.userAgent.match(/Windows Phone/i) != null;
    },
    isAndroid : function(){
        return navigator.userAgent.match(/Android/i) != null;
    },
    isIOS9 : function(){
      return navigator.userAgent.match(/OS 9[0-9_]* like Mac OS X/i) != null;
    },
    isFirefox : function() {
        return navigator.userAgent.match(/Firefox/i) != null; //
    },
    isChrome : function() {
        return navigator.userAgent.match(/Chrome/i) != null; //
    },
    isChromeiOS : function() {
        return navigator.userAgent.match(/CriOS/i) != null;
    },
    isIE : function() {
        return navigator.userAgent.match(/MSIE|Trident/i) != null; // MSIE for IE <=10 and Trident for IE 11=<
    },
    isIETouch: function() {
        return navigator.msPointerEnabled;
    },
    isSafari: function() {
      return !BrowserInfo.isChrome() && navigator.userAgent.match(/Safari/i) != null;
    },
    isIE10 : function() {
      return BrowserInfo.isIE() && !BrowserInfo.isWindowsPhone() && $.browser.version === "10.0";
    },
    isIE9orLower : function() {
      return BrowserInfo.isIE() && !BrowserInfo.isWindowsPhone() && ($.browser.version > "3" && $.browser.version <= "9.0");
    },
    isSmallScreen : function() {
      if (window.outerWidth === 0) {
        // probably chrome, tab was opened in background, try to rely on screen.width alone
        return screen.width < 730;
      } else {
        // iPad returns this as ~768, but we add a bit of margin.
        return window.outerWidth < 730 || screen.width < 730;
      }
    },
    hasDragAndDrop: function () {
        var div = document.createElement("div");
        return (typeof div.ondrop !== "undefined");
    },
    hasFormData: function () {
        return window.hasOwnProperty("FormData");
    }
};



