{$, View} = require 'space-pen'
{TextBuffer} = require 'atom'
{Node, HeaderView, RtagsTreeView, ResizeHandleView} = require './references-tree-view'
child_process = require 'child_process'


#TODO: There's a lot of duplication from the RtagsReferencesTreePane here.
module.exports.RtagsRefactorConfirmationNode =
  class RtagsRefactorConfirmationNode extends Node
    getView: ->
      @checkbox = $('<input>').attr('type', 'checkbox').prop('checked', true)
      if !@data.refactorLines
        @expander.hide()
        # Here we open a textBuffer and grab the line
        buffer = new TextBuffer({filePath: @data.path})
        buffer.loadSync()
        lineStr = buffer.lineForRow(@data.refactorLineLoc.line - 1)
        return [$('<span>').append(@checkbox),  $('<td>').text(lineStr)]
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

        cmdStr = 'sed -i \''
        for childNode in node.data.refactorLines
          if !childNode.isChecked()
            continue
          cmdStr += childNode.data.refactorLineLoc.line
          cmdStr += 's/^\\(.\\{'
          cmdStr += parseInt(childNode.data.refactorLineLoc.col, 10) - 1
          cmdStr += '\\}\\)[a-zA-Z0-9_]*/\\1' + node.data.replacement + '/;'
        cmdStr += '\' ' + node.data.path
        # Shell out to sed to do the replacement console.log(cmdStr)
        child_process.exec(cmdStr)
      @destroy()

    cancel: ->
      @destroy()
