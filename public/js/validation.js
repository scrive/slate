
$(function(){
window.Validation = Backbone.Model.extend({
    defaults : {
        validates : function() {return true;},
        callback : function() {},
        message : "Validation has failed",
        next: undefined
    },
    concat: function(nextValidation) {
        if (this.get("next") == undefined)
            this.set({"next": nextValidation});
        else
            this.get("next").concat(nextValidation);
        return this;
    },
    validateData: function(text, elem) {
            if (!this.get("validates")(text)) {
               this.fail(text, elem);
               return false;       
            }
            else if (this.get("next") != undefined)
               return this.get("next").validateData(text,elem); 
            else
               return true; 
    },
    fail : function(text, elem) {
        if (this.get("callback") != undefined)
            return this.get("callback")(text, elem, this);
    },
    message: function() {
        return this.get("message");
    },
    setCallback : function(callback) {
        this.set({callback : callback});
        if (this.get('next') != undefined) this.get('next').setCallback(callback);
        return this;
    }
});

//Here we need to define the initialize function because in javascript objects
//are shared by the reference. If we don't do this there will be always the
//same callbacks at all instances.
window.NotEmptyValidation = Validation.extend({
    defaults: {
           validates: function(t) {
                    if (/^\s*$/.test(t))
                        return false;
                    
                    return true;
            },
           message: "The value cannot be empty!"
        }
});

window.EmailValidation = Validation.extend({
     defaults: {
            validates: function(t) {
                if (/^[\w._%+-]+@[\w.-]+[.][a-z]{2,4}$/i.test(t))
                    return true;
                return false;
            },
            message: "Wrong email format!"
    }
});

window.PasswordValidation = Validation.extend({
    defaults: {
            validates: function(t) {
                if (t.length < 8 || t.length > 250)
                    return false;
                
                if (!/([a-z]+[0-9]+)|([0-9]+[a-z]+)/.test(t))
                    return false;
                
                return true;
            },
            message: "Password must contain one digit and one letter and must be 8 characters long at least!"
    }
});

window.NameValidation = Validation.extend({
    defaults: {
            validates: function(t) {
                var t = $.trim(t);

                if (t.length == 0 || t.length > 100)
                    return false;

                if (/[^a-z-' ]/i.test(t))
                    return false;

                return true;
            },
            message: "Name may contain only alphabetic characters, apostrophe, hyphen or space!"
    }
});

jQuery.fn.validate = function(validationObject){
    var validationObject = validationObject || (new NotEmptyValidation);
    var validates = true;

    this.each(function(){
            if (!validationObject.validateData($(this).val(), $(this))) {
                validates = false;
                return false;
            }
        });

    return validates;
};

String.prototype.validate = function(validationObject) {
    var validationObject = validationObject || (new NotEmptyValidation);
    return validationObject.validateData(this);
};

});