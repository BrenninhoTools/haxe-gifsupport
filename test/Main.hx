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
		testMetadata();
		testOptimizer();
		testDither();
		testUtilities();

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

	static function testMetadata()
	{
		var fixture = Base64.decode(FIXTURE);
		var gif = Gif.fromBytes(fixture);
		check(gif.version == "GIF89a", 'fixture version ${gif.version}');
		check(gif.backgroundColor == 0xFF000000, 'fixture background ${gif.backgroundColor}');
		check(gif.pixelAspectRatio == 0, "fixture aspect unspecified");
		check(gif.frames[0].regionWidth == 24 && gif.frames[0].regionHeight == 18, "fixture frame region");

		var patched = fixture.sub(0, fixture.length);
		patched.set(12, 49);
		check(Gif.fromBytes(patched).pixelAspectRatio == 1, "patched aspect ratio");

		var info = Gif.probe(fixture);
		check(info.width == 24 && info.height == 18, "probe size");
		check(info.numFrames == 4 && info.animated, 'probe frames ${info.numFrames}');
		check(info.loopCount == 2 && info.playCount == 3, "probe loop");
		check(info.duration == gif.duration, 'probe duration ${info.duration}');
		check(info.decodedSize == 24 * 18 * 4 * 4, "probe decoded size");

		var limited = Gif.fromBytes(fixture, 2);
		check(limited.numFrames == 2, 'max frames ${limited.numFrames}');
		check(normalizedCrc(limited.frames[1].pixels) == FIXTURE_CRCS[1], "max frames pixels");
		check(Gif.firstFrame(fixture).numFrames == 1, "first frame only");

		var frame = makeFrame(16, 16, 1, false);
		var encoded = new GifEncoder(16, 16).addComment("hello gif").addFrame(frame).addComment("é ünïcode").addFrame(makeFrame(16, 16, 2, false)).finish();
		var decoded = Gif.fromBytes(encoded);
		check(decoded.comments.length == 2, 'comment count ${decoded.comments.length}');
		check(decoded.comments[0] == "hello gif" && decoded.comments[1] == "é ünïcode", 'comments ${decoded.comments}');
		check(Gif.probe(encoded).comments.length == 2, "probe comments");

		var long = StringTools.lpad("", "x", 700);
		var reencoded = Gif.fromBytes(new GifEncoder(16, 16).addComment(long).addFrame(frame).finish());
		check(reencoded.comments[0] == long, "long comment split into sub-blocks");
		check(Gif.fromBytes(reencoded.encode()).comments[0] == long, "comments survive re-encode");
	}

	static function testOptimizer()
	{
		var width = 64;
		var height = 48;
		var base = makeFrame(width, height, 0, false);
		var source = new Array<Bytes>();
		for (i in 0...6)
		{
			var frame = base.sub(0, base.length);
			for (y in 10...18)
				for (x in 0...8)
				{
					var position = (y * width + x + i * 6) * 4;
					frame.set(position, 255);
					frame.set(position + 1, 255);
					frame.set(position + 2, 0);
				}
			source.push(frame);
		}

		var optimized = new GifEncoder(width, height);
		var plain = new GifEncoder(width, height, 0, {optimize: false});
		for (frame in source)
		{
			optimized.addFrame(frame, 80);
			plain.addFrame(frame, 80);
		}
		var optimizedBytes = optimized.finish();
		var plainBytes = plain.finish();
		check(optimizedBytes.length < plainBytes.length, 'optimized ${optimizedBytes.length} < plain ${plainBytes.length}');

		var gif = Gif.fromBytes(optimizedBytes);
		check(gif.numFrames == source.length, "optimized frame count");
		for (i in 0...source.length)
			check(sameVisible(source[i], gif.frames[i].pixels), 'optimized frame $i pixels');
		check(gif.frames[1].regionWidth < width && gif.frames[1].regionHeight < height, 'optimized region ${gif.frames[1].regionWidth}x${gif.frames[1].regionHeight}');

		var still = new GifEncoder(8, 8).addFrame(makeFrame(8, 8, 3, false)).addFrame(makeFrame(8, 8, 3, false)).finish();
		var stillGif = Gif.fromBytes(still);
		check(stillGif.numFrames == 2 && sameVisible(stillGif.frames[0].pixels, stillGif.frames[1].pixels), "identical frames");

		var empty = Bytes.alloc(8 * 8 * 4);
		empty.fill(0, empty.length, 0);
		var vanish = Gif.fromBytes(new GifEncoder(8, 8).addFrame(makeFrame(8, 8, 1, false)).addFrame(empty).addFrame(makeFrame(8, 8, 2, true)).finish());
		check(sameVisible(empty, vanish.frames[1].pixels), "frame clears to transparent");
		check(sameVisible(makeFrame(8, 8, 2, true), vanish.frames[2].pixels), "frame after clear");

		var soft = Bytes.alloc(4);
		soft.set(3, 100);
		var lowThreshold = Gif.fromBytes(new GifEncoder(1, 1, 0, {alphaThreshold: 50}).addFrame(soft).finish());
		check(lowThreshold.frames[0].pixels.get(3) == 255, "alpha threshold keeps pixel");
		var highThreshold = Gif.fromBytes(new GifEncoder(1, 1).addFrame(soft).finish());
		check(highThreshold.frames[0].pixels.get(3) == 0, "default threshold drops pixel");
	}

	static function testDither()
	{
		var width = 128;
		var height = 64;
		var pixels = Bytes.alloc(width * height * 4);
		for (y in 0...height)
			for (x in 0...width)
			{
				var position = (y * width + x) * 4;
				pixels.set(position, x * 2);
				pixels.set(position + 1, y * 4);
				pixels.set(position + 2, (x + y) & 0xFF);
				pixels.set(position + 3, x < 4 ? 0 : 255);
			}

		var gif = Gif.fromBytes(new GifEncoder(width, height, 0, {dither: true}).addFrame(pixels).finish());
		var alphaMatches = true;
		var error = 0.0;
		var visible = 0;
		for (i in 0...width * height)
		{
			var a = pixels.get(i * 4 + 3) >= 128;
			if (a != (gif.frames[0].pixels.get(i * 4 + 3) > 0))
				alphaMatches = false;
			if (a)
			{
				for (c in 0...3)
					error += Math.abs(pixels.get(i * 4 + c) - gif.frames[0].pixels.get(i * 4 + c));
				visible++;
			}
		}
		check(alphaMatches, "dither alpha matches");
		check(error / (visible * 3) < 20, 'dither mean error ${error / (visible * 3)}');
	}

	static function testUtilities()
	{
		var gif = Gif.fromBytes(Base64.decode(FIXTURE));

		var sliced = gif.slice(1, 3);
		check(sliced.numFrames == 2 && normalizedCrc(sliced.frames[0].pixels) == FIXTURE_CRCS[1], "slice");
		check(sliced.loopCount == gif.loopCount, "slice keeps loop");

		var reversed = gif.reverse();
		check(normalizedCrc(reversed.frames[0].pixels) == FIXTURE_CRCS[3] && reversed.frames[3] == gif.frames[0], "reverse");

		var faster = gif.withSpeed(2);
		check(faster.frames[1].delay == 60, 'speed ${faster.frames[1].delay}');
		check(gif.withSpeed(100).frames[0].delay == 20, "speed minimum delay");

		var cropped = gif.crop(4, 2, 10, 8);
		check(cropped.width == 10 && cropped.height == 8 && cropped.frames[0].pixels.length == 320, "crop size");
		check(cropped.frames[2].getPixel(10, 3, 5) == gif.frames[2].getPixel(24, 7, 7), "crop pixel");

		var resized = gif.resize(48, 36);
		check(resized.width == 48 && resized.height == 36, "resize size");
		check(resized.frames[1].getPixel(48, 21, 13) == gif.frames[1].getPixel(24, 10, 6), "resize pixel");
		check(Gif.fromBytes(resized.encode()).numFrames == 4, "resized encodes");

		var sheet = gif.toSpriteSheet(2, 1);
		check(sheet.columns == 2 && sheet.rows == 2, "sheet grid");
		check(sheet.width == 49 && sheet.height == 37, 'sheet size ${sheet.width}x${sheet.height}');
		check(sheet.frames[3].x == 25 && sheet.frames[3].y == 19, "sheet frame position");
		var sheetPixel = sheet.pixels.getInt32(((19 + 5) * sheet.width + 25 + 7) * 4);
		check(sheetPixel == gif.frames[3].pixels.getInt32((5 * 24 + 7) * 4), "sheet pixel");

		var xml = Xml.parse(sheet.toSparrowXml("dance.png", "dance")).firstElement();
		var subTextures = [for (node in xml.elementsNamed("SubTexture")) node];
		check(xml.get("imagePath") == "dance.png" && subTextures.length == 4, "sparrow xml");
		check(subTextures[3].get("name") == "dance0003" && subTextures[3].get("x") == "25", "sparrow frame");

		var json:Dynamic = haxe.Json.parse(sheet.toJson("dance.png"));
		check(json.frames.length == 4 && json.frames[1].duration == 120, "sheet json");

		var auto = gif.toSpriteSheet();
		check(auto.columns * auto.rows >= 4, "auto columns");
	}
}
