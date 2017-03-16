const { Point, Range, TextBuffer } = require('atom');
const util = require('./util.js');

function healLinterSeverity(input) {
  input = input.toLowerCase();
  if (input != "error" && input != "warning") {
    return "info";
  }

  return input;
}

class RtagsLinter {
  constructor(rcExecutor) {
    this.rcExecutor = rcExecutor;
    this.enableCodeLinting = atom.config.get('atom-rtags-plus.codeLinting');
    this.linter = null;
    this.diagnostics = null;
    this.current_linter_messages = {};
    this.rcExecutor.on('rdmStarted', this.updateLinterStatus.bind(this, atom.config.get('atom-rtags-plus.codeLinting')));
    if (this.rcExecutor.rdmStarted) {
      this.updateLinterStatus(atom.config.get('atom-rtags-plus.codeLinting'));
    }
    atom.config.observe('atom-rtags-plus.codeLinting', enable => this.updateLinterStatus(enable));
  }

  destroy() {
    return this.stopLinting();
  }

  registerLinter(registerIndie) {
    return this.linter = registerIndie({name: "Rtags Linter"});
  }

  updateLinterStatus(enable) {
    if (enable && this.rcExecutor.rdmStarted) {
      return this.startLinting();
    } else {
      return this.stopLinting();
    }
  }

  startLinting() {
    if (!this.diagnostics || (this.diagnostics.exitCode !== null)) {
      return this.diagnostics = this.rcExecutor.rc_diagnostics_start(this.updateLinter.bind(this));
    }
  }

  stopLinting() {
    if (this.diagnostics) {
        this.diagnostics.kill();
    }
    this.current_linter_messages = {};
    this.diagnostics = null;
    if (this.linter) {
      this.linter.setMessages([]);
    }
  }

  setErrorsForFile(filePath, errors) {
    this.current_linter_messages[filePath] = [];
    for (let error of errors) {
      if (error.$.severity === "skipped" || error.$.severity === "none" ) {
        continue;
      }

      let startPoint = new Point(parseInt(error.$.line) - 1, parseInt(error.$.column) - 1);
      let endPoint = new Point(startPoint.row, 0);

      // Length parameter does not show on most items, we need to find the end ourself
      util.getTextBuffer(filePath)
      .then((textBuf) => {
        let lineStr = textBuf.lineForRow(startPoint.row).slice(startPoint.column);
        let re = /^[&*]*[a-zA-Z0-9_]*/;
        let underlineStr = re.exec(lineStr)[0];
        endPoint.column = underlineStr.length + startPoint.column;
      });

      let range = new Range(startPoint, endPoint);

      this.current_linter_messages[filePath].push({
        severity: healLinterSeverity(error.$.severity),
        location: {
          file: filePath,
          position: range
        },
        excerpt: error.$.message,
      });
    }
  }

  updateLinter(data) {
    // Parse data into linter strings
    // Linter only updates one file at a time... so every time we set messages we have to aggregate all our previous linted files
    let error;
    let res = [];

    if (!data || !data.checkstyle) {
      return;
    }
    for (let file of data.checkstyle.file) {
      this.setErrorsForFile(file.$.name, file.error);
    }

    if (!this.linter) {
      return;
    }

    let ret = [];
    for (let k in this.current_linter_messages) {
      ret = ret.concat(this.current_linter_messages[k]);
    }
    this.linter.setAllMessages(ret);
  }
};

module.exports.RtagsLinter = RtagsLinter
