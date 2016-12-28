{View} = require 'space-pen'
rtags = require '../rtags'

module.exports =
  class RtagsSearchView extends View
    @content: ->
      @form =>
        @input class: 'input-text native-key-bindings', type: 'text', keyup: 'handleKeydown', outlet: 'textbox'

    initialize: () ->
      @panel = null
      @searchCallback = null

    setSearchCallback: (callback) ->
      @searchCallback = callback

    show: ->
      @textbox.val('')
      @panel = atom.workspace.addModalPanel({item: @})
      @textbox.focus()

    hide: ->
      @panel?.destroy()

    handleKeydown: (event) =>
      if event.keyCode == 13
        @searchCallback?(@textbox.val())
        @hide()
      else if event.keyCode == 27
        @hide()
      return
