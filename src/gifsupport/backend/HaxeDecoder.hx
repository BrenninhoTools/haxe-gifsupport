package gifsupport.backend;

import gifsupport.backend.GifParser;
import haxe.ds.Vector;
import haxe.io.Bytes;

class HaxeDecoder
{
	public static function decode(bytes:Bytes, maxFrames:Int = 0):Gif
	{
		var parsed = GifParser.parse(bytes, true, maxFrames);
		var width = parsed.width;
		var height = parsed.height;
		var canvas = Bytes.alloc(width * height * 4);
		canvas.fill(0, canvas.length, 0);
		var saved:Bytes = null;
		var frames = new Array<GifFrame>();

		for (raw in parsed.frames)
		{
			var framePixels:Float = raw.width * 1.0 * raw.height;

			if (raw.disposal == 3)
				saved = canvas.sub(0, canvas.length);

			if (framePixels > 0 && framePixels <= GifParser.MAX_CANVAS_PIXELS)
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

			frames.push(new GifFrame(canvas.sub(0, canvas.length), raw.delay, raw.disposal, raw.left, raw.top, raw.width, raw.height, raw.interlaced));

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

		return new Gif(width, height, parsed.loopCount, frames, parsed.version, parsed.backgroundColor,
			GifParser.aspectRatioToFloat(parsed.aspectRatio), parsed.comments);
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

	static function decompress(frame:ParsedFrame, indices:Bytes):Int
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
