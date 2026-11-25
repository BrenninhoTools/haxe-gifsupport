# haxe-gifsupport

A Haxe/C++ library to support GIF files for projects that use Haxe.

- Decodes static and animated GIFs (GIF87a and GIF89a) into fully composited RGBA frames
- Reads comments, background color, pixel aspect ratio and per-frame regions
- Probes GIF info without decoding pixels, or decodes only the first frames
- Encodes RGBA frames into animated GIFs, with automatic palette generation and transparency
- Frame difference optimization, Floyd-Steinberg dithering and comment writing
- Slice, reverse, crop, resize and speed up animations
- Sprite sheet export with Sparrow XML and JSON atlases
- Native C++ backend on hxcpp targets (Windows, Linux, macOS, Android, iOS)
- Pure Haxe fallback for every other target (HTML5, HashLink, Neko, JS, interp)
- Ready-to-use OpenFL `Bitmap` and HaxeFlixel `FlxSprite` players
- No external dependencies

## Installation

```bash
haxelib git haxe-gifsupport https://github.com/BrenninhoTools/haxe-gifsupport
```

Lime/OpenFL/Flixel projects:

```xml
<haxelib name="haxe-gifsupport" />
```

Plain Haxe projects:

```hxml
-lib haxe-gifsupport
```

## Usage

### Decoding

```haxe
import gifsupport.Gif;

var gif = Gif.fromBytes(bytes);
var gif = Gif.fromFile("assets/images/dance.gif");

var info = '${gif.width}x${gif.height}, ${gif.numFrames} frames, ${gif.duration} ms';

for (frame in gif.frames)
{
	var rgba = frame.pixels;
	var delay = frame.delay;
}
```

Every frame is a full `width * height * 4` RGBA buffer with disposal, transparency, interlacing and frame offsets already applied, so any frame can be displayed directly.

| Field | Description |
| --- | --- |
| `width`, `height` | Canvas size |
| `frames` | `Array<GifFrame>` with `pixels` (RGBA `Bytes`), `delay` (ms), `disposal`, and the raw frame region `x`, `y`, `regionWidth`, `regionHeight`, `interlaced` |
| `loopCount` | Raw NETSCAPE loop value: `-1` no extension, `0` infinite, `n` extra loops |
| `playCount` | Total plays: `0` infinite, otherwise how many times the animation runs |
| `duration` | Sum of all frame delays in ms |
| `averageFrameRate` | Frames per second based on the total duration |
| `version` | `"GIF87a"` or `"GIF89a"` |
| `comments` | Text from comment extensions |
| `backgroundColor` | ARGB background color from the global palette, `-1` when missing |
| `pixelAspectRatio` | Pixel aspect ratio, `0` when unspecified |
| `getFrameAt(time)` | Frame shown at a given time in ms, respecting the play count |

### Probing and partial decoding

```haxe
var info = Gif.probe(bytes);
var memory = info.decodedSize;

var preview = Gif.firstFrame(bytes);
var intro = Gif.fromBytes(bytes, 10);
```

`Gif.probe` reads size, frame count, loop count, duration and comments without decompressing any pixels, so it is cheap even for huge files. `Gif.fromBytes(bytes, maxFrames)` stops after `maxFrames` frames, which is useful for thumbnails and previews.

Frame delays follow browser behavior: delays of 10 ms or less are played as 100 ms.

### Encoding

```haxe
import gifsupport.GifEncoder;

var encoder = new GifEncoder(320, 240);
encoder.addFrame(frameA, 100);
encoder.addFrame(frameB, 100);
var bytes = encoder.finish();
```

`loopCount` defaults to `0` (loop forever); pass `-1` for a GIF that plays once. Frames with up to 256 colors are stored losslessly, frames with more colors are quantized with median cut.

```haxe
var encoder = new GifEncoder(320, 240, 0, {optimize: true, dither: true, alphaThreshold: 128});
encoder.addComment("Made with haxe-gifsupport");
```

| Option | Default | Description |
| --- | --- | --- |
| `optimize` | `true` | Stores only the changed rectangle of each frame and reuses unchanged pixels, which makes most animations much smaller |
| `dither` | `false` | Floyd-Steinberg dithering when a frame has more than 256 colors |
| `alphaThreshold` | `128` | Pixels with alpha below this value become transparent |

A decoded `Gif` can be re-encoded with `gif.encode(options)` or `gif.save(path, options)`, comments included.

### Editing

```haxe
var clip = gif.slice(2, 8);
var backwards = gif.reverse();
var faster = gif.withSpeed(2);
var face = gif.crop(10, 10, 64, 64);
var small = gif.resize(160, 120);
```

Every method returns a new `Gif` and keeps the loop count and comments.

### Sprite sheets

```haxe
var sheet = gif.toSpriteSheet(4, 1);
var xml = sheet.toSparrowXml("dance.png", "dance");
var json = sheet.toJson("dance.png", "dance");
```

`toSpriteSheet(columns, padding)` packs every frame into a single RGBA image; with `columns = 0` the grid is chosen automatically. `sheet.pixels` holds the image, `sheet.frames` the position and delay of each frame, and `sheet.frameRate` the average frame rate. The Sparrow XML works with Friday Night Funkin' style `FlxAtlasFrames.fromSparrow`, the JSON uses the TexturePacker/Aseprite array format with per-frame `duration`.

### OpenFL

```haxe
import gifsupport.openfl.GifBitmap;

var bitmap = GifBitmap.fromAsset("assets/images/dance.gif");
addChild(bitmap);

bitmap.pause();
bitmap.play();
bitmap.gotoFrame(3);
bitmap.addEventListener(Event.COMPLETE, onDone);
```

`GifBitmap.toBitmapData(gif, index)` converts a single frame to `BitmapData`, `GifBitmap.spriteSheetToBitmapData(sheet)` converts a sprite sheet and `GifBitmap.rgbaToBitmapData(pixels, width, height)` converts any RGBA buffer.

### HaxeFlixel

```haxe
import gifsupport.flixel.FlxGifSprite;

var sprite = new FlxGifSprite(100, 100);
sprite.loadGifAsset("assets/images/dance.gif");
add(sprite);

sprite.playback.speed = 2;
sprite.onGifComplete = () -> sprite.kill();
```

Works with Flixel 5 and 6. Methods: `loadGif`, `loadGifBytes`, `loadGifAsset`, `loadGifFile`, `playGif`, `pauseGif`, `stopGif`, `gotoGifFrame`.

`FlxGifSprite` keeps the exact delay of every frame. To use a GIF as a regular Flixel animation backed by a single texture, use `FlxGifAtlas`:

```haxe
import gifsupport.flixel.FlxGifAtlas;

var sprite = new FlxSprite();
FlxGifAtlas.loadGifAsset(sprite, "assets/images/dance.gif", "dance");

var frames = FlxGifAtlas.framesFromGif(gif, "dance");
```

The animation plays at the GIF average frame rate unless `frameRate` is passed, and loops unless the GIF plays only once.

### Playback without a framework

```haxe
var playback = new GifPlayback(gif);
playback.play();

if (playback.update(elapsedMs))
	draw(gif.frames[playback.frame]);
```

## Backends

| Target | Backend |
| --- | --- |
| hxcpp (Windows, Linux, macOS, Android, iOS) | Native C++ (`project/src`) |
| Everything else | Pure Haxe (`gifsupport.backend`) |

Define `gifsupport_pure_haxe` to force the Haxe backend on hxcpp.

The C++ sources live in `project/` and are compiled into the hxcpp build automatically through `project/Build.xml`, no extra setup or prebuilt binaries are needed.

## Limits

- Canvas size is capped at 67,108,864 pixels per frame
- All frames are kept decoded in memory, so very long or very large animations use `width * height * 4 * frames` bytes

## Tests

```bash
haxelib dev haxe-gifsupport .
haxe test/cpp.hxml && ./bin/cpp/Main
haxe test/cpp-pure.hxml && ./bin/cpp-pure/Main
haxe test/neko.hxml && neko bin/test.n
haxe test/js.hxml && node bin/test.js
haxe test/interp.hxml
```

## License

MIT
