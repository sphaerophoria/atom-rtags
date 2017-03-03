const { TextBuffer } = require('atom');

module.exports.RtagsLinter =
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

    registerLinter(indieRegistry) {
      return this.linter = indieRegistry.register({name: "Rtags Linter"});
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

    updateLinter(data) {
      // Parse data into linter strings
      // Linter only updates one file at a time... so every time we set messages we have to aggregate all our previous linted files
      let error;
      let res = [];

      if (!data || !data.checkstyle) {
        return;
      }

      for (let file of data.checkstyle.file) {
        this.current_linter_messages[file.$.name] = [];
        let editors = atom.workspace.getTextEditors()
        let fileBuf = null;
        for (let editor of editors) {
          if (editor.getPath() == file.$.name) {
            fileBuf = editor.getBuffer()
          }
        }
        if (fileBuf === null) {
          fileBuf = new TextBuffer({filePath: file.$.name});
          fileBuf.loadSync();
        }
        for (error of file.error) {
          if (error.$.severity !== "skipped" && error.$.severity !== "none") {
            let errorLine = parseInt(error.$.line, 10) - 1;
            let errorCol = parseInt(error.$.column, 10) - 1;
            let start_point = [errorLine, errorCol];
            let end_point = [errorLine];
            let filePath = file.$.name;

            let lineStr = fileBuf.lineForRow(errorLine);
            lineStr = lineStr.slice(errorCol);
            let re = /^[&*]*[a-zA-Z0-9_]*/;
            let underlineStr = re.exec(lineStr)[0];
            let endCol = underlineStr.length + errorCol;
            end_point.push(endCol);

            this.current_linter_messages[filePath].push({
              type: error.$.severity,
              text: error.$.message,
              filePath,
              severity: error.$.severity,
              range: [start_point, end_point]
            });
          }
        }
      }

      for (let k in this.current_linter_messages) {
        let v = this.current_linter_messages[k];
        for (error of v) {
          res.push(error);
        }
      }

      if (this.linter) {
        this.linter.setMessages(res);
      }
    }
  };
