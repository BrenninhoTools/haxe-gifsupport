package gifsupport;

import haxe.io.Bytes;

class GifFrame
{
	public var pixels(default, null):Bytes;
	public var delay(default, null):Int;
	public var disposal(default, null):Int;

	public function new(pixels:Bytes, delay:Int, disposal:Int = 0)
	{
		this.pixels = pixels;
		this.delay = delay;
		this.disposal = disposal;
	}

	public function getPixel(width:Int, x:Int, y:Int):Int
	{
		var position = (y * width + x) * 4;
		return (pixels.get(position + 3) << 24) | (pixels.get(position) << 16) | (pixels.get(position + 1) << 8) | pixels.get(position + 2);
	}

	public function toARGB():Bytes
	{
		var result = Bytes.alloc(pixels.length);
		var position = 0;
		while (position < pixels.length)
		{
			result.set(position, pixels.get(position + 3));
			result.set(position + 1, pixels.get(position));
			result.set(position + 2, pixels.get(position + 1));
			result.set(position + 3, pixels.get(position + 2));
			position += 4;
		}
		return result;
	}

	public function toBGRA():Bytes
	{
		var result = Bytes.alloc(pixels.length);
		var position = 0;
		while (position < pixels.length)
		{
			result.set(position, pixels.get(position + 2));
			result.set(position + 1, pixels.get(position + 1));
			result.set(position + 2, pixels.get(position));
			result.set(position + 3, pixels.get(position + 3));
			position += 4;
		}
		return result;
	}
}
