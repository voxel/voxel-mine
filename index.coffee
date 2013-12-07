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
  this.reach.on 'mining', (target) =>
    if not target
      console.log("no block mined")
      return

    this.progress += 1

    # TODO: variable hardness based on block type
    if this.instaMine || this.progress > this.opts.defaultHardness
      # TODO: reset this.progress if mouse released
      this.progress = 0

      this.emit 'break', target.voxel

  this.reach.on 'start mining', (target) =>
    if not target
      return

    console.log "start mining", target
    this.drawDamage(target)

  this.reach.on 'stop mining', (target) =>
    if not target
      return

    console.log "stop mining", target


Mine::drawDamage = (target) ->
  a = {x:0, y:0}
  b = {x:1, y:1}

  # rectangle geometry, see http://stackoverflow.com/questions/19085369/rendering-custom-geometry-in-three-js
  geometry = new this.game.THREE.Geometry()
  geometry.vertices.push(new this.game.THREE.Vector3(a.x, a.y, 0))
  geometry.vertices.push(new this.game.THREE.Vector3(b.x, a.y, 0))
  geometry.vertices.push(new this.game.THREE.Vector3(b.x, b.y, 0))
  geometry.vertices.push(new this.game.THREE.Vector3(a.x, b.y, 0))

  geometry.faces.push(new this.game.THREE.Face3(0, 1, 2)) # counter-clockwise winding order
  geometry.faces.push(new this.game.THREE.Face3(0, 2, 3))

  geometry.computeCentroids()
  geometry.computeFaceNormals()
  geometry.computeVertexNormals()

  material = new this.game.THREE.MeshLambertMaterial() # TODO: destroy_stage_N
  material.side = this.game.THREE.FrontSide
  material.transparent = true
  material.depthWrite = false
  material.depthTest = false
  mesh = new this.game.THREE.Mesh(geometry, material)
  obj = new game.THREE.Object3D()

  obj.add(mesh)
  obj.position.set(target.voxel[0], target.voxel[1], target.voxel[2] + 1) # TODO: side
  
  cube = game.addItem({mesh: obj, size: 1})

inherits Mine, EventEmitter
