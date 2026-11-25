package gifsupport;

import haxe.io.Bytes;

class GifFrame
{
	public var pixels(default, null):Bytes;
	public var delay(default, null):Int;
	public var disposal(default, null):Int;
	public var x(default, null):Int;
	public var y(default, null):Int;
	public var regionWidth(default, null):Int;
	public var regionHeight(default, null):Int;
	public var interlaced(default, null):Bool;

	public function new(pixels:Bytes, delay:Int, disposal:Int = 0, x:Int = 0, y:Int = 0, regionWidth:Int = 0, regionHeight:Int = 0,
			interlaced:Bool = false)
	{
		this.pixels = pixels;
		this.delay = delay;
		this.disposal = disposal;
		this.x = x;
		this.y = y;
		this.regionWidth = regionWidth;
		this.regionHeight = regionHeight;
		this.interlaced = interlaced;
	}

	public function getPixel(width:Int, x:Int, y:Int):Int
	{
		var position = (y * width + x) * 4;
		return (pixels.get(position + 3) << 24) | (pixels.get(position) << 16) | (pixels.get(position + 1) << 8) | pixels.get(position + 2);
	}

	public function withDelay(delay:Int):GifFrame
	{
		return new GifFrame(pixels, delay, disposal, x, y, regionWidth, regionHeight, interlaced);
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
