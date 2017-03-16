const util = require('./util.js');

module.exports.ModifiedFileTracker = class ModifiedFileTracker {
  constructor(rcExecutor, acceptableScopes) {
    this.rcExecutor = rcExecutor;
    this.subscriptions = {};
    this.subscriptions.observeTextEditors = atom.workspace.observeTextEditors(this.handleAddTextEditor.bind(this));
    this.enabled = false;
    this.currentlyModifiedFiles = {};
    this.acceptableScopes = acceptableScopes;
  }

  destroy() {
    disable();
  }

  setEnabled(enable) {
    if (enable == this.enabled) {
      return;
    }

    this.enabled = enable;
    if (this.enabled) {
      this.enable();
    }
    else {
      this.disable();
    }
  }

  enable() {
    for (let editor of atom.workspace.getTextEditors()) {
      this.handleAddTextEditor(editor);
    }
  }

  disable() {
    for (let key in this.subscriptions) {
      if (this.subscriptions[key]) {
        this.subscriptions[key].dispose();
        this.subscriptions[key] = undefined;
      }
    }

    for (let key in this.currentlyModifiedFiles) {
      if (this.currentlyModifiedFiles && this.currentlyModifiedFiles[key] === true) {
        this.rcExecutor.reindex_current_file(key);
      }
    }
  }

  setAcceptableScopes(scopes) {
    this.acceptableScopes = scopes;
  }

  handleAddTextEditor(editor) {
    if (!this.enabled || !util.matched_scope(editor)) {
      return;
    }

    let pathName = editor.getPath();

    if (this.subscriptions[pathName]) {
      this.subscriptions[pathName].dispose();
    }

    this.currentlyModifiedFiles[pathName] = editor.getBuffer().isModified();
    if (this.currentlyModifiedFiles[pathName] === true) {
      this.rcExecutor.index_unsaved_file(editor.getPath(), editor.getText());
    }

    this.subscriptions[pathName] = editor.onDidStopChanging(() => {
      if (editor.isModified() === true || this.currentlyModifiedFiles[pathName] === true) {
        this.rcExecutor.index_unsaved_file(editor.getPath(), editor.getText());
      }
      this.currentlyModifiedFiles[pathName] = editor.isModified();
    });

    editor.onDidDestroy(() => {
      if (this.currentlyModifiedFiles[pathName] === true) {
        this.rcExecutor.reindex_current_file(pathName);
      }
      if (this.subscriptions[pathName]) {
        this.subscriptions[pathName].dispose()
      }
      this.subscriptions[pathName] = undefined;
    });
  }
}
