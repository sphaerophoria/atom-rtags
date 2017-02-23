
module.exports = {
  matched_scope(editor) {
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
}
