define([
  "legacy_code",
  "Underscore",
  "Backbone",
  "React",
  "common/backbone_mixin",
  "common/button",
  "signview/signsection/transition_mixin",
  "signview/tasks/task_mixin",
  "signview/signsection/signsignview",
  "signview/signsection/signrejectview",
  "signview/signsection/signsigningview",
  "signview/signsection/signprocessview",
  "signview/signsection/signpin",
  "signview/signsection/signinputpinview",
  "signview/signsection/signeidview",
  "signview/signsection/signeidprocessview",
  "signview/signsection/signfinishview"
], function (
  legacy_code,
  _,
  Backbone,
  React,
  BackboneMixin,
  Button,
  TransitionMixin,
  TaskMixin,
  SignSign,
  SignReject,
  SignSigning,
  SignProcess,
  SignPin,
  SignInputPin,
  SignEID,
  SignEIDProcess,
  SignFinish
) {
  return React.createClass({
    mixins: [TransitionMixin],

    propTypes: {
      model: React.PropTypes.instanceOf(Backbone.Model).isRequired,
      className: React.PropTypes.string,
      pixelWidth: React.PropTypes.number.isRequired,
      enableOverlay: React.PropTypes.func.isRequired,
      disableOverlay: React.PropTypes.func.isRequired
    },

    getInitialState: function () {
      var model = this.props.model;
      var initialStep = this.getInitialStep();

      return {
        initialStep: initialStep,
        step: initialStep,
        signedStatus: 0,
        eidThisDevice: true,
        askForPhone: model.askForPhone(),
        askForSSN: model.askForSSN()
      };
    },

    shouldTransition: function (prevProps, prevState) {
      return prevState.step !== this.state.step;
    },

    getInitialStep: function () {
      var document = this.props.model.document();
      var signatory = document.currentSignatory();
      var hasPinAuth = signatory.smsPinAuthenticationToSign();
      var hasEIDAuth = signatory.seBankIDAuthenticationToSign();
      var hasFinish = false;
      var model = this.props.model;
      var hasPlacements = document.allPlacements().filter(function (placement) {
        return placement.field().signatory().current() && placement.field().isSignature();
      }).length > 0;

      if (hasPinAuth) {
        return "pin";
      }

      if (hasEIDAuth) {
        return "eid";
      }

      if (!hasPlacements) {
        return "sign";
      }

      return "finish";
    },

    isValidStep: function (step) {
      var steps = ["sign", "signing", "finish", "process", "eid", "eid-process", "pin", "input-pin", "reject"];
      var valid = steps.indexOf(step) > -1;

      if (!valid) {
        throw new Error(step + " is not a valid step in SignSection");
      }
    },

    componentDidUpdate: function (prevProps, prevState) {
      var model = this.props.model;
      var hadOverlay = this.shouldHaveOverlay(prevState.step);
      var shouldHaveOverlay = this.shouldHaveOverlay();

      if (!hadOverlay && shouldHaveOverlay) {
        setTimeout(function () {
          model.arrow().disable();
        }, 10);
        this.props.enableOverlay();
      }

      if (hadOverlay && !shouldHaveOverlay) {
        setTimeout(function () {
          model.arrow().enable();
        }, 10);
        this.props.disableOverlay();
      }
    },

    isOnStep: function (step) {
      this.isValidStep(step);

      return this.state.step === step;
    },

    setStep: function (step) {
      this.isValidStep(step);

      this.setState({step: step});
    },

    setSignedStatus: function (status) {
      this.setState({signedStatus: status});
    },

    handleSetStep: function (step) {
      return function (e) {
        this.setStep(step);
      }.bind(this);
    },

    shouldHaveOverlay: function (step) {
      step = step || this.state.step;
      var noOverlayStep = ["sign", "pin", "eid", "finish"];
      return !(noOverlayStep.indexOf(step) > -1);
    },

    canSignDocument: function () {
      var model = this.props.model;
      var signatoryHasPlacedSignatures = model.document().currentSignatory().hasPlacedSignatures();

      return this.shouldHaveOverlay() || model.tasks().notCompletedTasks().length == 1 &&
        model.tasks().notCompletedTasks()[0].isSignTask();
    },

    handleReject: function (text) {
      var model = this.props.model;
      var doc = model.document();

      trackTimeout("Accept", {"Accept": "reject document"}, function () {
        doc.currentSignatory().reject(text).sendAjax(function () {
          var shouldRedirect = doc.currentSignatory().rejectredirect() != undefined &&
            doc.currentSignatory().rejectredirect() != "";
          ReloadManager.stopBlocking();
          if (shouldRedirect) {
            window.location = doc.currentSignatory().rejectredirect();
           } else {
            window.location.reload();
           }
        }, function (xhr) {
          if (xhr.status == 403) {
            ScreenBlockingDialog.open({header: localization.sessionTimedoutInSignview});
          } else {
            new FlashMessage({
              type: "error",
              content: localization.signviewSigningFailed,
              className: "flash-signview",
              withReload: true
            });
          }
        });
      });
    },

    handleSign: function (pin) {
      var self = this;
      var model = self.props.model;
      var document = self.props.model.document();
      var signatory = document.currentSignatory();

      if (!self.canSignDocument()) {
        return model.arrow().blink();
      }

      if (signatory.smsPinAuthenticationToSign() && !pin) {
        return new FlashMessage({
          type: "error",
          content: localization.docsignview.pinSigning.noPinProvided,
          className: "flash-signview"
        });
      }

      var errorCallback = function (xhr) {
        var data = {};
        try {
          data = JSON.parse(xhr.responseText);
        } catch (e) {}

        if (xhr.status == 400 && data.pinProblem) {
          self.setStep("input-pin");
          new FlashMessage({
            content: localization.docsignview.pinSigning.invalidPin,
            className: "flash-signview", type: "error"
          });
        } else {
          if (xhr.status == 403) {
            ReloadManager.stopBlocking();
            ScreenBlockingDialog.open({header: localization.sessionTimedoutInSignview});
          } else {
            ReloadManager.stopBlocking();
            new ReloadDueToErrorModal(xhr);
          }
        }
      };

      var pinParam = signatory.smsPinAuthenticationToSign() ? {pin: pin} : {};

      self.setStep("process");
      self.setSignedStatus(0);

      document.checksign(function () {
        new FlashMessagesCleaner();

        document.takeSigningScreenshot(function () {
          setTimeout(function () {
            self.setSignedStatus(1);

            trackTimeout("Accept", {"Accept": "sign document"});

            document.sign(errorCallback, function (newDocument, oldDocument) {
              setTimeout(function () {
                self.setSignedStatus(2);

                var redirect = oldDocument.currentSignatory().signsuccessredirect();

                setTimeout(function () {
                  if (redirect) {
                    window.location = redirect;
                  } else {
                    new Submit().send();
                  }
                }, 500);
              }, 2500);
            }, pinParam).send();
          }, 2500);
        });
      }, errorCallback, pinParam).send();
    },

    handlePin: function () {
      var self = this;
      var model = self.props.model;
      var doc = model.document();
      var sig = doc.currentSignatory();
      var phoneField = sig.mobileField();
      var askForPhone = model.askForPhone();
      var phone = phoneField.value();

      if (askForPhone) {
        return new FlashMessage({
          type: "error",
          content: localization.docsignview.pinSigning.invalidPhone,
          className: "flash-signview"
        });
      }

      mixpanel.track("Requesting SMS PIN", {
        documentid: doc.documentid(),
        signatoryid: sig.signatoryid(),
        phone: phone
      });

      doc.requestPin(function () {
        self.setStep("input-pin");
      }, function (xhr) {
        ReloadManager.stopBlocking();
        new ReloadDueToErrorModal(xhr);
      }).send();
    },

    handleSignEID: function (thisDevice) {
      var self = this;
      var model = self.props.model;

      if (!self.canSignDocument()) {
        return model.arrow().blink();
      }

      self.setState({eidThisDevice: thisDevice}, function () {
        self.setStep("eid-process");
      });
    },

    handleNext: function () {
      this.setStep("signing");
    },

    render: function () {
      var model = this.props.model;
      var doc = model.document();
      var sig = doc.currentSignatory();
      var queryPart = doc.mainfile().queryPart({pixelwidth: this.props.pixelWidth});
      var imgUrl = "/pages/" + doc.mainfile().fileid() + "/1" + queryPart;

      var phoneField = sig.mobileField();
      var ssnField = sig.personalnumberField();

      var sectionClass = React.addons.classSet({
        "section": true,
        "sign": true,
        "small-screen": BrowserInfo.isSmallScreen(),
        "above-overlay": this.shouldHaveOverlay()
      });

      return (
        <div className={sectionClass}>
          {/* if */ this.isOnStep("finish") &&
            <SignFinish
              model={this.props.model}
              name={sig.name()}
              canSign={this.canSignDocument()}
              onSign={this.handleSign}
              onReject={this.handleSetStep("reject")}
            />
          }
          {/* if */ this.isOnStep("sign") &&
            <SignSign
              model={this.props.model}
              canSign={this.canSignDocument()}
              onSign={this.handleNext}
              onReject={this.handleSetStep("reject")}
            />
          }
          {/* if */ this.isOnStep("signing") &&
            <SignSigning
              model={this.props.model}
              title={doc.title()}
              name={sig.name()}
              canSign={this.canSignDocument()}
              onBack={this.handleSetStep("sign")}
              onSign={this.handleSign}
            />
          }
          {/* if */ this.isOnStep("process") &&
            <SignProcess
              imgUrl={imgUrl}
              docTitle={doc.title()}
              status={this.state.signedStatus}
            />
          }
          {/* if */ this.isOnStep("eid") &&
            <SignEID
              model={this.props.model}
              field={ssnField}
              name={sig.name()}
              askForSSN={this.state.askForSSN}
              canSign={this.canSignDocument()}
              ssn={sig.personalnumber()}
              onReject={this.handleSetStep("reject")}
              onSign={this.handleSignEID}
            />
          }
          {/* if */ this.isOnStep("eid-process") &&
            <SignEIDProcess
              ssn={sig.personalnumber()}
              signatory={sig}
              thisDevice={this.state.eidThisDevice}
              onError={this.handleSetStep("eid")}
              onSuccess={this.handleSign}
            />
          }
          {/* if */ this.isOnStep("pin") &&
            <SignPin
              model={this.props.model}
              canSign={this.canSignDocument()}
              askForPhone={this.state.askForPhone}
              field={phoneField}
              onReject={this.handleSetStep("reject")}
              onNext={this.handlePin}
            />
          }
          {/* if */ this.isOnStep("input-pin") &&
            <SignInputPin
              title={doc.title()}
              name={sig.name()}
              onBack={this.handleSetStep("pin")}
              onSign={this.handleSign}
            />
          }
          {/* if */ this.isOnStep("reject") &&
            <SignReject
              onBack={this.handleSetStep(this.state.initialStep)}
              onReject={this.handleReject}
            />
          }
        </div>
      );
    }
  });
});
