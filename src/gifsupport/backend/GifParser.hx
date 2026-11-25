package gifsupport.backend;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

class ParsedFrame
{
	public var left:Int = 0;
	public var top:Int = 0;
	public var width:Int = 0;
	public var height:Int = 0;
	public var interlaced:Bool = false;
	public var delay:Int = 0;
	public var disposal:Int = 0;
	public var transparentIndex:Int = -1;
	public var minCodeSize:Int = 0;
	public var palette:Bytes = null;
	public var data:Bytes = null;

	public function new() {}
}

class ParsedGif
{
	public var version:String = "GIF89a";
	public var width:Int = 0;
	public var height:Int = 0;
	public var loopCount:Int = -1;
	public var backgroundColor:Int = -1;
	public var aspectRatio:Int = 0;
	public var comments:Array<String> = [];
	public var frames:Array<ParsedFrame> = [];

	public function new() {}
}

class GifParser
{
	public static inline var MAX_CANVAS_PIXELS:Int = 1 << 26;

	public static function parse(bytes:Bytes, keepData:Bool, maxFrames:Int):ParsedGif
	{
		var length = bytes.length;

		if (length < 13 || !Gif.isGif(bytes))
			throw new GifException("Invalid GIF header");

		var result = new ParsedGif();
		result.version = bytes.getString(0, 6);
		result.width = bytes.getUInt16(6);
		result.height = bytes.getUInt16(8);
		var screenFlags = bytes.get(10);
		var backgroundIndex = bytes.get(11);
		result.aspectRatio = bytes.get(12);
		var position = 13;

		var globalPalette:Bytes = null;
		if (screenFlags & 0x80 != 0)
		{
			var size = 2 << (screenFlags & 7);
			if (position + size * 3 > length)
				throw new GifException("Truncated global color table");
			globalPalette = bytes.sub(position, size * 3);
			position += size * 3;

			if (backgroundIndex < size)
			{
				var color = backgroundIndex * 3;
				result.backgroundColor = 0xFF000000 | (globalPalette.get(color) << 16) | (globalPalette.get(color + 1) << 8) | globalPalette.get(color + 2);
			}
		}

		var pendingDelay = 0;
		var pendingDisposal = 0;
		var pendingTransparent = -1;

		while (position < length)
		{
			if (maxFrames > 0 && result.frames.length >= maxFrames)
				break;

			var block = bytes.get(position++);

			if (block == 0x3B)
				break;

			if (block == 0x21)
			{
				if (position >= length)
					break;

				var label = bytes.get(position++);

				if (label == 0xF9 && position + 5 <= length && bytes.get(position) >= 4)
				{
					var flags = bytes.get(position + 1);
					pendingDisposal = (flags >> 2) & 7;
					pendingDelay = bytes.getUInt16(position + 2);
					pendingTransparent = (flags & 1) != 0 ? bytes.get(position + 4) : -1;
				}
				else if (label == 0xFF && position + 12 <= length && bytes.get(position) == 11)
				{
					var identifier = bytes.getString(position + 1, 11);
					if (identifier == "NETSCAPE2.0" || identifier == "ANIMEXTS1.0")
					{
						var sub = position + 12;
						if (sub + 4 <= length && bytes.get(sub) >= 3 && (bytes.get(sub + 1) & 7) == 1)
							result.loopCount = bytes.getUInt16(sub + 2);
					}
				}
				else if (label == 0xFE)
				{
					var text = readSubBlocks(bytes, position);
					result.comments.push(text.getString(0, text.length));
				}

				position = skipSubBlocks(bytes, position);
				continue;
			}

			if (block == 0x2C)
			{
				if (position + 9 > length)
					break;

				var frame = new ParsedFrame();
				frame.left = bytes.getUInt16(position);
				frame.top = bytes.getUInt16(position + 2);
				frame.width = bytes.getUInt16(position + 4);
				frame.height = bytes.getUInt16(position + 6);
				var flags = bytes.get(position + 8);
				frame.interlaced = (flags & 0x40) != 0;
				position += 9;

				if (flags & 0x80 != 0)
				{
					var size = 2 << (flags & 7);
					if (position + size * 3 > length)
						break;
					if (keepData)
						frame.palette = bytes.sub(position, size * 3);
					position += size * 3;
				}
				else if (keepData)
				{
					frame.palette = globalPalette;
				}

				if (position >= length)
					break;

				frame.minCodeSize = bytes.get(position++);

				if (keepData)
				{
					var buffer = new BytesBuffer();
					while (position < length)
					{
						var size = bytes.get(position++);
						if (size == 0)
							break;
						var available = size < length - position ? size : length - position;
						buffer.addBytes(bytes, position, available);
						position += available;
					}
					frame.data = buffer.getBytes();
				}
				else
				{
					position = skipSubBlocks(bytes, position);
				}

				frame.delay = normalizeDelay(pendingDelay);
				frame.disposal = pendingDisposal;
				frame.transparentIndex = pendingTransparent;

				pendingDelay = 0;
				pendingDisposal = 0;
				pendingTransparent = -1;

				result.frames.push(frame);
				continue;
			}

			break;
		}

		if (result.frames.length == 0)
			throw new GifException("GIF contains no frames");

		if (result.width == 0 || result.height == 0)
		{
			for (frame in result.frames)
			{
				if (frame.left + frame.width > result.width)
					result.width = frame.left + frame.width;
				if (frame.top + frame.height > result.height)
					result.height = frame.top + frame.height;
			}
		}

		var canvasPixels:Float = result.width * 1.0 * result.height;
		if (canvasPixels <= 0 || canvasPixels > MAX_CANVAS_PIXELS)
			throw new GifException("Invalid GIF dimensions");

		return result;
	}

	public static inline function normalizeDelay(centiseconds:Int):Int
	{
		var delay = centiseconds * 10;
		return delay <= 10 ? 100 : delay;
	}

	public static inline function aspectRatioToFloat(value:Int):Float
	{
		return value == 0 ? 0 : (value + 15) / 64;
	}

	static function skipSubBlocks(bytes:Bytes, position:Int):Int
	{
		var length = bytes.length;
		while (position < length)
		{
			var size = bytes.get(position);
			position += 1 + size;
			if (size == 0)
				return position;
		}
		return length;
	}

	static function readSubBlocks(bytes:Bytes, position:Int):Bytes
	{
		var length = bytes.length;
		var buffer = new BytesBuffer();
		while (position < length)
		{
			var size = bytes.get(position++);
			if (size == 0)
				break;
			var available = size < length - position ? size : length - position;
			buffer.addBytes(bytes, position, available);
			position += available;
		}
		return buffer.getBytes();
	}
}
