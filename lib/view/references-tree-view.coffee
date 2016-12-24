referencesClassName = 'rtags-references'
rtags = require '../rtags'

class RtagsReference
  constructor: (ref, path, indentLevel, redrawCallback)->
    @currentlyOpen = false
    @element = document.createElement('tr')
    @callerReferences = null
    @caller = null
    @redrawCallback = redrawCallback
    @indentLevel = indentLevel
    @path = path

    [@line, @column, content, @caller] = ref
    # Looks like atom lines and columns are 0 indexed, but all display is 1 indexed
    displayLine = @line + 1;
    displayColumn = @column + 1;

    hasCaller = (@caller != null)

    pathCol = document.createElement('td')
    pathCol.style.whiteSpace = 'no-wrap'
    pathColLine = document.createElement('nobr')

    # Expander has to be part of path column to ensure that indentation doesn't look wrong
    for i in [1..@indentLevel] by 1
      indentSpan = document.createElement('span')
      indentSpan.classList.add('rtags-indent-span')
      indentSpan.textContent = '    '
      pathColLine.appendChild(indentSpan)
    if hasCaller
      @currentRefDisclosureArrow = document.createElement('span')
      @currentRefDisclosureArrow.classList.add('icon', 'icon-chevron-right')
      @currentRefDisclosureArrow.onclick = @toggle
      pathColLine.appendChild(@currentRefDisclosureArrow)

    pathSpan = document.createElement('span')
    pathSpan.textContent = "#{path}:#{displayLine}:#{displayColumn}:"
    pathSpan.onclick = @openPath
    pathColLine.appendChild(pathSpan)
    pathCol.appendChild(pathColLine)
    @element.appendChild(pathCol)

    lineCol = document.createElement('td')
    lineCol.style.whiteSpace = 'nowrap'
    lineCol.classList.add('text-highlight')
    lineCol.onclick = @openPath
    lineCol.textContent = "#{content}"
    @element.appendChild(lineCol)

    callerCol = document.createElement('td')
    callerCol.style.width = '100%'
    if hasCaller
      callerCol.textContent = "#{@caller.signature}"
      callerCol.onclick = @openPath

    @element.appendChild(callerCol)

  openPath: =>
    options = {
      initialLine: @line,
      initialColumn: @column,
    }
    atom.workspace.open(@path, options)

  expand: =>
    @currentlyOpen = true
    @currentRefDisclosureArrow.classList.remove('icon-chevron-right')
    @currentRefDisclosureArrow.classList.add('icon-chevron-down')
    @callerReferences = new RtagsReferencesList(@indentLevel + 1, @redrawCallback)
    try
      @callerReferences.setReferences(rtags.find_references_at_point(@caller.filename, @caller.location))
    catch err
      console.log(err)

    @redrawCallback()

  fold: =>
    @currentlyOpen = false
    @currentRefDisclosureArrow.classList.remove('icon-chevron-down')
    @currentRefDisclosureArrow.classList.add('icon-chevron-right')
    @callerReferences.destroy()
    @callerReferences = null
    @redrawCallback()

  getReferences: =>
    ret = [@element]
    if @callerReferences != null
      ret.push.apply(ret, @callerReferences.getReferences())
    ret

  toggle: =>
    if @currentlyOpen == true
      @fold()
    else
      @expand()

class RtagsReferencesList
  constructor: (indentLevel, redrawCallback)->
    @references = []
    @redrawCallback = redrawCallback
    @indentLevel = indentLevel

  getReferences: =>
    ret = []
    for reference in @references
      ret.push.apply(ret, reference.getReferences())
    ret

  destroy: =>
    @references = []

  setReferences: (res) =>
    @references = []
    for path, refArray of res.res
      for ref in refArray
        ref = new RtagsReference(ref, path, @indentLevel, @redrawCallback)
        @references.push(ref)

module.exports =
class RtagsReferencesTreePaneView
  constructor: ->
    @element = document.createElement('div')
    @element.style.height = "200px"

    @resizeHandle = document.createElement('div')
    @resizeHandle.style.height = '8px'
    @resizeHandle.style.cursor = 'row-resize'
    @resizeHandle.onmousedown =  @resizeStarted
    @resizeHandle.onmouseup =  @resizeStopped
    @element.appendChild(@resizeHandle)

    @header = document.createElement('header')
    title = document.createElement('h2')
    title.textContent = "Rtags References"
    # Ensure the next element (the close button) is on the same line
    title.style.display += 'inline-block'
    @header.appendChild(title)

    # TODO: Align it vertically
    closeButton = document.createElement ('span')
    closeButton.classList.add('icon', 'icon-x', 'pull-right')
    closeButton.onclick = @destroy

    @header.appendChild(closeButton)

    @element.appendChild(@header)

    # Put table in a div to allow for scrolling
    @referencesTableDiv = document.createElement('div')
    @referencesTableDiv.style.overflow = 'auto'
    @referencesTable = @generateReferencesTable()
    @referencesTableDiv.appendChild(@referencesTable)
    @element.appendChild(@referencesTableDiv)

    @child = new RtagsReferencesList(0, @redraw)

  generateReferencesTable: ->
    referencesTable = document.createElement('table')
    referencesTable.classList.add('rtags-references-table')
    #referencesTable.style.width = '100%'
    referencesTable

  setReferences: (res) =>
    @child.setReferences(res)
    @redraw()
    @rerender()

  destroy: =>
    @element.remove()

  getElement: =>
    @element

  resizeStarted: =>
    document.addEventListener('mousemove', @resize)
    document.addEventListener('mouseup', @resizeStopped)

  resizeStopped: =>
    document.removeEventListener('mousemove', @resize)
    document.removeEventListener('mouseup', @resizeStopped)

  resize: (event) =>
    boundingBox = @element.getBoundingClientRect()
    @element.style.height = "" + (boundingBox.bottom - event.pageY) + "px"
    @rerender()

  redraw: =>
    # Logic here is
    # * Delete all table elements
    # * Repopulate table with new elements
    referencesTable = @generateReferencesTable()
    for element in @child.getReferences()
      referencesTable.appendChild(element)
    @referencesTable.parentNode.replaceChild(referencesTable, @referencesTable)
    @referencesTable = referencesTable

  rerender: =>
    boundingBox = @element.getBoundingClientRect()
    headerBoundingBox = @header.getBoundingClientRect()
    headerHeight = headerBoundingBox.bottom - headerBoundingBox.top
    elementHeight = boundingBox.bottom - boundingBox.top
    # TODO: fix hardcoded 20
    @referencesTableDiv.style.height = "" + elementHeight - headerHeight - 20 + "px"
