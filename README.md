# haxe-gifsupport

A Haxe/C++ library to support GIF files for projects that use Haxe.

- Decodes static and animated GIFs (GIF87a and GIF89a) into fully composited RGBA frames
- Encodes RGBA frames into animated GIFs, with automatic palette generation and transparency
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
| `frames` | `Array<GifFrame>` with `pixels` (RGBA `Bytes`), `delay` (ms) and `disposal` |
| `loopCount` | Raw NETSCAPE loop value: `-1` no extension, `0` infinite, `n` extra loops |
| `playCount` | Total plays: `0` infinite, otherwise how many times the animation runs |
| `duration` | Sum of all frame delays in ms |
| `getFrameAt(time)` | Frame shown at a given time in ms, respecting the play count |

Frame delays follow browser behavior: delays of 10 ms or less are played as 100 ms.

### Encoding

```haxe
import gifsupport.GifEncoder;

var encoder = new GifEncoder(320, 240);
encoder.addFrame(frameA, 100);
encoder.addFrame(frameB, 100);
var bytes = encoder.finish();
```

`loopCount` defaults to `0` (loop forever); pass `-1` for a GIF that plays once. Frames with up to 256 colors are stored losslessly, frames with more colors are quantized with median cut. Pixels with alpha below 128 become transparent.

A decoded `Gif` can be re-encoded with `gif.encode()` or `gif.save(path)`.

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

`GifBitmap.toBitmapData(gif, index)` converts a single frame to `BitmapData`.

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
