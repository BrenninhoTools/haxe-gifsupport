package;

import gifsupport.Gif;
import gifsupport.GifEncoder;
import gifsupport.GifException;
import gifsupport.GifFrame;
import gifsupport.GifPlayback;
import haxe.crypto.Base64;
import haxe.crypto.Crc32;
import haxe.io.Bytes;

class Main
{
	static inline var FIXTURE = "R0lGODlhGAASAIEAAAAAAP8AHhTIWgAAACH/C05FVFNDQVBFMi4wAwECAAAh+QQJCAAAACwAAAAAGAASAAAIVwABCBxIsKDBgwgTDgzAsGFDhQUdSoRIUKJDigstMsQoUOPGgQJChjToMQBIkSIjehSIsmXFlS1jZtQIIKbLjjBtpsRJU+dOiD5HYvTJkaXMokZ/IoUYEAAh+QQJDAAAACwAAAAAGAASAIEAAAAUyFr/PB4AAAAIUQABCBxIsKDBgwgTHhTAsGFDhQUdSoRIUKJDigMtPsQIQCPDACBBKvQYsmRCjSVTIrSYsuVCiS1VGmQZM+RLhzVtUswpEmNOjgJjAh0ocyjFgAAh+QQJAAAAACwAAAAAGAASAIEAAAAUyFr/eB4AAAAITwABCBxIsKDBgwgTKgQgoKFDhwsJPpwYceDEhxUFXoSYcWKAjx87OgRJsuJIkiUXNkTJUqUAlihdwkyZcOXMkBFv4sw5M6NAmD4HxgxaMSAAIfkECQYAAAAsAAAAABgAEgCBAAAAFMha/7QeAAAACEsAAQgcSLCgwYMIEyosKKChQ4cLCT6cGHHgxIcVBV6EmFFAgI8fOVYESbJhRpIoBYxEiXIlS5AuXwaI+ZImy5MyMwqsqXMnyZ4ZAwIAOw==";
	static var FIXTURE_CRCS = [-885201294, -1660773345, -659674042, -666809261];
	static var FIXTURE_DELAYS = [80, 120, 100, 60];

	static var failures = 0;
	static var checks = 0;

	static function main()
	{
		testFixture();
		testExactRoundTrip();
		testQuantizedRoundTrip();
		testInvalidData();
		testPlayback();

		Sys.println('$checks checks, $failures failures');
		if (failures > 0)
			Sys.exit(1);
	}

	static function check(condition:Bool, message:String)
	{
		checks++;
		if (!condition)
		{
			failures++;
			Sys.println('FAIL: $message');
		}
	}

	static function normalizedCrc(pixels:Bytes):Int
	{
		var copy = pixels.sub(0, pixels.length);
		var position = 0;
		while (position < copy.length)
		{
			if (copy.get(position + 3) == 0)
			{
				copy.set(position, 0);
				copy.set(position + 1, 0);
				copy.set(position + 2, 0);
			}
			position += 4;
		}
		return Crc32.make(copy);
	}

	static function testFixture()
	{
		var gif = Gif.fromBytes(Base64.decode(FIXTURE));
		check(gif.width == 24 && gif.height == 18, 'fixture size ${gif.width}x${gif.height}');
		check(gif.loopCount == 2, 'fixture loop ${gif.loopCount}');
		check(gif.playCount == 3, 'fixture play count ${gif.playCount}');
		check(gif.numFrames == 4, 'fixture frames ${gif.numFrames}');

		for (i in 0...gif.numFrames)
		{
			check(normalizedCrc(gif.frames[i].pixels) == FIXTURE_CRCS[i], 'fixture frame $i pixels');
			check(gif.frames[i].delay == FIXTURE_DELAYS[i], 'fixture frame $i delay ${gif.frames[i].delay}');
		}
	}

	static function makeFrame(width:Int, height:Int, seed:Int, transparent:Bool):Bytes
	{
		var pixels = Bytes.alloc(width * height * 4);
		for (y in 0...height)
		{
			for (x in 0...width)
			{
				var position = (y * width + x) * 4;
				var band = Std.int((x + seed * 3) / 5) % 6;
				pixels.set(position, band * 40);
				pixels.set(position + 1, (Std.int(y / 4) * 30 + seed * 10) & 0xFF);
				pixels.set(position + 2, 255 - band * 20);
				pixels.set(position + 3, transparent && (x + y + seed) % 7 == 0 ? 0 : 255);
			}
		}
		return pixels;
	}

	static function sameVisible(a:Bytes, b:Bytes):Bool
	{
		if (a.length != b.length)
			return false;
		var position = 0;
		while (position < a.length)
		{
			var visibleA = a.get(position + 3) >= 128;
			var visibleB = b.get(position + 3) > 0;
			if (visibleA != visibleB)
				return false;
			if (visibleA && (a.get(position) != b.get(position) || a.get(position + 1) != b.get(position + 1) || a.get(position + 2) != b.get(position + 2)))
				return false;
			position += 4;
		}
		return true;
	}

	static function testExactRoundTrip()
	{
		var width = 40;
		var height = 30;
		var source = [for (i in 0...5) makeFrame(width, height, i, i % 2 == 0)];

		var encoder = new GifEncoder(width, height, 0);
		for (i in 0...source.length)
			encoder.addFrame(source[i], 50 + i * 10);
		var bytes = encoder.finish();

		check(Gif.isGif(bytes), "encoded output has GIF header");

		var gif = Gif.fromBytes(bytes);
		check(gif.width == width && gif.height == height, "exact round trip size");
		check(gif.loopCount == 0 && gif.playCount == 0, "exact round trip infinite loop");
		check(gif.numFrames == source.length, "exact round trip frame count");

		for (i in 0...source.length)
		{
			check(sameVisible(source[i], gif.frames[i].pixels), 'exact round trip frame $i pixels');
			check(gif.frames[i].delay == 50 + i * 10, 'exact round trip frame $i delay');
		}

		var again = Gif.fromBytes(gif.encode());
		for (i in 0...source.length)
			check(sameVisible(gif.frames[i].pixels, again.frames[i].pixels), 're-encode frame $i pixels');
	}

	static function testQuantizedRoundTrip()
	{
		var width = 200;
		var height = 150;
		var pixels = Bytes.alloc(width * height * 4);
		var state = 12345;
		for (i in 0...width * height)
		{
			for (c in 0...4)
			{
				state = (state * 25173 + 13849) & 0xFFFF;
				pixels.set(i * 4 + c, c == 3 ? ((state >> 8) % 10 == 0 ? 0 : 255) : (state >> 8));
			}
		}

		var bytes = new GifEncoder(width, height, -1).addFrame(pixels, 0).finish();
		var gif = Gif.fromBytes(bytes);
		check(gif.loopCount == -1 && gif.playCount == 1, "quantized no loop extension");
		check(gif.frames[0].delay == 100, 'quantized zero delay normalized ${gif.frames[0].delay}');

		var alphaMatches = true;
		var error = 0.0;
		var visible = 0;
		for (i in 0...width * height)
		{
			var a = pixels.get(i * 4 + 3) >= 128;
			var b = gif.frames[0].pixels.get(i * 4 + 3) > 0;
			if (a != b)
				alphaMatches = false;
			if (a)
			{
				for (c in 0...3)
					error += Math.abs(pixels.get(i * 4 + c) - gif.frames[0].pixels.get(i * 4 + c));
				visible++;
			}
		}
		check(alphaMatches, "quantized alpha matches");
		check(error / (visible * 3) < 20, 'quantized mean error ${error / (visible * 3)}');
	}

	static function testInvalidData()
	{
		var thrown = false;
		try
		{
			Gif.fromBytes(Bytes.ofString("not a gif at all"));
		}
		catch (e:GifException)
		{
			thrown = true;
		}
		check(thrown, "invalid data throws GifException");

		var truncated = Base64.decode(FIXTURE);
		var gif = Gif.fromBytes(truncated.sub(0, Std.int(truncated.length * 0.6)));
		check(gif.numFrames >= 1, "truncated GIF still decodes available frames");
	}

	static function testPlayback()
	{
		var frames = [for (i in 0...3) new GifFrame(Bytes.alloc(4), 100)];
		var playback = new GifPlayback(Gif.fromFrames(1, 1, frames, 1));
		var completed = false;
		playback.onComplete = function() completed = true;
		playback.play();

		playback.update(50);
		check(playback.frame == 0, "playback stays on first frame");
		playback.update(60);
		check(playback.frame == 1, "playback advances");
		playback.update(200);
		check(playback.frame == 0 && playback.completedLoops == 1, "playback loops");
		playback.update(300);
		check(completed && playback.finished && playback.frame == 2, "playback finishes after play count");

		var gif = Gif.fromFrames(1, 1, frames, 0);
		check(gif.getFrameIndexAt(250) == 2, "frame index at time");
		check(gif.getFrameIndexAt(310) == 0, "frame index wraps");
	}
}
