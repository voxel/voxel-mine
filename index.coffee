# vim: set shiftwidth=2 tabstop=2 softtabstop=2 expandtab:

inherits = require 'inherits'
EventEmitter = (require 'events').EventEmitter

module.exports = (game, opts) ->
  return new Mine(game, opts)

Mine = (game, opts) ->
  this.game = game
  opts = opts ? {}
  opts.defaultHardness ?= 3
  opts.instaMine ?= false
  if !opts.reach?
    throw "voxel-mine requires 'reach' option set to voxel-reach instance"

  this.opts = opts

  this.instaMine = opts.instaMine
  this.progress = 0
  this.reach = opts.reach

  this.bindEvents()

  this

Mine::bindEvents = ->
  this.reach.on 'mining', (hit_voxel) =>
    if not hit_voxel?
      console.log("no block mined")
      return

    # TODO: show destroy stage overlay
    this.progress += 1

    # TODO: variable hardness based on block type
    if this.instaMine || this.progress > this.opts.defaultHardness
      # TODO: reset this.progress if mouse released
      this.progress = 0

      this.emit 'break', hit_voxel

inherits Mine, EventEmitter
