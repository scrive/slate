/** @jsx React.DOM */

/**
 * A upload button component in React. Internallly it uses standard buttons, and can take many UI propperties of buttons.
 *
 * Properties:
      text        : string , text on button,  default ""
      type:       : string, "action | optional | cancel | inactive | main",
      size        : string, tiny | small | big
      width       : integer, final width of button, if not set, button will adjust to text
      className   : additional css classes
      style       : style object (react format)
      onUploadComplete : function(input, title)

 *
 * Example usage:
 * var button = React.render(React.createElement(UploadButton,{
 *    text: "ABC"
 * }), div);
 *
 */

define(['React','common/button'], function(React,Button) {
  return React.createClass({
    propTypes: {
      text        : React.PropTypes.string,
      type        : React.PropTypes.string,
      fileType    : React.PropTypes.string,
      size        : React.PropTypes.string,
      width       : React.PropTypes.number,
      className   : React.PropTypes.string,
      style       : React.PropTypes.object
    },
    getDefaultProps : function() {
      return {
        "className" : "",
        "text"      : "",
        "color"     : "green",
        "size"      : "small",
        "style"     : {}
      };
    },
    // Don't depend on this calls, since it will not work well in IE8 and IE9 (access denied on file upload)
    openFileDialogue: function () {
      if (this.isMounted()) {
        var targetElm = $(this.getDOMNode()).find("input.file-input").last();
        targetElm.click();
        return true;
      }
    },
    fileName: function(fileinput) {
      var fullPath = fileinput[0].value;
      if (fullPath) {
        var startIndex = (fullPath.indexOf('\\') >= 0 ? fullPath.lastIndexOf('\\') : fullPath.lastIndexOf('/'));
        var filename = fullPath.substring(startIndex);
        if (filename.indexOf('\\') === 0 || filename.indexOf('/') === 0) {
          filename = filename.substring(1);
        }
        return filename;
      } else {
        return "";
      }
    },
    updateFileInputWidth: function(fileinput) {
      var self = this;
      if (self.props.width) {
        fileinput.css("width",self.props.width  + "px");
      } else if (self.isMounted()) {
        // To compute width component needs to be added to DOM.
        // isMounted doesn't guarantee that
        if (   $.contains(document.documentElement, self.refs.button.getDOMNode())
            && $(self.refs.button.getDOMNode()).outerWidth() > 0
        ) {
          fileinput.css("width",$(self.refs.button.getDOMNode()).outerWidth()  + "px");
        } else {
          setTimeout(function() {self.updateFileInputWidth(fileinput),100});
        }
      }
    },
    createFileInput : function() {
      var self = this;
      if (self.isMounted()) {
        var fileinput = $("<input class='file-input' type='file'/>");
        if (BrowserInfo.isIE8orLower()) {
          // make input invisible
          fileinput.css('filter', 'alpha(opacity=0)');
        }
        self.updateFileInputWidth(fileinput);

        if (self.props.fileType) {
          fileinput.attr("accept",self.props.fileType);
        }

        fileinput.attr("name",self.props.name);
        fileinput.change(function() {
          if (self.props.onUploadComplete != undefined) {
            // IE8 requires delay before inputs are available.
            setTimeout(function () {
              fileinput.detach();
              self.props.onUploadComplete(fileinput, self.fileName(fileinput));
              self.createFileInput();
            }, 100);
          } else {
            fileinput.remove();
            self.createFileInput();
          }
        });
        $(self.refs.button.getDOMNode()).append(fileinput);
      }
    },
    componentDidMount : function() {
      this.createFileInput();
    },
    render: function() {
      var self = this;
      return (
        <Button
          text={this.props.text}
          type={this.props.type}
          size={this.props.size}
          width={this.props.width}
          className={this.props.className + " upload-button" }
          style={this.props.style}
          onClick={function() {
            // do nothing. It should never happend since users should click on transparent file input
          }}
          ref="button"
        />
      );
    }
  });
});
