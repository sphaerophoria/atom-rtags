{$, View} = require 'space-pen'
rtags = require '../rtags'
util = require '../util'

module.exports.Node =
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
        @expanded = false

        @children = []

        for i in [0..@indentLevel][1..]
          @indents.append('    ')

        view = @getView()
        @nodeTd.append(view[0])
        @.append(view[1..])
        @redrawCallback()

      applyClickHandlers: () ->
        @.unbind('click', @onClick)
        @expander.unbind('click', @expand)
        @expander.unbind('click', @fold)

        @.on('click', ' *', @onClick)
        @nodeTd.unbind('click', @onClick)
        if (@expanded)
          @expander.click(@fold)
        else
          @expander.click(@expand)


      getNodes: ->
        ret = []
        ret.push.apply(ret, @)
        @applyClickHandlers()
        for child in @children
          ret.push.apply(ret, child.getNodes())
        ret

      expand: (e) =>
        @expanded = true;
        @expander.unbind('click', @expand)
        @expander.click(@fold)
        @expander.removeClass('icon-chevron-right')
        @expander.addClass('icon-chevron-down')
        @retrieveChildren().then((newChildren) =>
            @children.push.apply(@children, newChildren)
            @redrawCallback())
        e.stopPropagation()

      fold: (e) =>
        @expanded = false
        @expander.unbind('click', @fold)
        @expander.click(@expand)
        @expander.removeClass('icon-chevron-down')
        @expander.addClass('icon-chevron-right')
        @children = []
        @redrawCallback()
        e.stopPropagation()

module.exports.RtagsClassHierarchyNode =
class RtagsClassHierarchyNode

module.exports.RtagsReferenceNode =
class RtagsReferenceNode extends Node
  getView: ->
    [@line, @column, content, @caller] = @data.ref

    # Looks like atom lines and columns are 0 indexed, but all display is 1 indexed
    displayLine = @line + 1;
    displayColumn = @column + 1;

    hasCaller = (@caller != null)

    spacer = $(document.createElement('span')).css('white-space', 'pre').text("  ")

    # Here we display the key as the caller if we have it, if not we use the filename as an approximation
    keyView = null;
    if hasCaller
      keyView = $(document.createElement('span'))
      sigParts = @caller.signature.split('(')
      if sigParts.length > 1
        isFunction = true
      else
        isFunction = false

      sigParts = sigParts[0].split(' ')
      sigString = sigParts[sigParts.length - 1]
      keyView.text("#{sigString}")

      if isFunction
        keyView.text(keyView.text() + "()")

    else
      keyView = $(document.createElement('span'))
      keyView.text("#{@data.path}:#{displayLine}:#{displayColumn}")
      @expander.hide()

    contentView = $(document.createElement('td')).addClass('text-highlight').css('white-space', 'nowrap').width('100%')

    #TODO: This can be removed on resoution of https://github.com/Andersbakken/rtags/issues/911
    if atom.config.get('atom-rtags-plus.liveParsing')
      textBufferPromise = util.getTextBuffer(@data.path)

      textBufferPromise.then((textBuffer) =>
        contentView.text(textBuffer.lineForRow(@line))
      )
    else
      contentView.text(content)

    [keyView, spacer, contentView]

  retrieveChildren: ->
    references = @data.rcExecutor.find_references_at_point(@caller.filename, @caller.location)

    references.then((references) =>
        ret = []
        for path, refArray of references.res
            for ref in refArray
                ref = new RtagsReferenceNode({ref: ref, path: path, rcExecutor: @data.rcExecutor}, @indentLevel + 1, @redrawCallback)
                ret.push(ref)
        ret)

  onClick: =>
    atom.workspace.open(@data.path, {'initialLine': @line, 'initialColumn': @column})

module.exports.ResizeHandleView =
class ResizeHandleView extends View
  @content: ->
    @div style: 'height: 4px; cursor: row-resize', mouseDown: 'resizeStarted', mouseUp: 'resizeStopped'

  initialize: (vertical=true) ->
    @vertical = vertical

  setResizee: (resizee) ->
    @resizee = resizee

  resizeStarted: ->
    document.addEventListener('mousemove', @resize)
    document.addEventListener('mouseup', @resizeStopped)

  resizeStopped: ->
    document.removeEventListener('mousemove', @resize)
    document.removeEventListener('mouseup', @resizeStopped)

  resize: (event) =>
    boundingBox = @parentView.element.getBoundingClientRect()
    if (@vertical)
      currentHeight = @resizee.height()
      heightDiff = @offset().top - event.pageY
      @resizee.height(currentHeight + heightDiff)
    else
      atom.notifications.addError("Unimplemented horizontal resize")

module.exports.HeaderView =
class HeaderView extends View
  @content: (params) ->
      @tag 'header', outlet: 'header', =>
        @h2 params.title, style: 'display: inline-block;'
        @span class: 'icon icon-x pull-right', click: 'destroy'

  destroy: ->
    @parentView.destroy()

module.exports.RtagsTreeView =
class RtagsTreeView extends View
  @content: ->
    @div style: 'overflow: auto;', =>
      @table class: 'rtags-references-table', outlet: 'referencesTable'

  initialize: ->
    @children = []

  setItems: (items) ->
    @children = []

    for item in items
      @children.push(item)

    @redraw()

  redraw: =>
    @referencesTable.children().remove()
    for rtagsReference in @children
      for reference in rtagsReference.getNodes()
        @referencesTable.append(reference)

module.exports.RtagsReferencesTreePane =
class RtagsReferencesTreePane extends View
  @content: ->
    @div style: 'padding: 0 10px', =>
      @subview 'resizeHandle', new ResizeHandleView
      @subview 'header', new HeaderView(title: "Rtags References")
      @subview 'referencesTree', new RtagsTreeView

  initialize: ->
    @panel = null
    @resizeHandle.setResizee(@referencesTree)
    @referencesTree.height(200)

  destroy: ->
    @panel?.destroy()

  show: ->
    @destroy()
    @panel = atom.workspace.addBottomPanel({item: @})
