

function getUniqueId()
{
    var rnd = Math.round(Math.random() * 1000000000);
    while($("#" + rnd).length  >0) {
        rnd = Math.round(Math.random() * 1000000000);
    }
    return rnd;
}

function enableInfoText(where)
{
    if( where==null ) {
        where = $(document);
    }
    var selector = ':input[infotext]';
    var inputs = where.find(selector);
    
    inputs.focus(function() { 
            if( $(this).hasClass("grayed")) {
                $(this).val("");
                $(this).removeClass("grayed");
            }
            });
    inputs.blur(function() {
            if( $(this).val()=="" || $(this).val()==$(this).attr("infotext") ) {
                $(this).addClass("grayed");
                $(this).val($(this).attr("infotext"));
            }
        });
    inputs.blur();
    $("form").submit(function () {
            var elems = $(this).find(selector + ".grayed");
            elems.val("");
            return true;
        });
}

function disableInfoText(where)
{
    if( where==null ) {
        where = $(document);
    }
    inputs = where.filter('input[type="text"][infotext!=""]');
    inputs.focus();
}

function signatoryadd()
{
    var signatorylist = $( "#signatorylist" );
    var sig = $("#signatory_template").clone();
	var text = sig.html();
	var emailfield = sig.find("input[type='email']");
	emailfield.attr("id","othersignatoryemail");
    signatorylist.append(sig);
    enableInfoText(sig);
    sig.hide();
    sig.slideDown("slow");
    return false;
}

function signatoryremove(node)
{
  var sig = $(node).parent();
  var cls = sig.data("draggableBoxClass");
  var db = $("." + cls);
  sig.slideUp('slow',function() { $(this).remove(); });
  db.fadeOut('slow',function() { $(this).remove(); });
  return false;
}



function swedishString(names)
{ 
    if( names.length == 0) 
        return "";
    if( names.length == 1) 
        return "<strong>" + names[0] + "</strong>";
  
    var name0 = names.shift();  
    if( names.length == 1)
        return "<strong>" + name0 + "</strong> och " + swedishString(names);

    return "<strong>" + name0 + "</strong>, " + swedishString(names);
}

$(document).ready( function () {

        var focused;
        // two alternative ways to track clicks off of a .check
        //$("*").not(".check").click(function(){if(this == document.activeElement) { focused = null; }});
        // this way is cleaner since it only installs a handler on the toplevel document instead of nearly
        // every element
        $(document).click(function(event){ 
                if($(event.target).parents("#selectable").size() === 0){ 
                    focused = null; 
                }
            });

        $("#selectable tr").mousedown(function(event){
                if(focused && event.shiftKey && $(event.target).filter(".check").size() === 0){
                    var checks = $(".check");
                    var startIndex = focused?checks.index(focused):null;
                    var endIndex = checks.index($(this).find(".check"));
                    
                    var s = Math.min(startIndex, endIndex);
                    var e = Math.max(startIndex, endIndex);
 
                    checks.slice(s, e+1).attr("checked", true);

                    checks.not(":checked").parents("tr").removeClass("ui-selected");
                    checks.filter(":checked").parents("tr").addClass("ui-selected");

                    focused = $(checks.get(endIndex));
                    checks.get(endIndex).focus();

                    // cancel all further click processing
                    // we are overriding the Selectable behavior for shift-clicks
                    return false;
                }                     
            });

        // the jQuery Selectable feature 
        $("#selectable" ).selectable({
                // links and input fields do not have click overridden
                cancel: 'a,input',
                    
                unselected: function(event, ui) {
                    var check = $(ui.unselected).find(".check");
                    check.attr("checked", false);
                },

                selected: function(event, ui) {
                    var check = $(ui.selected).find(".check");
                    check.attr("checked", true);
                    check.focus();
                    focused = check;
                }});

        $(".check:checked").parents("tr").addClass("ui-selected");
        $(".ui-selected").find(".check").attr("checked", true);
        
        $(".check").click(function(event) {
                    
                if(event.shiftKey && focused && focused.filter(".check").size() > 0 && focused.attr("checked")){
                    var checks = $(".check");
                    var startIndex = checks.index(focused);
                    var endIndex = checks.index(this);
                    
                    var s = Math.min(startIndex, endIndex);
                    var e = Math.max(startIndex, endIndex);
 
                    var checksslice = checks.slice(s, e+1);
                    checksslice.attr("checked", true);
                    checksslice.parents("tr").addClass("ui-selected");
                }
                else {
                    if( $(this).attr("checked")) {
                        $(this).parents("tr").addClass("ui-selected");
                    }
                    else {
                        $(this).parents("tr").removeClass("ui-selected");
                    }
                }

                focused = $(this);
            });

        $('#all').click(function() {
            var checks = $('input:checkbox[name="doccheck"]');
            var acc = true;
            checks.each(function(i, val) { acc = acc && $(val).attr("checked");});
            checks.attr("checked", !acc);
            
            if( !acc ) {    
                checks.parents("tr").addClass("ui-selected");
            } else {
                checks.parents("tr").removeClass("ui-selected");
            }
        }); 

    $('.flashmsgbox').delay(5000).fadeOut();
    $('.flashmsgbox').click( function() { 
         $(this).fadeOut() 
    });
    /*
    $('#all').click(function() {
    });
    */
    enableInfoText();
    if(typeof(window.documentid)!= "undefined" ) {
        $.ajax({ url: "/pagesofdoc/" + documentid,
            success: function(data) {
                $('#documentBox').html(data);
            },
            error: function () {
                var that = this;
                $(document).delay(1000).queue(function() {
                        $(this).dequeue();
                        $.ajax(that);
                    });
            }
        });
    }
    
 
    $("#signinvite").overlay({  
    onBeforeLoad: function () { 
           if (!emailFieldsValidation($("input[type='email']"))) return false;
           if (!authorFieldsValidation()) return false;
           var mrxs = $("form input[name='signatoryname']");
           var tot = "";
           var allparties = new Array();
             mrxs.each(function(index) { 
                     allparties.push($(this).val());
                 });
           tot = swedishString(allparties);
           $(".Xinvited").html(tot);
          } })
        
    $(".submiter").click(function(){
                               $(this.form).submit();
    })
 
   $(".editer").each(function() {
                             $(this).click(function(){
                                  prepareForEdit($(this.form));
                                  $(this).hide();
                                  return false;
                                  })
                         })   
                         
    $("#editinvitetextlink").overlay({        
    onBeforeLoad: function () { 
            var newtxt = $("#invitetext").val()
            $("#edit-invite-text-dialog textarea").val(newtxt );          
    }
    })   
        
    $("#editing-invite-text-finished").click(function() {
                         var newtxt = $("#edit-invite-text-dialog textarea").val();
                         $("#invitetext").val( newtxt );
                     })
    $(".redirectsubmitform").submit(function(){
                          var newform = $($(this).attr("rel"))
                          var inputs = $("input",$(this))
                          $('textarea:tinymce',$(this)).each(
                             function(){
                             inputs = inputs.add($("<input name='"+$(this).attr('name')+"' value='"+$(this).html()+"'>"))
                             })
                          inputs.css("display","none");
                          newform.append(inputs); 
                          newform.submit();
                          return false; 
                          })                      
    $("#sign").overlay({
        onBeforeLoad: function () { if (!sigFieldsValidation()) return false;}
    })
    
    $("#cancel").overlay({
    })    
	
	$("input[type='email']").focus(function(){
		applyRedBorder($(this));
		return false;
            });
	
	$("#loginbtn").click(function(){
		if(emailFieldsValidation($("input[type='email']",this.form))){
			$(this.form).submit();
		}						  
		return false;
	});
	
	$("#createnewaccount").click(function(){
		if(emailFieldsValidation($("input[type='email']"))){
			$(this.form).submit();
		}
		return false;
							
	
	});
	
    $(window).resize();
    
    //var rpxJsHost = (("https:" == document.location.protocol) ? "https://" : "http://static.");
    //document.write(unescape("%3Cscript src='" + rpxJsHost +
    //           "rpxnow.com/js/lib/rpx.js' type='text/javascript'%3E%3C/script%3E"));
    //    RPXNOW.overlay = true;
    //    RPXNOW.language_preference = 'sv';
});

$("#othersignatoryemail").live('focus', function(e){	
		    applyRedBorder($(this));
});

	
function isValidEmailAddress(emailAddress) {
	var pattern = /^([A-Za-z0-9_\-\.+])+\@([A-Za-z0-9_\-\.])+\.([A-Za-z]{2,4})$/;
	return pattern.test(emailAddress);
}

function applyRedBorder(field){
	field.keyup(function(){
		var emailVal = $(this).val();
		$(this).removeAttr("style");		
		if(emailVal != 0)
		{
			if(isValidEmailAddress(emailVal))
			{
				$(this).removeAttr("style");
			}
			else{
			  $(this).css("border","1px solid red");
			} 
		}
		else{
			 $(this).removeAttr("style");
		} 
				
	});
}
	   

  function emailFieldsValidation(fields){
      var invalidEmailErrMsg = "Felaktig e-post \"email\". Försök igen.";
      var emptyEmailErrMsg = "Du måste ange e-post till motpart.";
	 var errorMsg="";
	 var address="";
	 var showError=false;
	 var isValidEmail=false;

    
    fields.each(function() {
		if(!isExceptionalField($(this))){
		address = $(this).val();
		 
			if(address.length == 0){
                            errorMsg = emptyEmailErrMsg;
                            showError = true;
			}
			if(isValidEmailAddress(address) == false && showError==false) { 
				errorMsg=invalidEmailErrMsg.replace("email",address);
				showError=true;
			}
			 
			if(showError){
				var $dialog = $('<div></div>')
					.html(errorMsg)
					.dialog({
						autoOpen: false,
						title: 'Felaktig e-post',
						modal: true
					});
				$dialog.dialog('open');
				return false;
			}	
		}
	});
	isValidEmail=(showError)?false:true;
	return isValidEmail;
}

function authorFieldsValidation(){

    var remainingAuthFields = false;
	 
    $(".dragfield").each(function(){
	    var field = $(this);
	    var s = getIcon(field);
	    if(s == 'athr') {
		remainingAuthFields = true;
	    }
	});
    var emptyMsg = "Please fill out all of the required fields.";
    if(remainingAuthFields){
	var $dialog = $('<div></div>')
	    .html(emptyMsg)
	    .dialog({
		    autoOpen: false,
		    title: 'Required fields',
		    modal: true
		});
	$dialog.dialog('open');
	return false;
    }	
    return !remainingAuthFields;
}

function sigFieldsValidation(){

    var remainingSigFields = false;
	 
    $(".dragfield").each(function(){
	    var field = $(this);
	    if(getValue(field).length === 0) {
		remainingSigFields = true;
	    }
	});
    var emptyMsg = "Please fill out all of the fields.";
    if(remainingSigFields){
	var $dialog = $('<div></div>')
	    .html(emptyMsg)
	    .dialog({
		    autoOpen: false,
		    title: 'Required fields',
		    modal: true
		});
	$dialog.dialog('open');
	return false;
    }	
    return !remainingSigFields;
}

function isExceptionalField(field){

	var parentid = field.closest("div").attr("id");
	var fieldid = field.attr("id");
	var fieldname=field.attr("name");

	if(fieldname=="signatoryemail" && parentid == "signatory_template" && fieldid != "othersignatoryemail")
		return true

	return false
}


$(function(){
    $(".prepareToSendReminderMail").each(function(){
        var form = $($(this).attr("rel"));
        $(this).overlay({
                     resizable: false,
                     onClose: function(e){ return false;
                    }
                 })
    })                   
})

function prepareForEdit(form){
    $(".editable",form).each( function(){
        var textarea = $("<textarea style='width:95%;height:120px'  name='"+$(this).attr('name')+"'> "+ $(this).html()+ "</textarea>")
        $(this).replaceWith(textarea);
        var editor = textarea.tinymce({
                          script_url : '/tiny_mce/tiny_mce.js',
                          theme : "advanced",
                          theme_advanced_toolbar_location : "top",     
                          theme_advanced_buttons1 : "bold,italic,underline,separator,strikethrough,bullist,numlist,separator,undo,redo,separator,cut,copy,paste",
                          theme_advanced_buttons2 : "",
                          
                         })
  })    
}