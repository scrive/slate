/* Definition of documents archive */

define(['Backbone', 'legacy_code'], function() {

window.DocumentCellsDefinition = function(archive) { return  [
        new Cell({name: "ID", width:"30px", field:"id", special: "select"}),
        new Cell({name: localization.archive.documents.columns.status, width:"62px", field:"status",
                 rendering: function(status,idx,listobject) {
                    var icon = jQuery("<div class='icon status "+status+"'></div>");
                    var tip = jQuery("<div id='tooltip-"+status+"'> <div class='icon status "+status+"'></div><p>"+
                                      localization.statusToolTip[status]+"</p></div>");
                    ToolTip.set({
                        on: icon,
                        tip: tip
                    });
                    return icon;
                 }
        }),
        new Cell({name: localization.archive.documents.columns.time, width:"105px", field:"time", special: "rendered",
                  rendering: function(time) {
                         if (time != undefined && time != "")
                           return $("<span/>").text(new Date(Date.parse(time)).toTimeAbrev()).attr("title",new Date(Date.parse(time)).fullTime());
                         else return $("<span/>");
        }}),
        new Cell({width:"5px" }),
        new Cell({name: localization.archive.documents.columns.sender, width:"140px", field:"author",  special: "link"}),
        new Cell({width:"5px" }),
        new Cell({name: localization.archive.documents.columns.party, width:"210px", field:"party", special: "expandable", subfield : "name"}),
        new Cell({name: localization.archive.documents.columns.title, width:"230px", substyle: "", field:"id",special: "rendered",
                 rendering: function(value,idx,listobject) {
                    if (idx == undefined)
                       {
                            return $("<a class='s-archive-document-title'/>").text(listobject.field("title")).attr("href",listobject.link());
                       }
                 }})
        ];
};

window.DocumentSelectsDefinition = function(archive) { return  _.flatten([
            new SelectFiltering({
                             name: "status",
                             textWidth : "135px",
                             options: [{name: localization.filterByStatus.showAnyStatus, value: ""},
                                       {name: localization.filterByStatus.showDraft,     value: "[draft]"},
                                       {name: localization.filterByStatus.showCancelled, value: "[cancelled,rejected,timeouted,problem]"},
                                       {name: localization.filterByStatus.showSent,      value: "[sent,delivered,read,opened,deliveryproblem]"},
                                       {name: localization.filterByStatus.showSigned,    value: "[signed]"}
                                      ]}),
            archive.forCompanyAdmin() ?
              [new SelectAjaxFiltering({
                             name: "sender",
                             textWidth : "135px",
                             text : "sender",
                             optionsURL : "/companyaccounts",
                             defaultName : localization.filterByAuthor.showAnyAuthor,
                             optionsParse: function(resp) {
                                        var options = [];
                                        _.each(resp.list, function(l) {
                                          var fields = l.fields;
                                          var id = fields["id"];
                                          var name = fields["fullname"];
                                          if (name == undefined || name == "" || name == " ")
                                            name = fields["email"];
                                          if (fields["activated"])
                                            options.push({name : name , value : id });
                                        });
                                        return options;
                                   }
                 })] : [],
            new IntervalDoubleSelectFiltering({
                             name: "time",
                             textWidth : "100px",
                             selectedBottomPrefix : localization.filterByTime.filterForm,
                             selectedTopPrefix :    localization.filterByTime.filterTo ,
                             options: function() {
                                        var year = archive.year();
                                        var month = archive.month();
                                        var options = [{name : localization.filterByTime.filterForm , value : "<" }];
                                        var time = new Date();
                                        while (year < time.getFullYear() || (year == time.getFullYear() && month <= time.getMonth() + 1)) {
                                            var name = capitaliseFirstLetter(localization.months[month-1].slice(0,3) + " " + year);
                                            options.push({name : name , value : "("+month + "," + year + ")" });
                                            month++;
                                            if (month == 13) {month = 1; year++;}
                                        }
                                        options.push({name : localization.filterByTime.filterTo , value : ">" });
                                        return options} ()
                             })
            ]);
};

window.DocumentsListDefinition = function(archive) { return {
    name : "Documents Table",
    loadOnInit : false,
    schema: new Schema({
    url: "/api/frontend/list",
    extraParams : { documentType : "Document" },
    sorting: new Sorting({ fields: ["title", "status", "time", "party", "author"]}),
    paging: new Paging({}),
    textfiltering: new TextFiltering({text: "", infotext: localization.archive.documents.search}),
    selectfiltering : DocumentSelectsDefinition(archive),
    cells : DocumentCellsDefinition(archive),
    actions : [
        new ListAction({
            name :  localization.archive.documents.sendreminder.action,
            emptyMessage :  localization.archive.documents.sendreminder.emptyMessage,
            notAvailableMessage :  localization.archive.documents.sendreminder.notAvailableMessage,
            size: "normal",
            avaible : function(doc){
              return doc.field("status") == "sent"      ||
                     doc.field("status") == "delivered" ||
                     doc.field("status") == "read"      ||
                     doc.field("status") == "opened";
            },
            onSelect : function(docs) {
                 var content = jQuery("<p/>");
                             if (docs.length == 1) {
                               var span = $('<span />').html(localization.archive.documents.sendreminder.bodysingle);
                               span.find('.put-document-name-here').html(jQuery("<strong/>").text(docs[0].field("title")));
                               content.append(span);
                             } else {
                               var span = $('<span />').html(localization.archive.documents.sendreminder.bodymulti);
                               span.find('.put-number-of-documents-here').text(docs.length);
                               content.append(span);
                             }
                             var confirmationPopup = new Confirmation({
                                acceptText: localization.ok,
                                rejectText: localization.cancel,
                                title: localization.archive.documents.sendreminder.action,
                                icon: '/img/modal-icons/remind.png',
                                content: content,
                                onAccept : function() {
                                    mixpanel.track('Send reminder');
                                    new Submit({
                                                url: "/d/remind",
                                                method: "POST",
                                                documentids: "[" + _.map(docs, function(doc){return doc.field("id");}) + "]",
                                                ajaxsuccess : function() {
                                                    new FlashMessage({color : "green", content : localization.archive.documents.sendreminder.successMessage});
                                                    archive.documents().recall();
                                                    confirmationPopup.clear();
                                                },
                                                ajaxerror : function() {
                                                    new FlashMessage({color : "red", content : localization.archive.documents.sendreminder.errorMessage});
                                                    archive.documents().recall();
                                                    confirmationPopup.clear();
                                                }
                                          }).sendAjax();
                                }
                              });
                             return true;
            }
        }),
        new ListAction({
            name :  localization.archive.documents.cancel.action,
            emptyMessage :  localization.archive.documents.cancel.emptyMessage,
            notAvailableMessage :  localization.archive.documents.cancel.notAvailableMessage,
            size: 'normal',
            avaible : function(doc){
              return (   _.contains(['sent', 'delivered', 'read', 'opened'], doc.field('status'))
                      && (doc.get('isauthor') || (   doc.get('docauthorcompanysameasuser')
                                                  && archive.forCompanyAdmin())));
            },
            onSelect : function(docs) {
                             var confirmationPopup = new Confirmation({
                                acceptText: localization.ok,
                                rejectText: localization.cancel,
                                title: localization.archive.documents.cancel.action,
                                icon: '/img/modal-icons/sign.png',
                                content: jQuery("<p/>").text(localization.archive.documents.cancel.body),
                                onAccept : function() {
                                    mixpanel.track('Cancel document');
                                    new Submit({
                                                url: "/d/cancel",
                                                method: "POST",
                                                documentids: "[" + _.map(docs, function(doc){return doc.field("id");}) + "]",
                                                ajaxsuccess : function() {
                                                    new FlashMessage({color : "green", content : localization.archive.documents.cancel.successMessage});
                                                    archive.documents().recall();
                                                    confirmationPopup.clear();
                                                },
                                                ajaxerror : function() {
                                                    archive.documents().recall();
                                                    confirmationPopup.clear();
                                                }
                                          }).sendAjax();
                                }
                              });
                             return true;
            }
        }),
        new ListAction({
            name : localization.archive.documents.remove.action,
            emptyMessage :  localization.archive.documents.cancel.emptyMessage,
            size: 'normal',
            avaible : function(doc){ return true;},
            onSelect : function(docs) {
                        var confirmationText = $('<span />').html(localization.archive.documents.remove.body);
                        var listElement = confirmationText.find('.put-one-or-more-things-to-be-deleted-here');
                        if (docs.length == 1) {
                          listElement.html($('<strong />').text(docs[0].field("title")));
                        } else {
                          listElement.text(docs.length + (" " + localization.documents).toLowerCase());
                        }
                             var confirmationPopup = new Confirmation({
                                acceptText: localization.archive.documents.remove.action,
                                rejectText: localization.cancel,
                                title: localization.archive.documents.remove.action,
                                icon: '/img/modal-icons/delete.png',
                                content: confirmationText,
                                oneClick: true,
                                onAccept : function() {
                                    mixpanel.track('Delete document');
                                    new Submit({
                                                url: "/d/delete",
                                                method: "POST",
                                                documentids: "[" + _.map(docs, function(doc){return doc.field("id");}) + "]",
                                                ajaxsuccess : function() {
                                                    new FlashMessage({color : "green", content : localization.archive.documents.remove.successMessage});
                                                    archive.documents().recall();
                                                    confirmationPopup.clear();
                                                }
                                          }).sendAjax();
                                }
                              });
                             return true;
            }
        })
    ],
    options : [
                {name : localization.archive.documents.csv.action,
                 acceptEmpty : true,
                 onSelect: function(){
                     mixpanel.track('Download CSV');
                        var url =  archive.documents().model().schema.url() + "?";
                        var params =  archive.documents().model().schema.getSchemaUrlParams();
                        _.each(params,function(a,b){url+=(b+"="+a+"&")});
                        window.open(url + "format=csv");
                        return true;
                 }
                } ,
               {name : localization.archive.documents.zip.action,
                 acceptEmpty : true, // We handle in manually
                 onSelect: function(docs){
                     mixpanel.track('Download PDFs');
                        if (docs == undefined || docs.length == 0 ) {
                         new FlashMessage({color : "red", content : localization.archive.documents.zip.emptyMessage});
                         return true;
                        }
                        if (docs.length == 1) {
                          var url =  "/api/frontend/downloadmainfile/" + docs[0].field("id") + "/" + encodeURIComponent(docs[0].field("title")) + ".pdf";
                          window.open(url);
                          return true;
                        } else {
                          var url =  "/d/zip?";
                          url += "documentids=[" + _.map(docs,function(doc){return doc.field("id")}) + "]";
                          window.open(url);
                          return true;
                        }
                 }
                }
              ]
    }),
    bottomExtras : function() {
        // The new users will be presented with a welcoming message and
        // not see the table status footer in the document tab.
        if (archive.forNewUser()) { return; }

        var box = $("<div class='table-statuses'/>");
        var description = function(cssClass,text) {
            var icon = $("<div class='icon status float-left'></div>").addClass(cssClass);
            var text = $("<div class='float-left'/>").text(text);
            return $.merge(icon,text);
        };
        box.append(description("draft",localization.archive.documents.statusDescription.draft).addClass('first'));
        box.append(description("problem",localization.archive.documents.statusDescription.cancelled));
        box.append(description("sent",localization.archive.documents.statusDescription.sent));
        box.append(description("delivered",localization.archive.documents.statusDescription.delivered));
        box.append(description("read",localization.archive.documents.statusDescription.read));
        box.append(description("opened",localization.archive.documents.statusDescription.opened));
        box.append(description("signed",localization.archive.documents.statusDescription.signed));
        return box;
    }()
};};

});
