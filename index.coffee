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
    this.drawDamage(hit_voxel)

    # TODO: variable hardness based on block type
    if this.instaMine || this.progress > this.opts.defaultHardness
      # TODO: reset this.progress if mouse released
      this.progress = 0

      this.emit 'break', hit_voxel

Mine::drawDamage = (at) ->
  geometry = new this.game.THREE.CubeGeometry(1, 1, 1)
  material = new this.game.THREE.MeshLambertMaterial() # TODO: destroy_stage_N
  mesh = new this.game.THREE.Mesh(geometry, material)
  obj = new game.THREE.Object3D()

  obj.add(mesh)
  obj.position.set(at[0] + 0.5, at[1] + 0.5, at[2] + 0.5)
  
  cube = game.addItem({mesh: obj, size: 1})

inherits Mine, EventEmitter
