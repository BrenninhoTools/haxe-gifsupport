package gifsupport;

import haxe.io.Bytes;

class GifEncoder
{
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var loopCount(default, null):Int;
	public var frameCount(default, null):Int = 0;
	public var finished(default, null):Bool = false;

	#if (cpp && !gifsupport_pure_haxe)
	var backend:gifsupport.backend.NativeBackend.NativeEncoderHandle;
	#else
	var backend:gifsupport.backend.HaxeEncoder;
	#end

	public function new(width:Int, height:Int, loopCount:Int = 0)
	{
		if (width <= 0 || height <= 0 || width > 65535 || height > 65535)
			throw new GifException('Invalid GIF dimensions ${width}x$height');

		this.width = width;
		this.height = height;
		this.loopCount = loopCount < 0 ? -1 : (loopCount > 65535 ? 65535 : loopCount);

		#if (cpp && !gifsupport_pure_haxe)
		backend = new gifsupport.backend.NativeBackend.NativeEncoderHandle(width, height, this.loopCount);
		#else
		backend = new gifsupport.backend.HaxeEncoder(width, height, this.loopCount);
		#end
	}

	public function addFrame(pixels:Bytes, delay:Int = 100):GifEncoder
	{
		if (finished)
			throw new GifException("Encoder already finished");

		var expected = width * height * 4;
		if (pixels == null || pixels.length < expected)
			throw new GifException('Frame size mismatch, expected $expected bytes');

		backend.addFrame(pixels, delay < 0 ? 0 : delay);
		frameCount++;
		return this;
	}

	public function addGifFrame(frame:GifFrame):GifEncoder
	{
		return addFrame(frame.pixels, frame.delay);
	}

	public function finish():Bytes
	{
		if (finished)
			throw new GifException("Encoder already finished");

		if (frameCount == 0)
			throw new GifException("Cannot finish a GIF without frames");

		finished = true;
		var result = backend.finish();
		backend = null;
		return result;
	}
}
