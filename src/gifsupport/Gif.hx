package gifsupport;

import haxe.io.Bytes;

class Gif
{
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var loopCount(default, null):Int;
	public var frames(default, null):Array<GifFrame>;

	public var numFrames(get, never):Int;
	public var duration(get, never):Int;
	public var playCount(get, never):Int;
	public var animated(get, never):Bool;

	public function new(width:Int, height:Int, loopCount:Int, frames:Array<GifFrame>)
	{
		this.width = width;
		this.height = height;
		this.loopCount = loopCount;
		this.frames = frames;
	}

	public static function fromBytes(bytes:Bytes):Gif
	{
		if (bytes == null || !isGif(bytes))
			throw new GifException("Invalid GIF header");

		#if (cpp && !gifsupport_pure_haxe)
		return gifsupport.backend.NativeBackend.decode(bytes);
		#else
		return gifsupport.backend.HaxeDecoder.decode(bytes);
		#end
	}

	#if sys
	public static function fromFile(path:String):Gif
	{
		return fromBytes(sys.io.File.getBytes(path));
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

	public function encode():Bytes
	{
		var encoder = new GifEncoder(width, height, loopCount);
		for (frame in frames)
			encoder.addFrame(frame.pixels, frame.delay);
		return encoder.finish();
	}

	#if sys
	public function save(path:String):Void
	{
		sys.io.File.saveBytes(path, encode());
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
}
