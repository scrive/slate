// checks for ie
function hasSign2PluginIE() {
    try {
        return !!(new ActiveXObject("Nexus.SignerV2Ctl"));
    } catch(e) {
        return false;
    }
}

function hasNetIDPluginIE() {
    try {
        return !!(new ActiveXObject('IID.iIDCtl'));
    } catch(e) {
        return false;
    }
}

function hasSign2PluginMozilla() {
    return (navigator.plugins
            && navigator.plugins.length > 0
            && navigator.mimeTypes && navigator.mimeTypes["application/x-personal-signer2"]
            && navigator.mimeTypes["application/x-personal-signer2"].enabledPlugin);
}

function hasNetIDPluginMozilla() {
    return (navigator.plugins
            && navigator.plugins.length > 0
            && navigator.mimeTypes && navigator.mimeTypes["application/x-iid"]
            && navigator.mimeTypes["application/x-iid"].enabledPlugin);
}

function installSign2IE() {
    $("body").append('<OBJECT ID="signer2" CLASSID="CLSID:FB25B6FD-2119-4cef-A915-A056184C565E"> </OBJECT>');
}

function installNetIDIE() {
    $("body").append("<OBJECT NAME='iid' id='iid' WIDTH=0 HEIGHT=0 CLASSID='CLSID:5BF56AD2-E297-416E-BC49-00B327C4426E'> </OBJECT>");
}


function installSign2Mozilla() {
    $("body").append('<OBJECT id="signer2" type="application/x-personal-signer2" length=0 height=0></OBJECT>');
}

function installNetIDMozilla() {
    $("body").append("<OBJECT NAME='iid' id='iid' WIDTH=0 HEIGHT=0 TYPE='application/x-iid'></OBJECT>");
}

function flashBankIDMessage() {
    new FlashMessage({ content: localization.noBankIdInstalled, color: "red"});
    return false;
}

function flashTeliaMessage() {
    new FlashMessage({ content: localization.noTeliaInstalled, color: "red"});
    return false;
}

function failEleg(msg, personalNumber) {
    if( personalNumber!=undefined && personalNumber!="" && personalNumber!=null ) {
        msg = msg + " (" + personalNumber + ")";
    }
    new FlashMessage({ content: msg, color: "red"});
    LoadingDialog.close();
    return null;
}

function checkPlugin(iefn, otfn, msgfn) {
    if ((BrowserInfo.isIE() && iefn()) || otfn())
        return true;
    else
        msgfn();
    return false;
}

/* Totally new functions set for backbone connected stuff */

define(['Backbone', 'legacy_code'], function() {

window.Eleg = {
  // generate a TBS from the available data
   generateTBS : function(doctitle, docid, signatories) {
     var span = $('<span />').html(localization.tbsMessage);
     span.find('.put-document-name-here').text(doctitle);
     span.find('.put-document-id-here').text(docid);
     var signatoryList = "";
     $(signatories).each(function() {
         signatoryList += "\n" + this.fstname() + " " + this.sndname() + ", " + this.personalnumber();
     });
     span.find('.put-signing-parties-here').text(signatoryList);
     return span.text();
   },
   isUserCancelError: function(res) {
     var res = new String(res);
     // The error message for user abortion differs between eID providers and versions
     if (res && res.match(/8002|USER_ABORT|USER_CANCEL/))
       return true;

     return false;
   },
   getErrorMessage: function(res) {
      if (window.Eleg.isUserCancelError(res))
        return localization.youCancelledSigning;

      return localization.yourSigningPluginFailed + " " + res;
   },
   bankidSign : function(document, signatory, callback) {
      if (!checkPlugin(hasSign2PluginIE, hasSign2PluginMozilla, flashBankIDMessage))
        return false;
      LoadingDialog.open(localization.startingSaveSigning);

      var url;
      if(document.preparation()) // designview
        url = "/d/eleg/" + document.documentid();
      else
        url = "/s/eleg/" + document.documentid() +  "/" + document.viewer().signatoryid();
      var tbs = window.Eleg.generateTBS(document.title(), document.documentid(), document.signatories());
      $.ajax({
            'url': url,
            'dataType': 'json',
            'data': { 'provider' : 'bankid',
                      'tbs' : tbs
                    },
            'scriptCharset': "utf-8",
            'success': function(data) {
              if (data && data.status === 0)  {
	       console.log(data.tbs);
               LoadingDialog.close(); // this was opened just before starting
                if (BrowserInfo.isIE() && hasSign2PluginIE())
                    installSign2IE();
                else if (hasSign2PluginMozilla())
                    installSign2Mozilla();
                else {
                    flashBankIDMessage();
                    return; }
                var signer = $('#signer2')[0];
                if(!signer)  {
                     new FlashMessage({ content: localization.yourSigningPluginFailed, color: "red"});
                     LoadingDialog.close();
                     failEleg(localization.yourSigningPluginFailed);
                     return;
                }
               signer.SetParam('TextToBeSigned', data.tbs);
               signer.SetParam('Nonce', data.nonce);
               signer.SetParam('ServerTime', data.servertime);
               //signer.SetParam('TextCharacterEncoding', "UTF-8");
               var res = signer.PerformAction('Sign');
               if (res !== 0) // 0 means success
                {
                    new FlashMessage({ content: window.Eleg.getErrorMessage(res), color: "red"});
                    LoadingDialog.close();
                    return;
                }
                var signresult =  signer.GetParam('Signature');
                if (!signresult)
                    return;
                LoadingDialog.open(localization.verifyingSignature);
                callback({
                      "signature" : signresult,
                      "transactionid" : data.transactionid,
                      "eleg" : "bankid"
                });
            }
            else
               new FlashMessage({ content: data.msg, color: "red"});
            LoadingDialog.close();
            },
            error: repeatForeverWithDelay(250)
      });
    },
    teliaSign : function(document, signatory, callback) {
      if (!checkPlugin(hasNetIDPluginIE, hasNetIDPluginMozilla, flashTeliaMessage))
        return false;
      var url;
      if(document.preparation()) // designview
        url = "/d/eleg/" + document.documentid();
      else
        url = "/s/eleg/" + document.documentid() +  "/" + document.viewer().signatoryid();
      var tbs = window.Eleg.generateTBS(document.title(), document.documentid(), document.signatories());
        LoadingDialog.open(localization.startingSaveSigning);
        $.ajax({
            'url': url,
            'dataType': 'json',
            'data': { 'provider' : 'telia',
                      'tbs' : tbs
                    },
            'scriptCharset': "utf-8",
            'success': function(data) {
            if (data && data.status === 0)  {
                LoadingDialog.close();
                if (BrowserInfo.isIE() && hasNetIDPluginIE())
                     installNetIDIE();
                else if (hasNetIDPluginMozilla())
                     installNetIDMozilla();
                else {
                     flashTeliaMessage();
                     return; }
                var signer = $("#iid")[0];
                if(!signer) {
                     new FlashMessage({ content: localization.yourSigningPluginFailed, color: "red"});
                     LoadingDialog.close();
                     failEleg(localization.yourSigningPluginFailed);
                     return;
                }

                signer.SetProperty('DataToBeSigned', data.tbs);
                signer.SetProperty('Base64', 'true');
                signer.SetProperty('UrlEncode', 'false');
                signer.SetProperty('IncludeRootCaCert', 'true');
                signer.SetProperty('IncludeCaCert', 'true');
                var res = signer.Invoke('Sign');
                if (res !== 0) {
                    new FlashMessage({ content: window.Eleg.getErrorMessage(res), color: "red"});
                    LoadingDialog.close();
                    return;
                }
                var signresult =  signer.GetProperty('Signature');
                if (!signresult)
                    return;
                LoadingDialog.open(localization.verifyingSignature);
                callback({
                      "signature" : signresult,
                      "transactionid" : data.transactionid,
                      "eleg" : "telia"
                 });

            }
            else
               new FlashMessage({ content: data.msg, color: "red"});
            LoadingDialog.close();


        },
        error: repeatForeverWithDelay(250)

    });
    },
    mobileBankIDSign: function(document, signatory, callback, personnummer) {
        var url;
        if(document.preparation())// designview
            url = "/d/eleg/mbi/" + document.documentid();
        else
            url = "/s/eleg/mbi/" + document.documentid() +  "/" + document.viewer().signatoryid();
        console.log(url);
        LoadingDialog.open(localization.sign.eleg.mobile.startingMobileBankID);
        var fetching = true;

        var data = {};
        if(personnummer)
            data.personnummer = personnummer;
        $.ajax({
            'url': url,
            'dataType': 'json',
            'data': data,
            'type': 'POST',
            'scriptCharset': "utf-8",
            'success': function(data) {
                fetching = false;
                if (data && !data.error && data.message)  {
                    LoadingDialog.open(data.message);
                } else if (data && data.error) {
                    new FlashMessage({ content: data.error, color: "red"});
                    LoadingDialog.close();
                    return;
                }
                var m = new MobileBankIDPolling({docid: document.documentid()
                                                 , collecturl:url
                                                 ,trid: data.transactionid
                                                 ,slid: document.viewer().signatoryid()
                                                 ,callback: function() {
                                                     callback({"transactionid" : data.transactionid,
                                                               "eleg"  : "mobilebankid"
                                                              });
                                                 }
                                                 ,errorcallback: function(errormessage) {
                                                    var message = "";

                                                    LoadingDialog.close();

                                                    if (errormessage && errormessage.indexOf("USER_CANCEL")) {
                                                      // This means the user cancelled by clicking the right button in the interface
                                                      message = localization.youCancelledSigning;
                                                    } else {
                                                      // Unknown error, probably there has not been a mobile bankid issued for this person number.
                                                      message = localization.yourSigningPluginFailed;
                                                    }

                                                    new FlashMessage({ content: message, color: "red"});
                                                 }
                                                });
                var mv = new MobileBankIDPollingView({model:m});
                m.poll();

            }});
        // retry after 5 seconds if it hasn't worked.
        window.setTimeout(function() {if (fetching) window.Eleg.mobileBankIDSign(document,signatory,callback,personnummer);}, 5000);
    }

};

});
