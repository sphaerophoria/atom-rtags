{$, View} = require 'space-pen'
{Point, TextBuffer} = require 'atom'
{Node, HeaderView, RtagsTreeView, ResizeHandleView} = require './references-tree-view'
child_process = require 'child_process'
util = require '../util.js'


#TODO: There's a lot of duplication from the RtagsReferencesTreePane here.
module.exports.RtagsRefactorConfirmationNode =
  class RtagsRefactorConfirmationNode extends Node
    getView: ->
      @checkbox = $('<input>').attr('type', 'checkbox').prop('checked', true)
      if !@data.refactorLines
        @expander.hide()

        bufferPromise = null
        if atom.config.get('atom-rtags-plus.liveParsing')
          bufferPromise = util.getTextBuffer(@data.path)
        else
          bufferPromise = Promise.resolve()
          .then(() =>
            buffer = new TextBuffer({filePath: @data.path})
            buffer.loadSync()
            return buffer
          )

        lineTd = $('<td>')
        bufferPromise.then((buffer) =>
          lineStr = buffer.lineForRow(@data.refactorLineLoc.row - 1)
          lineTd.text(lineStr)
        )
        console.log(@data.path, @data.refactorLineLoc)
        return [$('<span>').append(@checkbox), lineTd]
      else
        # Here we prep the children for later
        ret = [];
        for refactorLine in @data.refactorLines
          ret.push(new RtagsRefactorConfirmationNode({path: @data.path, refactorLineLoc: refactorLine}, @indentLevel + 3, @redrawCallback))
        @data.refactorLines = ret
        return [$('<span>').append(@checkbox), $('<td>').text(@data.path).width('100%')]

    retrieveChildren: ->
      new Promise((resolve) =>
        resolve(@data.refactorLines)
        )

    isChecked: ->
      @checkbox.prop('checked')

    onClick: =>
      atom.workspace.open

module.exports.RtagsRefactorConfirmationPane =
  class RtagsRefactorConfirmationPane extends View
    @content: ->
      @div =>
        @subview 'resizeHandle', new ResizeHandleView
        @subview 'header', new HeaderView(title: "Rtags Refactor")
        @subview 'referencesTree', new RtagsTreeView
        @div align: 'right', =>
          @div 'Cancel', class: 'btn', mouseUp: 'cancel'
          @div 'Confirm', class: 'btn', mouseUp: 'confirm'

    initialize: ->
      @panel = null
      @resizeHandle.setResizee(@referencesTree)
      @referencesTree.height(200)

    destroy: ->
      @panel?.destroy()

    show: ->
      @destroy()
      @panel = atom.workspace.addBottomPanel({item: @})

    confirm: ->
      for node in @referencesTree.children
        if !node.isChecked()
          continue

        editorPromise = atom.workspace.open(node.data.path, {activateItem: false})
        for childNode in node.data.refactorLines
          if !childNode.isChecked()
            continue

          # This do prevents variables in the promise from being overwritten in
          # the next iteration of the loop
          do (childNode, node, editorPromise) ->
            editorPromise = editorPromise.then((editor) =>
              # If we're currently in a modified buffer, we don't want to apply
              # potentially unsaved changes, however we don't want to force people
              # to save in files they haven't touched yet
              saveAfterChange = !editor.isModified()
              cursor = editor.getLastCursor()
              editor.setCursorBufferPosition(new Point(childNode.data.refactorLineLoc.row - 1, childNode.data.refactorLineLoc.column - 1))
              wordRange = util.getCurrentWordBufferRange(editor);
              editor.setTextInBufferRange(wordRange, node.data.replacement);
              if saveAfterChange
                editor.save();
              return editor
            )
      @destroy()

    cancel: ->
      @destroy()
