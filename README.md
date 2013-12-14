# voxel-mine

An addon for voxel.js to mine blocks of variable hardness. Hold down the left mouse button to mine:

![screenshot](http://imgur.com/s5wbWic.png "Screenshot mining")

Hardness can be set for each block type (controls how long it takes to mine).
As the mining progresses, damage overlay textures (not included, example is from [ProgrammerArt](https://github.com/deathcap/ProgrammerArt)) are shown:

![screenshot](http://imgur.com/ywjWFxF.png "Screenshot progress more")

## Usage

    var createMine = require('voxel-mine');
    var mine = createMine(game, opts);
    
    mine.on('break', function(target) {
      // harvest the block
    });

or with [voxel-plugins](https://github.com/deathcap/voxel-plugins):

    plugins.load('mine', opts);

see source for supported options

Requires [voxel-reach](https://github.com/deathcap/voxel-reach)


## License

MIT

