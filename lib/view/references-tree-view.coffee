{$, View} = require 'space-pen'
rtags = require '../rtags'

class Node extends View
  @content: ->
    @tr =>
      @td outlet: 'nodeTd', style: 'white-space: nowrap;', =>
        @span outlet: 'indents', style: 'white-space: pre'
        @span outlet: 'expander', class: 'icon icon-chevron-right'

  initialize: (data, indentLevel, redrawCallback) ->
    @data = data
    @redrawCallback = redrawCallback
    @indentLevel = indentLevel

    @children = []

    for i in [0..@indentLevel][1..]
      @indents.append('    ')

    @.append(@getView())
    @.on('click', ' *', @onClick)
    @nodeTd.unbind('click', @onClick)
    @expander.click(@expand)
    @redrawCallback()

  getNodes: ->
    ret = []
    ret.push.apply(ret, @)
    for child in @children
      ret.push.apply(ret, child.getNodes())
    ret

  expand: (e) =>
    @expander.unbind('click', @expand)
    @expander.click(@fold)
    @expander.removeClass('icon-chevron-right')
    @expander.addClass('icon-chevron-down')
    @retrieveChildren().then((newChildren) =>
        @children.push.apply(@children, newChildren)
        @redrawCallback())
    e.stopPropagation()

  fold: (e) =>
    @expander.unbind('click', @fold)
    @expander.click(@expand)
    @expander.removeClass('icon-chevron-down')
    @expander.addClass('icon-chevron-right')
    @children = []
    @redrawCallback()
    e.stopPropagation()

module.exports.RtagsReferenceNode =
class RtagsReferenceNode extends Node
  getView: ->
    [@line, @column, content, @caller] = @data.ref

    # Looks like atom lines and columns are 0 indexed, but all display is 1 indexed
    displayLine = @line + 1;
    displayColumn = @column + 1;

    hasCaller = (@caller != null)

    spacer = $(document.createElement('span'))
    spacer.width(300);

    pathView = $(document.createElement('span'))
    pathView.text("#{@data.path}:#{displayLine}:#{displayColumn}")
    contentView = $(document.createElement('span')).addClass('text-highlight').css('white-space', 'nowrap')
    contentView.text("#{content}")

    ret = [pathView, spacer.clone(), contentView]

    if hasCaller
      callerView = $(document.createElement('span')).width('100%').addClass('text-success')
      callerView.text("#{@caller.signature}")
      ret.push(spacer.clone())
      ret.push(callerView)
    else
      @expander.hide()

    ret

  retrieveChildren: ->
    references = rtags.find_references_at_point(@caller.filename, @caller.location)

    references.then((references) =>
        ret = []
        for path, refArray of references.res
            for ref in refArray
                ref = new RtagsReferenceNode({ref: ref, path: path}, @indentLevel + 1, @redrawCallback)
                ret.push(ref)
        ret, () -> [])

  onClick: =>
    atom.workspace.open(@data.path, {initialLine: @line, initialColumn: @column})

module.exports.RtagsReferencesTreePane =
class RtagsReferencesTreePane extends View
  @content: ->
    @div =>
      @div outlet: 'resizeHandle', style: 'height: 8px; cursor: row-resize', mouseDown: 'resizeStarted', mouseUp: 'resizeStopped'
      @tag 'header', outlet: 'header', =>
        @h2 'Rtags References', style: 'display: inline-block;'
        @span class: 'icon icon-x pull-right', click: 'destroy'
      @div style: 'overflow: auto;', outlet: 'referencesTableDiv', =>
        @table class: 'rtags-references-table', outlet: 'referencesTable'

  initialize: ->
    @panel = null
    @children = []
    @height(200)

  setItems: (items) ->
    @children = []

    for item in items
      @children.push(item)

    @redraw()
    @resizeChild()

  resizeStarted: ->
    document.addEventListener('mousemove', @resize)
    document.addEventListener('mouseup', @resizeStopped)

  resizeStopped: ->
    document.removeEventListener('mousemove', @resize)
    document.removeEventListener('mouseup', @resizeStopped)

  resize: (event) =>
    boundingBox = @element.getBoundingClientRect()
    @height(boundingBox.bottom - event.pageY)
    @resizeChild()

  resizeChild: ->
    headerHeight = @header.height()
    elementHeight = @height()
    # TODO: fix hardcoded 20
    @referencesTableDiv.height(elementHeight - headerHeight - 20)

  redraw: =>
    @referencesTable.children().detach()
    for rtagsReference in @children
      for reference in rtagsReference.getNodes()
        @referencesTable.append(reference)

  destroy: ->
    @panel?.destroy()

  show: ->
    @destroy()
    @panel = atom.workspace.addBottomPanel({item: @})
