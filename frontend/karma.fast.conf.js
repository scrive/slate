var path = require("path");
var webpack = require("webpack");
var generateVersionId = require("./custom_grunt_tasks/utils/version_id_generator");

function bowerResolver() {
  return new webpack.ResolverPlugin(
    new webpack.ResolverPlugin.DirectoryDescriptionFilePlugin("./bower.json", ["main"])
  );
}

module.exports = function(config) {
  config.set({
    basePath: "./app/",

    frameworks: ["mocha", "sinon-chai"],

    files: [
      "./localization/*.en.js",
      "./compiled/vendor-" + generateVersionId() + ".js",
      "./test/env.js",
      "./test/entry.js"
    ],

    preprocessors: {
      "./test/entry.js": ["webpack"]
    },

    reporters: ["progress"],

    port: 9876,

    colors: true,

    logLevel: config.LOG_INFO,

    autoWatch: false,

    browsers: ["PhantomJS"],

    singleRun: false,

    webpack: {
      context: "./app",

      module: {
        preLoaders: [
          {
            test: /.jsx$/,
            loader: "babel",
            query: {
              presets: ["react", "es2015"]
            }
          }
        ]
      },

      externals: {
        "jquery": "jQuery",
        "backbone": "Backbone",
        "underscore": "_",
        "react": "React",
        "react/addons": "React",
        "tinycolor": "tinycolor",
        "html2canvas": "html2canvas",
        "moment": "moment",
        "sinon": "sinon",
        "base64": "Base64"
      },

      resolve: {
        extensions: ["", "min.js", ".js", ".jsx"],
        root: [path.join(__dirname, "./app/bower_components")],
      },

      plugins: [bowerResolver()]
    }
  });
};
