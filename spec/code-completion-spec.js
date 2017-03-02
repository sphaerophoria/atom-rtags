const {RcExecutor} = require('../lib/rtags.js')
const RtagsCodeCompleter = require('../lib/code-completer.coffee')
const {Point} = require('atom')
const child_process = require('child_process')

let ensureResults = function(suggestions) {
    if (suggestions[0].snippet === undefined) {
        throw "No snippet"
    }
};


describe( "Code completion", function() {
    var rcExecutor = new RcExecutor();
    rcExecutor.start_rc_worker();

    var codeCompleter;
    var finished;

    beforeEach( function() {
        atom.config.set('atom-rtags-plus.rcCommand', 'rc')
        atom.config.set('atom-rtags-plus.codeCompletion', true)

        finished = false;
        codeCompleter = new RtagsCodeCompleter();
        codeCompleter.setRcExecutor(rcExecutor);
    })

    afterEach( function () {
        waitsFor(function() {
            return finished;
        }, "should execute reasonably quickly", 1000);
    })


    it("should provide results", function () {
        runs(function() {
            return atom.workspace.open("cppsrc/test.cpp")
            .then((editor) => {
                editor.setCursorBufferPosition(new Point(10,0))
                editor.insertText("T", {autoIndent: false});
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(10, 1), scopeDescriptor: null, prefix: "T", activatedManually: false})
            })
            .then((suggestions) => {
                expect(() => ensureResults(suggestions)).not.toThrow();
            })
            .then(() => finished = true);
        })
    });

    it("should provide correct completions", function() {
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
    });

    it ("should only execute rc once for the same input", function () {
        runs(function() {
            let editor = null;
            return atom.workspace.open("cppsrc/test.cpp")
            .then((promiseEditor) => {
                editor = promiseEditor;
                editor.setCursorBufferPosition(new Point(10,0))
                editor.insertText("T", {autoIndent: false});
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(10, 1), scopeDescriptor: null, prefix: "T", activatedManually: false});
            })
            .then((suggestions) => {
                expect(() => ensureResults(suggestions)).not.toThrow();
            })
            .then(() => {
                codeCompleter.setRcExecutor(null);
                editor.insertText("e", {autoIndent: false});
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(10, 2), scopeDescriptor: null, prefix: "Te", activatedManually: false});
            })
            .then((suggestions) => {
                expect(() => ensureResults(suggestions)).not.toThrow()
            })
            .then( () => {
                editor.deleteToBeginningOfLine();
                editor.insertText("s");
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(10, 1), scopeDescriptor: null, prefix: "s", activatedManually: false});
            })
            .then((suggestions) => {
                expect(() => ensureResults(suggestions)).not.toThrow()
            })
            .then(() => finished = true);
        })
    });

    it("should provide completions after a ., :: and ->", function() {
        runs(function() {
            let editor = null;
            return atom.workspace.open("cppsrc/test.cpp")
            .then((promiseEditor) => {
                editor = promiseEditor;
                editor.setCursorBufferPosition(new Point(13, 0))
                let prefix = "TestNamespace::"
                editor.insertText(prefix, {autoIndent: false});
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(13, prefix.length), scopeDescriptor: null, prefix: "::", activatedManually: false})
            })
            .then((suggestions) => {
                expect(() => ensureResults(suggestions)).not.toThrow()
                editor.deleteToBeginningOfLine();
                let prefix = "pTestClass->"
                editor.insertText(prefix, {autoIndent: false});
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(13, prefix.length), scopeDescriptor: null, prefix: "", activatedManually: false})
            })
            .then((suggestions) => {
                expect(() => ensureResults(suggestions)).not.toThrow()
                editor.deleteToBeginningOfLine();
                let prefix = "(*pTestClass)."
                editor.insertText(prefix, {autoIndent: false});
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(13, prefix.length), scopeDescriptor: null, prefix: ".", activatedManually: false})
            })
            .then((suggestions) => {
                expect(() => ensureResults(suggestions)).not.toThrow()
            })
            .then(() => finished = true);
        })
    })

    it("should parse correctly on doxygen commented variables", function() {
        runs(function() {
            let editor = null;
            return atom.workspace.open("cppsrc/test.cpp")
            .then((promiseEditor) => {
                editor = promiseEditor;
                editor.setCursorBufferPosition(new Point(13, 0))
                let prefix = "pTestClass->m_publicMemberV"
                let item = "m_publicMemberV"
                editor.insertText(prefix, {autoIndent: false});
                return codeCompleter.getSuggestions({editor, bufferPosition: new Point(13, prefix.length), scopeDescriptor: null, prefix: item, activatedManually: false})
            })
            .then((suggestions) => {
                expect(suggestions[0].snippet).toBe("m_publicMemberVar");
                expect(suggestions[0].leftLabel).toBe("int");
                expect(suggestions[0].rightLabel).toBe("FieldDecl")
                expect(suggestions[0].type).toBe("variable")
            })
            .then(() => finished = true);
        })
    })
})
