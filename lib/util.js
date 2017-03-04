const lazyreq = require('lazy-req').proxy(require);
const n_atom = lazyreq('atom');

module.exports.matched_scope = function (editor, acceptableScopes) {
    let rootScopeDescriptor = editor.getRootScopeDescriptor().scopes[0];

    if (!acceptableScopes) {
      acceptableScopes = ['source.cpp', 'source.c', 'source.h', 'source.hpp'];
    }

    if (acceptableScopes.indexOf(rootScopeDescriptor) > -1) {
      return true;
    }

    return false;
  }

module.exports.getTextBuffer = function(filename){
    for (let editor of atom.workspace.getTextEditors()) {
        if (editor.getPath() == filename) {
            return Promise.resolve(editor.getBuffer());
        }
    }

    let textBuffer = new n_atom.TextBuffer({filePath: filename});
    return new Promise((resolve) => {
      textBuffer.load()
      .then(() => {
        resolve(textBuffer);
      });
    });
  }
