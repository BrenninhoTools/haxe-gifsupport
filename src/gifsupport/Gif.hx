package gifsupport;

import haxe.io.Bytes;

class Gif
{
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var loopCount(default, null):Int;
	public var frames(default, null):Array<GifFrame>;
	public var version(default, null):String;
	public var backgroundColor(default, null):Int;
	public var pixelAspectRatio(default, null):Float;
	public var comments(default, null):Array<String>;

	public var numFrames(get, never):Int;
	public var duration(get, never):Int;
	public var playCount(get, never):Int;
	public var animated(get, never):Bool;
	public var averageFrameRate(get, never):Float;

	public function new(width:Int, height:Int, loopCount:Int, frames:Array<GifFrame>, version:String = "GIF89a", backgroundColor:Int = -1,
			pixelAspectRatio:Float = 0, ?comments:Array<String>)
	{
		this.width = width;
		this.height = height;
		this.loopCount = loopCount;
		this.frames = frames;
		this.version = version;
		this.backgroundColor = backgroundColor;
		this.pixelAspectRatio = pixelAspectRatio;
		this.comments = comments == null ? [] : comments;
	}

	public static function fromBytes(bytes:Bytes, maxFrames:Int = 0):Gif
	{
		if (bytes == null || !isGif(bytes))
			throw new GifException("Invalid GIF header");

		if (maxFrames < 0)
			maxFrames = 0;

		#if (cpp && !gifsupport_pure_haxe)
		return gifsupport.backend.NativeBackend.decode(bytes, maxFrames);
		#else
		return gifsupport.backend.HaxeDecoder.decode(bytes, maxFrames);
		#end
	}

	public static function firstFrame(bytes:Bytes):Gif
	{
		return fromBytes(bytes, 1);
	}

	public static function probe(bytes:Bytes):GifInfo
	{
		if (bytes == null || !isGif(bytes))
			throw new GifException("Invalid GIF header");

		var parsed = gifsupport.backend.GifParser.parse(bytes, false, 0);
		var duration = 0;
		for (frame in parsed.frames)
			duration += frame.delay;

		return new GifInfo(parsed.version, parsed.width, parsed.height, parsed.frames.length, parsed.loopCount, duration, parsed.backgroundColor,
			gifsupport.backend.GifParser.aspectRatioToFloat(parsed.aspectRatio), parsed.comments);
	}

	#if sys
	public static function fromFile(path:String, maxFrames:Int = 0):Gif
	{
		return fromBytes(sys.io.File.getBytes(path), maxFrames);
	}

	public static function probeFile(path:String):GifInfo
	{
		return probe(sys.io.File.getBytes(path));
	}
	#end

	public static function isGif(bytes:Bytes):Bool
	{
		if (bytes == null || bytes.length < 6)
			return false;

		var signature = bytes.getString(0, 6);
		return signature == "GIF87a" || signature == "GIF89a";
	}

	public static function fromFrames(width:Int, height:Int, frames:Array<GifFrame>, loopCount:Int = 0):Gif
	{
		var expected = width * height * 4;
		for (frame in frames)
			if (frame.pixels.length != expected)
				throw new GifException('Frame size mismatch, expected $expected bytes but got ${frame.pixels.length}');

		return new Gif(width, height, loopCount, frames);
	}

	public function encode(?options:GifEncoderOptions):Bytes
	{
		var encoder = new GifEncoder(width, height, loopCount, options);
		for (comment in comments)
			encoder.addComment(comment);
		for (frame in frames)
			encoder.addFrame(frame.pixels, frame.delay);
		return encoder.finish();
	}

	#if sys
	public function save(path:String, ?options:GifEncoderOptions):Void
	{
		sys.io.File.saveBytes(path, encode(options));
	}
	#end

	public function getFrameIndexAt(time:Float):Int
	{
		if (frames.length < 2)
			return 0;

		var total = duration;
		if (total <= 0)
			return 0;

		var plays = playCount;
		if (plays > 0 && time >= total * plays)
			return frames.length - 1;

		var local = time % total;
		if (local < 0)
			local += total;

		for (i in 0...frames.length)
		{
			local -= frames[i].delay;
			if (local < 0)
				return i;
		}

		return frames.length - 1;
	}

	public function getFrameAt(time:Float):GifFrame
	{
		return frames[getFrameIndexAt(time)];
	}

	public function slice(start:Int, ?end:Int):Gif
	{
		var selected = frames.slice(start, end == null ? frames.length : end);
		if (selected.length == 0)
			throw new GifException("Slice contains no frames");
		return copyWith(width, height, selected);
	}

	public function reverse():Gif
	{
		var reversed = frames.copy();
		reversed.reverse();
		return copyWith(width, height, reversed);
	}

	public function withSpeed(speed:Float):Gif
	{
		if (speed <= 0)
			throw new GifException('Invalid speed $speed');

		return copyWith(width, height, [
			for (frame in frames)
			{
				var delay = Math.round(frame.delay / speed);
				frame.withDelay(delay < 20 ? 20 : delay);
			}
		]);
	}

	public function crop(x:Int, y:Int, cropWidth:Int, cropHeight:Int):Gif
	{
		if (x < 0 || y < 0 || cropWidth <= 0 || cropHeight <= 0 || x + cropWidth > width || y + cropHeight > height)
			throw new GifException('Invalid crop rectangle $x,$y ${cropWidth}x$cropHeight');

		var result = new Array<GifFrame>();
		for (frame in frames)
		{
			var pixels = Bytes.alloc(cropWidth * cropHeight * 4);
			for (row in 0...cropHeight)
				pixels.blit(row * cropWidth * 4, frame.pixels, ((y + row) * width + x) * 4, cropWidth * 4);
			result.push(new GifFrame(pixels, frame.delay, frame.disposal, 0, 0, cropWidth, cropHeight));
		}
		return copyWith(cropWidth, cropHeight, result);
	}

	public function resize(newWidth:Int, newHeight:Int):Gif
	{
		if (newWidth <= 0 || newHeight <= 0 || newWidth > 65535 || newHeight > 65535)
			throw new GifException('Invalid size ${newWidth}x$newHeight');

		var sourceX = [for (x in 0...newWidth) Std.int(x * width / newWidth)];
		var sourceY = [for (y in 0...newHeight) Std.int(y * height / newHeight)];
		var result = new Array<GifFrame>();

		for (frame in frames)
		{
			var pixels = Bytes.alloc(newWidth * newHeight * 4);
			var source = frame.pixels;
			var target = 0;
			for (y in 0...newHeight)
			{
				var rowStart = sourceY[y] * width;
				for (x in 0...newWidth)
				{
					var position = (rowStart + sourceX[x]) * 4;
					pixels.set(target, source.get(position));
					pixels.set(target + 1, source.get(position + 1));
					pixels.set(target + 2, source.get(position + 2));
					pixels.set(target + 3, source.get(position + 3));
					target += 4;
				}
			}
			result.push(new GifFrame(pixels, frame.delay, frame.disposal, 0, 0, newWidth, newHeight));
		}
		return copyWith(newWidth, newHeight, result);
	}

	public function toSpriteSheet(columns:Int = 0, padding:Int = 0):GifSpriteSheet
	{
		return GifSpriteSheet.fromGif(this, columns, padding);
	}

	function copyWith(newWidth:Int, newHeight:Int, newFrames:Array<GifFrame>):Gif
	{
		return new Gif(newWidth, newHeight, loopCount, newFrames, version, backgroundColor, pixelAspectRatio, comments.copy());
	}

	function get_numFrames():Int
	{
		return frames.length;
	}

	function get_duration():Int
	{
		var total = 0;
		for (frame in frames)
			total += frame.delay;
		return total;
	}

	function get_playCount():Int
	{
		if (loopCount < 0)
			return 1;
		if (loopCount == 0)
			return 0;
		return loopCount + 1;
	}

	function get_animated():Bool
	{
		return frames.length > 1;
	}

	function get_averageFrameRate():Float
	{
		var total = duration;
		return total <= 0 ? 0 : frames.length * 1000 / total;
	}
}
