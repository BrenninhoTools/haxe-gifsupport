package gifsupport.backend;

import haxe.ds.Vector;
import haxe.io.Bytes;

private class RawFrame
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

class HaxeDecoder
{
	static inline var MAX_CANVAS_PIXELS:Int = 1 << 26;

	public static function decode(bytes:Bytes):Gif
	{
		var length = bytes.length;

		if (length < 13 || !Gif.isGif(bytes))
			throw new GifException("Invalid GIF header");

		var canvasWidth = bytes.getUInt16(6);
		var canvasHeight = bytes.getUInt16(8);
		var screenFlags = bytes.get(10);
		var position = 13;

		var globalPalette:Bytes = null;
		if (screenFlags & 0x80 != 0)
		{
			var size = 2 << (screenFlags & 7);
			if (position + size * 3 > length)
				throw new GifException("Truncated global color table");
			globalPalette = bytes.sub(position, size * 3);
			position += size * 3;
		}

		var loopCount = -1;
		var pendingDelay = 0;
		var pendingDisposal = 0;
		var pendingTransparent = -1;
		var rawFrames = new Array<RawFrame>();

		while (position < length)
		{
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
							loopCount = bytes.getUInt16(sub + 2);
					}
				}

				position = skipSubBlocks(bytes, position);
				continue;
			}

			if (block == 0x2C)
			{
				if (position + 9 > length)
					break;

				var frame = new RawFrame();
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
					frame.palette = bytes.sub(position, size * 3);
					position += size * 3;
				}
				else
				{
					frame.palette = globalPalette;
				}

				if (position >= length)
					break;

				frame.minCodeSize = bytes.get(position++);

				var buffer = new haxe.io.BytesBuffer();
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

				frame.delay = pendingDelay * 10;
				if (frame.delay <= 10)
					frame.delay = 100;
				frame.disposal = pendingDisposal;
				frame.transparentIndex = pendingTransparent;

				pendingDelay = 0;
				pendingDisposal = 0;
				pendingTransparent = -1;

				rawFrames.push(frame);
				continue;
			}

			break;
		}

		if (rawFrames.length == 0)
			throw new GifException("GIF contains no frames");

		if (canvasWidth == 0 || canvasHeight == 0)
		{
			for (frame in rawFrames)
			{
				if (frame.left + frame.width > canvasWidth)
					canvasWidth = frame.left + frame.width;
				if (frame.top + frame.height > canvasHeight)
					canvasHeight = frame.top + frame.height;
			}
		}

		var canvasPixels:Float = canvasWidth * 1.0 * canvasHeight;
		if (canvasPixels <= 0 || canvasPixels > MAX_CANVAS_PIXELS)
			throw new GifException("Invalid GIF dimensions");

		var width = canvasWidth;
		var height = canvasHeight;
		var canvas = Bytes.alloc(width * height * 4);
		canvas.fill(0, canvas.length, 0);
		var saved:Bytes = null;
		var frames = new Array<GifFrame>();

		for (raw in rawFrames)
		{
			var framePixels:Float = raw.width * 1.0 * raw.height;

			if (raw.disposal == 3)
				saved = canvas.sub(0, canvas.length);

			if (framePixels > 0 && framePixels <= MAX_CANVAS_PIXELS)
			{
				var indices = Bytes.alloc(raw.width * raw.height);
				var decoded = decompress(raw, indices);
				var rowMap = buildRowMap(raw.height, raw.interlaced);
				var palette = raw.palette;
				var paletteSize = palette == null ? 0 : Std.int(palette.length / 3);

				for (n in 0...decoded)
				{
					var index = indices.get(n);
					if (index == raw.transparentIndex || index >= paletteSize)
						continue;

					var x = raw.left + n % raw.width;
					var y = raw.top + rowMap[Std.int(n / raw.width)];
					if (x >= width || y >= height)
						continue;

					var target = (y * width + x) * 4;
					var color = index * 3;
					canvas.set(target, palette.get(color));
					canvas.set(target + 1, palette.get(color + 1));
					canvas.set(target + 2, palette.get(color + 2));
					canvas.set(target + 3, 255);
				}
			}

			frames.push(new GifFrame(canvas.sub(0, canvas.length), raw.delay, raw.disposal));

			if (raw.disposal == 2)
			{
				var right = raw.left + raw.width < width ? raw.left + raw.width : width;
				var bottom = raw.top + raw.height < height ? raw.top + raw.height : height;
				if (right > raw.left)
					for (y in raw.top...bottom)
						canvas.fill((y * width + raw.left) * 4, (right - raw.left) * 4, 0);
			}
			else if (raw.disposal == 3 && saved != null)
			{
				canvas.blit(0, saved, 0, saved.length);
			}
		}

		return new Gif(width, height, loopCount, frames);
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

	static function buildRowMap(height:Int, interlaced:Bool):Vector<Int>
	{
		var rowMap = new Vector<Int>(height);
		if (interlaced)
		{
			var starts = [0, 4, 2, 1];
			var steps = [8, 8, 4, 2];
			var row = 0;
			for (pass in 0...4)
			{
				var y = starts[pass];
				while (y < height)
				{
					rowMap[row++] = y;
					y += steps[pass];
				}
			}
		}
		else
		{
			for (y in 0...height)
				rowMap[y] = y;
		}
		return rowMap;
	}

	static function decompress(frame:RawFrame, indices:Bytes):Int
	{
		var total = indices.length;
		var minCodeSize = frame.minCodeSize;
		if (minCodeSize < 1 || minCodeSize > 11 || total == 0)
			return 0;

		var prefix = new Vector<Int>(4096);
		var suffix = new Vector<Int>(4096);
		var first = new Vector<Int>(4096);
		var lengths = new Vector<Int>(4096);

		var clearCode = 1 << minCodeSize;
		var endCode = clearCode + 1;

		for (i in 0...clearCode)
		{
			prefix[i] = 0;
			suffix[i] = i;
			first[i] = i;
			lengths[i] = 1;
		}

		var codeSize = minCodeSize + 1;
		var nextCode = clearCode + 2;
		var previous = -1;

		var data = frame.data;
		var dataLength = data.length;
		var dataPosition = 0;
		var bitBuffer = 0;
		var bitCount = 0;
		var output = 0;

		while (output < total)
		{
			while (bitCount < codeSize && dataPosition < dataLength)
			{
				bitBuffer |= data.get(dataPosition++) << bitCount;
				bitCount += 8;
			}

			if (bitCount < codeSize)
				break;

			var code = bitBuffer & ((1 << codeSize) - 1);
			bitBuffer >>>= codeSize;
			bitCount -= codeSize;

			if (code == clearCode)
			{
				codeSize = minCodeSize + 1;
				nextCode = clearCode + 2;
				previous = -1;
				continue;
			}

			if (code == endCode)
				break;

			if (previous == -1)
			{
				if (code >= clearCode)
					break;

				indices.set(output++, code);
				previous = code;
				continue;
			}

			if (code < nextCode)
			{
				if (nextCode < 4096)
				{
					prefix[nextCode] = previous;
					suffix[nextCode] = first[code];
					first[nextCode] = first[previous];
					lengths[nextCode] = lengths[previous] + 1;
					nextCode++;
				}
			}
			else if (code == nextCode && nextCode < 4096)
			{
				prefix[nextCode] = previous;
				suffix[nextCode] = first[previous];
				first[nextCode] = first[previous];
				lengths[nextCode] = lengths[previous] + 1;
				nextCode++;
			}
			else
			{
				break;
			}

			var end = output + lengths[code];
			var current = code;
			var position = end - 1;
			while (position >= output)
			{
				if (position < total)
					indices.set(position, suffix[current]);
				current = prefix[current];
				position--;
			}
			output = end < total ? end : total;

			previous = code;

			if (nextCode == (1 << codeSize) && codeSize < 12)
				codeSize++;
		}

		return output;
	}
}
