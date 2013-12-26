# voxel-mine

An addon for voxel.js to mine blocks of variable hardness. Hold down the left mouse button to mine:

![screenshot](http://imgur.com/s5wbWic.png "Screenshot mining")

Hardness can be set for each block type (controls how long it takes to mine).
As the mining progresses, damage overlay textures (not included, example is from [ProgrammerArt](https://github.com/deathcap/ProgrammerArt)) are shown:

![screenshot](http://imgur.com/ywjWFxF.png "Screenshot progress more")

The 'break' event is sent when the mining completes. You can listen to this event
and `setBlock` to 0 to remove the block, or use 
[voxel-harvest](https://github.com/deathcap/voxel-harvest) to do this for you and
add an item representing the block to a (player's) inventory, therefore "harvesting" 
the mined block. voxel-mine doesn't harvest the blocks automatically, it merely sends
an event when the mining process is complete, to be handled appropriately by other code.

## Usage

    var createMine = require('voxel-mine');
    var mine = createMine(game, opts);
    
    mine.on('break', function(target) {
      // do something to this voxel (remove it, etc.)
    });

or with [voxel-plugins](https://github.com/deathcap/voxel-plugins):

    plugins.load('mine', opts);

see source for supported/required options

Requires [voxel-reach](https://github.com/deathcap/voxel-reach)


## License

MIT

