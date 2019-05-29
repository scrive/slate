var Backbone = require("backbone");


var Company = exports.Company = Backbone.Model.extend({
  defaults : {
      companyid        : "",
      companyname      : "",
      companynumber    : "",
      address    : "",
      zip       : "",
      city      : "",
      country    : "",
      idledoctimeoutpreparation : null,
      idledoctimeoutclosed : null,
      idledoctimeoutcanceled : null,
      idledoctimeouttimedout : null,
      idledoctimeoutrejected : null,
      idledoctimeouterror : null,
      immediatetrash: false,
      cgidisplayname : "",
      cgiserviceid : "",
      ipaddressmasklist : "",
      parentid : null,
      parentgrouppath : [],
      smsprovider : "",
      ready : false,
      padappmode : "list_view",
      padearchiveenabled : true,
      sendtimeoutnotification: false,
      companyaddressisinherited: false,
      companysettingsisinherited: false,
      companyinheritedaddress: null,
      companyinheritedsettings: null
  },
  initialize : function(args) {
    if (args.forAdmin && args.companyid != undefined)
        this.url = "/adminonly/companyadmin/details/"+ args.companyid;
  },
  companyid : function() {
     return this.get("companyid");
  },
  companyname : function() {
     return this.get("companyname");
  },
  companynumber : function() {
     return this.get("companynumber");
  },
  address : function() {
     return this.get("address");
  },
  zip : function() {
     return this.get("zip");
  },
  city : function() {
     return this.get("city");
  },
  country : function() {
     return this.get("country");
  },
  ipaddressmasklist: function() {
     return this.get("ipaddressmasklist");
  },
  parentid: function() {
     return this.get("parentid");
  },
  parentgrouppath: function() {
     return this.get("parentgrouppath");
  },
  cgidisplayname : function() {
     return this.get("cgidisplayname");
  },
  cgiserviceid : function() {
     return this.get("cgiserviceid");
  },

  idledoctimeoutpreparation: function() {
    return this.get("idledoctimeoutpreparation");
  },

  idledoctimeoutclosed: function() {
    return this.get("idledoctimeoutclosed");
  },

  idledoctimeoutcanceled: function() {
    return this.get("idledoctimeoutcanceled");
  },

  idledoctimeouttimedout: function() {
    return this.get("idledoctimeouttimedout");
  },

  idledoctimeoutrejected: function() {
    return this.get("idledoctimeoutrejected");
  },

  idledoctimeouterror: function() {
    return this.get("idledoctimeouterror");
  },

  immediatetrash: function() {
    return this.get("immediatetrash");
  },

  minidledoctimeout : function() {
     return 1; // sync with backend
  },
  maxidledoctimeout : function() {
     return 365; // sync with backend
  },
  smsprovider: function() {
    return this.get("smsprovider");
  },
  padappmode: function(){
     return this.get("padappmode");
  },
  padearchiveenabled: function(){
     return this.get("padearchiveenabled");
  },
  sendtimeoutnotification: function() {
     return this.get("sendtimeoutnotification");
  },
  companyaddressisinherited: function(){
     return this.get("companyaddressisinherited");
  },
  companysettingsisinherited: function(){
     return this.get("companysettingsisinherited");
  },
  companyinheritedaddress: function(){
     return this.get("companyinheritedaddress");
  },
  companyinheritedsettings: function(){
     return this.get("companyinheritedsettings");
  },
  ready : function() {
     return this.get("ready");
  },
  parse: function(args) {
     return {
      companyid        : args.companyid,
      companyname      : args.companyname,
      companynumber    : args.companynumber,
      address    : args.address,
      zip       : args.zip,
      city      : args.city,
      country    : args.country,
      ipaddressmasklist : args.ipaddressmasklist,
      parentid : args.parentid,
      parentgrouppath : args.parentgrouppath,
      cgidisplayname : args.cgidisplayname,
      cgiserviceid : args.cgiserviceid,
      idledoctimeoutpreparation  : args.idledoctimeoutpreparation,
      idledoctimeoutclosed : args.idledoctimeoutclosed,
      idledoctimeoutcanceled : args.idledoctimeoutcanceled,
      idledoctimeouttimedout : args.idledoctimeouttimedout,
      idledoctimeoutrejected : args.idledoctimeoutrejected,
      idledoctimeouterror : args.idledoctimeouterror,
      immediatetrash: args.immediatetrash,
      smsprovider : args.smsprovider,
      padappmode : args.padappmode,
      padearchiveenabled : args.padearchiveenabled,
      sendtimeoutnotification: args.sendtimeoutnotification,
      // do not set inherited, when the inherited values are not provided
      companyaddressisinherited: args.companyinheritedaddress && args.companyaddressisinherited,
      companysettingsisinherited: args.companyinheritedsettings && args.companysettingsisinherited,
      companyinheritedaddress: args.companyinheritedaddress,
      companyinheritedsettings: args.companyinheritedsettings,
      ready : true
    };
  }
});
