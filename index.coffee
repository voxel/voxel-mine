# vim: set shiftwidth=2 tabstop=2 softtabstop=2 expandtab:

module.exports = (game, opts) ->
  return new Mine(game, opts)

Mine = (game, opts) ->
  this.game = game
  opts = opts ? {}
  opts.defaultHardness ?= 3
  opts.instaMine ?= false

  this.opts = opts

  this.instaMine = opts.instaMine
  this.progress = 0

  this.bindEvents()

  this

Mine::bindEvents = ->
  this.game.on 'mining', (hit_voxel) =>
    if not hit_voxel?
      console.log("no block mined")
      return

    # TODO: show destroy stage overlay
    this.progress += 1

    # TODO: variable hardness based on block type
    if this.instaMine || this.progress > this.opts.defaultHardness
      this.game.setBlock hit_voxel, 0
      this.progress = 0
      # TODO: reset this.progress if mouse released

