lazyreq = require('lazy-req').proxy(require);
n_atom = lazyreq('atom');
n_util = lazyreq('./util.js');

function generateEmptySuggestion() {
  return { range: new n_atom.Range, callback() {} };
}

module.exports.RtagsHyperclicker = class RtagsHyperclicker {
  constructor() {
    this.rcExecutor = null;
    this.tokens = {};
    this.currentFile = null;
    this.currentPromise = new Promise((resolve) => {resolve()});
    this.nextSuggestionFunc = null;
  }

  destroy() {
    this.rcExecutor = null;
  }

  setRcExecutor(rcExecutor) {
      this.rcExecutor = rcExecutor;
  }

  setActionExecutor(actionExecutor) {
    this.actionExecutor = actionExecutor;
  }

  getProvider() {
    return {
      providerName: 'rtags-hyperclicker',
      getSuggestionForWord: this.getSuggestionForWord.bind(this)
    };
  }

  /*
   * Strategy here is a little strange. The intent is to avoid spamming rc when
   * we don't have to. If we are moving the mouse really fast, then it is likely
   * that we will queue calls that we will no longer need to execute. This is
   * due ot the fact that we will not be finished the first rc --symbol-info
   * call before we queue up two more. The strategy here is to generate a
   * function to return the suggestion and queue it up after the currently
   * executiong one.
   */
  getSuggestionForWord(textEditor, text, range) {
    if (!n_util.matched_scope(textEditor)) {
      return generateEmptySuggestion();
    }

    // suggestionFunc will execute *after* currently executing promise
    let suggestionFunc = () => {
      return this.rcExecutor.get_symbol_info(textEditor.getPath(), range.start)
        .then((out) => {
          // We have to heal the range here. Range in circumstances such as x::y
          // or x->y will contain x when hovering over y. This isn't quite what we
          // want. Instead of using the range they give us, we'll give beginning + symbolLength
          let range = new n_atom.Range([out.location.row, out.location.column], [out.location.row, out.location.column + out.symbolLength])

          // Special case where symbol length doesn't match
          let operStr = "operator"
          if (out.symbolName.slice(0,operStr.length) == operStr && out.Kind == "DeclRefExpr") {
            range.end.column -= operStr.length;
          }

          return {
            range: range,

            // This really sucks. On click we call this callback. Hyperclick
            // doesn't provide us with an api to distinguish between right and
            // left click, so we look for which mouse is raised after we get the
            // callback. Then we decide whether or not we we want to find
            // references/virtuals/etc.
            callback: () => {
              return new Promise((resolve) => {
                var handleMouseUp = (e) => {
                  removeEventListener('mouseup', handleMouseUp);
                  resolve(e);
                };
                addEventListener('mouseup', handleMouseUp);
              }).then( (mouseUpEvent) => {
                // FIXME: This should definitely not be hard coded
                if (mouseUpEvent.button == 0) {
                  this.actionExecutor.findSymbolAtPoint();
                }
                else if (mouseUpEvent.button == 1) {
                  this.actionExecutor.findVirtualsAtPoint();
                }
                else if (mouseUpEvent.button == 2) {
                  this.actionExecutor.findReferencesAtPoint();
                }
              })
              .catch((error) => atom.notifications.addError(error));
            }
          }
        })
        .catch((err) => {
          if (err && err.trim) {
            err = err.trim();
          }
          if (!err || (err != "No Results" && err != "Not indexed" )) {
            console.error("Caught", err, "in rtags hyperclick provider")
          }
          return generateEmptySuggestion();
        });
    }

    this.nextSuggestionFunc = suggestionFunc;

    // Return it queued after
    return this.currentPromise.then(() => {
      // Cancel action if we have been replaced with another request
      if (this.nextSuggestionFunc != suggestionFunc) {
        return generateEmptySuggestion();
      }
      // Assign currentPromise to be new executing rc call
      this.currentPromise = this.nextSuggestionFunc();
      // return suggesitonFunc promise
      return this.currentPromise;
    });
  }
}
