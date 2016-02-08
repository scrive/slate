/** @jsx React.DOM */

define(['legacy_code', 'React','common/select', 'common/infotextinput', 'common/daysinputwithcalendar'], function(_Legacy, React, Select, InfoTextInput, DaysInputWithCalendar) {

return React.createClass({
  languages : function() {
    var languages = [
        {name: localization.languages.en, value: "en"}
      , {name: localization.languages.sv, value: "sv"}
      , {name: localization.languages.de, value: "de"}
      , {name: localization.languages.fr, value: "fr"}
      , {name: localization.languages.it, value: "it"}
      , {name: localization.languages.es, value: "es"}
      , {name: localization.languages.pt, value: "pt"}
      , {name: localization.languages.nl, value: "nl"}
      , {name: localization.languages.da, value: "da"}
      , {name: localization.languages.no, value: "no"}
      , {name: localization.languages.el, value: "el"}
      , {name: localization.languages.fi, value: "fi"}
      , {name: localization.languages.is, value: "is"}
      , {name: localization.languages.et, value: "et", hidden: true}
      , {name: localization.languages.lv, value: "lv", hidden: true}
      , {name: localization.languages.lt, value: "lt", hidden: true}
    ];
    return _.sortBy(languages, function(l) {return l.name.toLowerCase();});
  },
  hideAllCalendars :  function() {
    if (this.refs.deadlineEditor) {
      this.refs.deadlineEditor.hideCalendar();
    }
    if (this.refs.reminderEditor) {
      this.refs.reminderEditor.hideCalendar();
    }
  },
  render: function() {
    var self = this;
    var doc = self.props.document;
    var lang = doc.lang().simpleCode();
    return (
      <div>
        <div className="design-view-action-process-left-column-document-name">
          <div className="design-view-action-process-left-column-document-name-label">
            {localization.designview.documentName}
          </div>
          <InfoTextInput
            className="design-view-action-process-left-column-document-name-field"
            value={doc.title()}
            infotext={localization.designview.documentName}
            onChange={function(v) {
                doc.setTitle(v);
            }}
            onBlur = {function () {
              if (doc.title() === "") {
                doc.setDefaultTitle();
              }
            }}
          />
        </div>
        <div className="design-view-action-process-left-column-language">
          <div className="design-view-action-process-left-column-language-label">
            {localization.designview.recipientsLanguage}
          </div>
          <Select
            className="design-view-action-process-left-column-language-field"
            name={_.findWhere(self.languages(), {value :lang}).name}
            options={_.filter(self.languages(), function(l) { return !l.hidden;})}
            width={158}
            onSelect= {function(v) {
              mixpanel.track('Select language', {'New Language': v});
              doc.lang().setLanguage(v);
            }}
          />
        </div>


        <div className="design-view-action-process-left-column-deadline">
          <div className="design-view-action-process-left-column-deadline-label">
            {localization.designview.signingDeadline}
          </div>
          <DaysInputWithCalendar
            ref="deadlineEditor"
            infotext="1"
            label={localization.designview.days}
            className="design-view-action-process-left-column-deadline-days-input-with-calendar"
            labelClassName="design-view-action-process-left-column-deadline-tag"
            inputClassName="design-view-action-process-left-column-deadline-field"
            days={doc.daystosign()}
            canBeEmpty={false}
            minDays={1}
            maxDays={365}
            onChange= {function(days) {
              doc.setDaystosign(days);
            }}
          />
        </div>

        <div className="design-view-action-process-left-column-remindline">
          <div className="design-view-action-process-left-column-remindline-label">
            {localization.autoreminders.sendReminderIn}
          </div>
          <DaysInputWithCalendar
            ref="reminderEditor"
            infotext="-"
            label={localization.autoreminders.days}
            className="design-view-action-process-left-column-remindline-days-input-with-calendar"
            labelClassName="design-view-action-process-left-column-remindline-tag"
            inputClassName="design-view-action-process-left-column-remindline-field"
            days={doc.daystoremind()}
            canBeEmpty={true}
            minDays={1}
            maxDays={doc.daystosign()}
            onChange= {function(days) {
              doc.setDaystoremind(days);
            }}
          />
        </div>
      </div>
    );
  }
});


});


