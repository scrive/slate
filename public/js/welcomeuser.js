/* Thie file defines the welcome message that the new users will be greeted with.
 * Currently it only has content for the Post Sign View signups.
 */

(function(window){

window.WelcomeUser = {

    /**
     * Resets the "from post sign view" indicator
     */
    noLongerFromPostSignView: function() {
        SessionStorage.set('postsignview', 'signup', false);
    },

    /**
     * Return true if the user got here from post sign view
     */
    isFromPostSignView: function() {
        return SessionStorage.get('postsignview', 'signup') === 'true';
    },


    /**
     * Handles people who may be here from the post sign view.
     */
    fromPostSignViewWelcome: function() {
        if (!this.isFromPostSignView())
            return;

        this.noLongerFromPostSignView(); // only welcome them once

        var welcomeSubtitleExperiment = new Experiment({
            namespace: 'welcome',
            name: 'subtitle',
            domain: ['1', '2', '3', '4'] // Different possible subtitles
        });

        return this.fromPostSignViewWelcomeContent(welcomeSubtitleExperiment.value());   
    },


    /**
     * Returns an element welcoming the user, telling them that their document
     * has been saved and that they can try sending a sample document.
     *
     * @param {object} option Which of the possible subtitles that will be rendered. [1,3].
     */
    fromPostSignViewWelcomeContent: function(option) {
	var outerContainer = $('<div class="new-post-sign-view-user"></div>');
        var container = $('<div class="inner-container"/>');    
	outerContainer.append(container);

	if (option == 4) {
	    $('.session-create').remove();
	    $('#page-archive').css('color', '#999');
	    setTimeout(function() {		
		var document_overlay = $('<div class="mark-document-overlay" />');
		$('table').prepend(document_overlay);
		var documentDescription = $('<div class="document-description" />');
	
		documentDescription.append($('<img src="/img/point-at-arrow.png"/>'));
		documentDescription.append($('<h3>' + localization.welcomenewuser.subtitle4.explainDocument + '</h3>'));

		$('.list-container').append(documentDescription);
	    }, 1000);
	    
	} else {
            container.append($('<img src="/img/arrow-grey.png" class="grey-arrow" />'));
            container.append($('<h2></h2>').text(localization.welcomenewuser.title));
	}

        /* We want to highlight the first row of the table body. */
        $('body').addClass('new-post-sign-view-user-first-row-highlighted');

        // For small devices and pad devices, don't give them an option to try
        // sending a sample document.
        if (BrowserInfo.isPadDevice() || BrowserInfo.isSmallScreen()) {
            return container;
        }

        mixpanel.register({'Welcome new user test': option});
        mixpanel.track('Welcome modal shown');
        
	var sendDocumentButtonText = localization.welcomenewuser.button;

        // I think this increases the chance of ending up at else if option == undefined (in some error cases). Rewrite to switch?
        if (option == 1) {
            subtitle = $('<h4 class="subtitle"></h4>').text(localization.welcomenewuser.subtitle1);
        } else if (option == 2) {
            subtitle = $('<h4 class="subtitle"></h4>').text(localization.welcomenewuser.subtitle2);
        } else if (option == 3) {
            subtitle = $('<div class="subtitle"></div>');
            subtitle.append($('<h5></h5>').text(localization.welcomenewuser.subtitle3.injustafewminutes));
            subtitle.append($('<h5 class="great-thing"></h5>').text(localization.welcomenewuser.subtitle3.reviewed));
            subtitle.append($('<h5 class="great-thing"></h5>').text(localization.welcomenewuser.subtitle3.returned));
            subtitle.append($('<h5 class="great-thing"></h5>').text(localization.welcomenewuser.subtitle3.saved));
            subtitle.append($('<h5></h5>').text(localization.welcomenewuser.subtitle3.isntthishowsimple));
        } else if (option == 4) {
	    outerContainer.hide();
	    setTimeout(function() {
		outerContainer.show();
		$('html, body').animate({
		    scrollTop:  outerContainer.offset().top - 70
		}, 2000);
	    }, 4000);
	    
	    container.addClass('experiment4');
	    sendDocumentButtonText = localization.welcomenewuser.subtitle4.buttonText;
	    subtitle = $('<div class="subtitle"></div>');
            subtitle.append($('<h5 class="explanation"></h5>').text(localization.welcomenewuser.subtitle3.injustafewminutes));
            subtitle.append($('<h5 class="great-thing"></h5>').text(localization.welcomenewuser.subtitle3.reviewed));
            subtitle.append($('<h5 class="great-thing"></h5>').text(localization.welcomenewuser.subtitle3.returned));
            subtitle.append($('<h5 class="great-thing"></h5>').text(localization.welcomenewuser.subtitle3.saved));
            subtitle.append($('<h5 class="explanation" class="second-h5"></h5>').text(localization.welcomenewuser.subtitle4.isntthishowsimple));
	} 
            
        container.append(subtitle);


        var fakeUploadButton = new Button({
            color: 'green',
            shape: 'rounded',
            size: 'big',
            text: sendDocumentButtonText,
            // make it look similar to the upload button so that the user gets familiar with the button style/functioning
            cssClass: 'design-view-document-buttons-upload-button', 
            onClick: function() {
                var sampleDocumentExperiment = new Experiment({
                  name: 'sampledocument',
                  namespace: 'welcome', 
                  domain: ['scrivegraphics','loremipsumcontract'] 
                });

                mixpanel.register({
                    'Sample document test group': sampleDocumentExperiment.value(),
                    'Welcome modal accepted': true
                });
                mixpanel.people.set({
                    'Welcome modal accepted': true
                });

                mixpanel.track("Welcome modal accept");

                LoadingDialog.open();

                SessionStorage.set('welcome', 'accepted', true);

                DocumentUploader.uploadByURL(function(documentData) {
                    window.location.pathname = '/d/' + documentData.id;
                },
                function() {}, // currently no error handling.
                '/pdf/sample_document_' + sampleDocumentExperiment.value() + '_' + localization.code + '.base64.pdf',
                localization.welcomenewuser.documentTitle);
            }
        });

        container.append(fakeUploadButton.el());

        return outerContainer;
    }
};

})(window);
