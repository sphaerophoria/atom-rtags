const lazyreq = require('lazy-req').proxy(require);
const n_atom = lazyreq('atom');

function isUriOpen(uri) {
  for (let editor of atom.workspace.getTextEditors()) {
    if (editor.getPath() === uri) {
      return true;
    }
  }
  return false;
}

// This prevents us from attempting to open the same file more than once at a
// time, we can serialize the requests instead
var s_editorPromises = {};

function getTextEditor(filename) {
  if (isUriOpen(filename)) {
    return atom.workspace.open(filename, {activateItem: false})
  }

  if (s_editorPromises[filename]) {
      return s_editorPromises[filename];
  }

  s_editorPromises[filename] =  atom.workspace.open(filename, {activateItem: false})
  .then((editor) => {
    return editor.getBuffer().load()
      .then(() => editor);
  })
  .then((editor) => {
    s_editorPromises[filename] = null;
    return editor;
  });

  return s_editorPromises[filename];
}


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

module.exports.isUriOpen = isUriOpen;

module.exports.getTextEditor = getTextEditor;

module.exports.getTextBuffer = function(filename){
  return getTextEditor(filename)
  .then((editor) => editor.getBuffer());
}

module.exports.getCurrentWordBufferRange = function(editor) {
  let cursor = editor.getLastCursor();
  let wordRegExp = cursor.wordRegExp({includeNonWordCharacters: false});
  let wordRange = cursor.getCurrentWordBufferRange({wordRegex: wordRegExp});
  return wordRange;
}
