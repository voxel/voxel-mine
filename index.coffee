# vim: set shiftwidth=2 tabstop=2 softtabstop=2 expandtab:

inherits = require 'inherits'
EventEmitter = (require 'events').EventEmitter

module.exports = (game, opts) ->
  return new Mine(game, opts)

Mine = (game, opts) ->
  this.game = game
  opts = opts ? {}
  opts.defaultHardness ?= 9
  opts.instaMine ?= false
  opts.progressTexturesBase ?= undefined
  opts.progressTexturesExt ?= ".png"
  opts.progressTexturesCount ?= 9

  opts.applyTextureParams ?= (texture) =>
    texture.magFilter = this.game.THREE.NearestFilter
    texture.minFilter = this.game.THREE.LinearMipMapLinearFilter
    texture.wrapT = this.game.THREE.RepeatWrapping
    texture.wrapS = this.game.THREE.RepeatWrapping

  if !opts.reach?
    throw "voxel-mine requires 'reach' option set to voxel-reach instance"

  this.opts = opts

  this.instaMine = opts.instaMine
  this.progress = 0
  this.reach = opts.reach

  this.texturesEnabled = this.opts.progressTexturesBase?
  this.overlay = null
  this.setupTextures()
  this.bindEvents()

  this

Mine::setupTextures = ->
  if not this.texturesEnabled
    return

  this.progressTextures = []

  for i in [0..this.opts.progressTexturesCount]
    path = this.opts.progressTexturesBase + i + this.opts.progressTexturesExt
    this.progressTextures.push(this.game.THREE.ImageUtils.loadTexture(path))

Mine::getHardness = (target) ->
  # TODO: variable hardness based on block type
  return this.opts.defaultHardness

Mine::bindEvents = ->
  this.reach.on 'mining', (target) =>
    if not target
      console.log("no block mined")
      return

    this.progress += 1

    if this.instaMine || this.progress > this.getHardness(target)
      this.progress = 0
      this.emit 'break', target.voxel

    this.updateForStage()

  this.reach.on 'start mining', (target) =>
    if not target
      return

    this.createOverlay(target)

  this.reach.on 'stop mining', (target) =>
    if not target
      return

    # Reset this.progress if mouse released
    this.destroyOverlay()
    this.progress = 0


Mine::createOverlay = (target) ->
  if this.instaMine or not this.texturesEnabled
    return

  this.destroyOverlay()

  geometry = new this.game.THREE.Geometry()
  # TODO: actually compute this
  if target.normal[2] == 1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 1, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 0))
    offset = [0, 0, 1]
  else if target.normal[1] == 1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 0))
    offset = [0, 1, 0]
  else if target.normal[0] == 1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 1))
    offset = [1, 0, 0]
  else if target.normal[0] == -1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 0))
    offset = [0, 0, 0]
  else if target.normal[1] == -1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 1))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 1))
    offset = [0, 0, 0]
  else if target.normal[2] == -1
    geometry.vertices.push(new this.game.THREE.Vector3(0, 0, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(0, 1, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 1, 0))
    geometry.vertices.push(new this.game.THREE.Vector3(1, 0, 0))
    offset = [0, 0, 0]
  else
    console.log "unknown face", target.normal
    return

  # rectangle geometry, see http://stackoverflow.com/questions/19085369/rendering-custom-geometry-in-three-js
  geometry.faces.push(new this.game.THREE.Face3(0, 1, 2)) # counter-clockwise winding order
  geometry.faces.push(new this.game.THREE.Face3(0, 2, 3))

  geometry.computeCentroids()
  geometry.computeFaceNormals()
  geometry.computeVertexNormals()
  geometry.faceVertexUvs = [
      [
        [
          {x:0, y:0},
          {x:1, y:0},
          {x:1, y:1},
          {x:0, y:1}
        ],
        [
          {x:0, y:0},
          {x:1, y:1},
          {x:1, y:0},
          {x:0, y:1},
        ]
      ]
    ]

  material = new this.game.THREE.MeshLambertMaterial()

  material.map = this.progressTextures[0]
  this.opts.applyTextureParams(material.map)

  material.side = this.game.THREE.FrontSide
  material.transparent = true
  material.polygonOffset = true
  material.polygonOffsetFactor = -1.0
  material.polygonOffsetUnits = -1.0
  mesh = new this.game.THREE.Mesh(geometry, material)
  this.overlay = new this.game.THREE.Object3D()

  this.overlay.add(mesh)
  this.overlay.position.set(target.voxel[0] + offset[0], 
                   target.voxel[1] + offset[1],
                   target.voxel[2] + offset[2])

  this.game.scene.add(this.overlay)

  return this.overlay

# Set overlay texture based on mining progress stage
Mine::updateForStage = () ->
  if not this.texturesEnabled
    return

  index = Math.floor((this.progress / this.getHardness()) * (this.progressTextures.length - 1))
  texture = this.progressTextures[index]

  this.setOverlayTexture(texture)

Mine::setOverlayTexture = (texture) ->
  if not this.overlay or not this.texturesEnabled
    return

  # TODO: destroy_stage_N
  this.opts.applyTextureParams(texture)
  this.overlay.children[0].material.map = texture
  this.overlay.children[0].material.needsUpdate = true

Mine::destroyOverlay = () ->
  if not this.overlay or not this.texturesEnabled
    return

  this.game.scene.remove(this.overlay)
  this.overlay = null

inherits Mine, EventEmitter
