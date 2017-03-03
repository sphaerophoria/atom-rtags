const lazyreq = require('lazy-req').proxy(require);
const n_atom = lazyreq('atom');

module.exports.matched_scope = function (editor) {
    let rootScopeDescriptor = editor.getRootScopeDescriptor().scopes;
    let acceptableScopes = ['source.cpp', 'source.c', 'source.h', 'source.hpp'];
    for (let i = 0; i < rootScopeDescriptor.length; i++) {
      for (let j = 0; j < acceptableScopes.length; j++) {
        if (rootScopeDescriptor[i] == acceptableScopes[j]) {
          return true;
        }
      }
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
