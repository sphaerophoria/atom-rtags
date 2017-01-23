{$, View} = require 'space-pen'
{Node, HeaderView, RtagsTreeView, ResizeHandleView} = require './references-tree-view'
child_process = require 'child_process'


#TODO: There's a lot of duplication from the RtagsReferencesTreePane here.
module.exports.RtagsRefactorConfirmationNode =
  class RtagsRefactorConfirmationNode extends Node
    getView: ->
      @checkbox = $('<input>').attr('type', 'checkbox').prop('checked', true)
      [$('<span>'), @checkbox, $('<td>').text(@data.path).width('100%')]

    retrieveChildren: ->
      for refactorLine in @data.refactorLines
        console.log(refactorLine)
      new Promise((resolve) ->
        resolve([])
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
        for pathObj in node.data.refactorLines
          cmdStr += pathObj.line
          cmdStr += 's/^\\(.\\{'
          cmdStr += parseInt(pathObj.col, 10) - 1
          cmdStr += '\\}\\)[a-zA-Z0-9_]*/\\1' + node.data.replacement + '/;'
        cmdStr += '\' ' + node.data.path
        # Shell out to sed to do the replacement console.log(cmdStr)
        child_process.exec(cmdStr)
      @destroy()

    cancel: ->
      @destroy()
