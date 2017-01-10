{View} = require 'space-pen'
rtags = require '../rtags'

class RtagsReference extends View
  @content: ->
    @tr =>
      @td style: 'white-space: nowrap;', =>
        @span outlet: 'indents', style: 'white-space: pre'
        @span outlet: 'expander', class: 'icon icon-chevron-right'
        @span outlet: "pathText", click: 'openPath', style: 'width: 100%'
      @td outlet: 'referenceText', class: 'text-highlight', click: 'openPath', style: 'white-space: nowrap;'
      @td outlet: "callerText", click: 'openPath', style: 'width: 100%;'

  initialize: (ref, path, indentLevel, redrawCallback) ->
    @caller = null
    @redrawCallback = redrawCallback
    @indentLevel = indentLevel
    @path = path
    @children = []

    [@line, @column, content, @caller] = ref
    # Looks like atom lines and columns are 0 indexed, but all display is 1 indexed
    displayLine = @line + 1;
    displayColumn = @column + 1;
    hasCaller = (@caller != null)

    @expander.click(@expand)

    for i in [0..@indentLevel][1..]
      @indents.append('    ')

    if hasCaller
      @expander.show()
    else
      @expander.hide()

    @pathText.text("#{path}:#{displayLine}:#{displayColumn}:")
    @referenceText.text("#{content}")
    if hasCaller
      @callerText.text("#{@caller.signature}")

  getReferences: ->
    ret = []
    ret.push.apply(ret, @)
    for child in @children
      ret.push.apply(ret, child.getReferences())
    ret

  expand: =>
    @expander.unbind('click', @expand)
    @expander.click(@fold)
    @expander.removeClass('icon-chevron-right')
    @expander.addClass('icon-chevron-down')
    rtags.find_references_at_point(@caller.filename, @caller.location).then((out) =>
      @addChildren(out)
      @redrawCallback())

  fold: =>
    @expander.unbind('click', @fold)
    @expander.click(@expand)
    @expander.removeClass('icon-chevron-down')
    @expander.addClass('icon-chevron-right')
    @children = []
    @redrawCallback()

  openPath: ->
    options = {
      initialLine: @line,
      initialColumn: @column,
    }
    atom.workspace.open(@path, options)

  addChildren: (res)->
    for path, refArray of res.res
      for ref in refArray
        ref = new RtagsReference(ref, path, @indentLevel + 1, @redrawCallback)
        @children.push(ref)

module.exports =
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

  setReferences: (res) ->
    @children = []
    for path, refArray of res.res
      for ref in refArray
        ref = new RtagsReference(ref, path, 0, @redraw)
        @children.push(ref)
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
      for reference in rtagsReference.getReferences()
        @referencesTable.append(reference)

  destroy: ->
    @panel?.destroy()

  show: ->
    @destroy()
    @panel = atom.workspace.addBottomPanel({item: @})
