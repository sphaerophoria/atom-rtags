rtags = require '../rtags'

module.exports =
  class RtagsSearchView
    constructor: (searchCallback, destroyCallback) ->
      @destroyCallback = destroyCallback
      @searchCallback = searchCallback

      @element = document.createElement('form')
      @textbox = document.createElement('input')
      @textbox.classList.add('input-text', 'native-key-bindings')
      @textbox.autofocus = true
      @textbox.type = 'text'
      @element.appendChild(@textbox)
      @textbox.onkeyup = @handleKeydown

    getElement: =>
      @element

    destroy: =>
      @element.remove()
      @destroyCallback()

    handleKeydown: (event) =>
      if event.keyCode == 13
        @searchCallback(@textbox.value)
      else if event.keyCode == 27
        @destroy()
      return
