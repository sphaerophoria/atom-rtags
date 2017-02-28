const {RcExecutor} = require('../lib/rtags.js')
const RtagsCodeCompleter = require('../lib/code-completer.coffee')
const {Point} = require('atom')
const child_process = require('child_process')

describe( "Code completion", function() {
    beforeEach( function() {
        atom.config.set('atom-rtags-plus.rcCommand', 'rc')
        atom.config.set('atom-rtags-plus.codeCompletion', true)
    })

    var rcExecutor = new RcExecutor();
    rcExecutor.start_rc_worker();

    it("should provide results", function () {
        let finished = false;
        let codeCompleter = new RtagsCodeCompleter()
        codeCompleter.setRcExecutor(rcExecutor);

        runs(function() {
            return atom.workspace.open("cppsrc/test.cpp")
            .then((editor) => {
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(8, 1), scopeDescriptor: null, prefix: "T", activatedManually: false})
            })
            .then((suggestions) => {
                expect(suggestions.length).not.toBe(0);
            })
            .then(() => finished = true);
        })

        waitsFor(function() {
            return finished;
        }, "should execute reasonably quickly", 1000);
    });

    it("should provide correct completions", function() {
        let finished = false;
        let codeCompleter = new RtagsCodeCompleter()
        codeCompleter.setRcExecutor(rcExecutor);

        runs(function() {
            return atom.workspace.open("cppsrc/test.cpp")
            .then((editor) => {
                editor.setCursorBufferPosition(new Point(10, 0))
                editor.insertText("TestNamespace::", {autoIndent: false});
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(10, 24), scopeDescriptor: null, prefix: "TestClass", activatedManually: false})
            })
            .then((suggestions) => {
                expect(suggestions.length).not.toBe(0);
                expect(suggestions[0].rightLabel).toBe('ClassDecl');
                expect(suggestions[0].type).toBe('type');
                expect(suggestions[0].leftLabel).toBe('TestClass');
                expect(suggestions[0].snippet).toBe('TestClass');
            })
            .then(() => finished = true);
        })

        waitsFor(function() {
            return finished;
        }, "should execute reasonably quickly", 1000);
    });

    it ("should only execute rc once for the same input", function () {
        let finished = false;
        let codeCompleter = new RtagsCodeCompleter()
        codeCompleter.setRcExecutor(rcExecutor);

        runs(function() {
            let editor = null;
            let ensureResults = function(suggestions) {
                if (suggestions[0].snippet === undefined) {
                    throw "No snippet"
                }
            };

            return atom.workspace.open("cppsrc/test.cpp")
            .then((promiseEditor) => {
                editor = promiseEditor;
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(10, 0), scopeDescriptor: null, prefix: "T", activatedManually: false});
            })
            .then((suggestions) => {
                expect(() => ensureResults(suggestions)).not.toThrow()
            })
            .then(() => {
                codeCompleter.setRcExecutor(null);
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(10, 1), scopeDescriptor: null, prefix: "Te", activatedManually: false});
            })
            .then((suggestions) => {
                expect(() => ensureResults(suggestions)).not.toThrow()
            })
            .then( () => {
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(10, 0), scopeDescriptor: null, prefix: "s", activatedManually: false});
            })
            .then((suggestions) => {
                expect(() => ensureResults(suggestions)).not.toThrow()
            })
            .then(() => finished = true);
        })

        waitsFor(function() {
            return finished;
        }, "should execute reasonably quickly", 1000);
    });

    it("should provide completions after a ., :: and ->", function() {
        //FIXME: Not implemented
    })

    it("should parse correctly on doxygen commented variables", function() {
        //FIXME: Not implemented
    })
})
