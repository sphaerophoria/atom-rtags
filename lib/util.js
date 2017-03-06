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
    return atom.workspace.open(filename, {activateItem: false})
        .then((editor) => editor.getBuffer());
  }

module.exports.getCurrentWordBufferRange = function(editor) {
  let cursor = editor.getLastCursor();
  let wordRegExp = cursor.wordRegExp({includeNonWordCharacters: false});
  let wordRange = cursor.getCurrentWordBufferRange({wordRegex: wordRegExp});
  return wordRange;
}
