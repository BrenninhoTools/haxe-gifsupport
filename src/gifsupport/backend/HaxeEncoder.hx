package gifsupport.backend;

import haxe.ds.Vector;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;

private class ColorEntry
{
	public var r:Int;
	public var g:Int;
	public var b:Int;
	public var count:Int;

	public function new(r:Int, g:Int, b:Int, count:Int)
	{
		this.r = r;
		this.g = g;
		this.b = b;
		this.count = count;
	}

	public inline function channel(axis:Int):Int
	{
		return axis == 0 ? r : (axis == 1 ? g : b);
	}
}

private class BitWriter
{
	public var bytes:BytesBuffer = new BytesBuffer();

	var buffer:Int = 0;
	var count:Int = 0;

	public function new() {}

	public function write(code:Int, size:Int):Void
	{
		buffer |= code << count;
		count += size;
		while (count >= 8)
		{
			bytes.addByte(buffer & 0xFF);
			buffer >>>= 8;
			count -= 8;
		}
	}

	public function flush():Void
	{
		if (count > 0)
		{
			bytes.addByte(buffer & 0xFF);
			buffer = 0;
			count = 0;
		}
	}
}

class HaxeEncoder
{
	var width:Int;
	var height:Int;
	var optimize:Bool;
	var dither:Bool;
	var alphaThreshold:Int;
	var output:BytesBuffer;
	var canvas:Bytes;
	var pending:Bytes;
	var pendingDelay:Int = 0;

	public function new(width:Int, height:Int, loopCount:Int, optimize:Bool = true, dither:Bool = false, alphaThreshold:Int = 128)
	{
		this.width = width;
		this.height = height;
		this.optimize = optimize;
		this.dither = dither;
		this.alphaThreshold = alphaThreshold;
		output = new BytesBuffer();

		output.addString("GIF89a");
		writeShort(width);
		writeShort(height);
		output.addByte(0x70);
		output.addByte(0);
		output.addByte(0);

		if (loopCount >= 0)
		{
			output.addByte(0x21);
			output.addByte(0xFF);
			output.addByte(11);
			output.addString("NETSCAPE2.0");
			output.addByte(3);
			output.addByte(1);
			writeShort(loopCount);
			output.addByte(0);
		}

		if (optimize)
		{
			canvas = Bytes.alloc(width * height * 4);
			canvas.fill(0, canvas.length, 0);
		}
	}

	inline function writeShort(value:Int):Void
	{
		output.addByte(value & 0xFF);
		output.addByte((value >> 8) & 0xFF);
	}

	public function addComment(text:Bytes):Void
	{
		if (text.length == 0)
			return;

		output.addByte(0x21);
		output.addByte(0xFE);
		var position = 0;
		while (position < text.length)
		{
			var size = text.length - position < 255 ? text.length - position : 255;
			output.addByte(size);
			output.addBytes(text, position, size);
			position += size;
		}
		output.addByte(0);
	}

	public function addFrame(rgba:Bytes, delay:Int):Void
	{
		var frame = normalize(rgba);

		if (!optimize)
		{
			writeFrame(frame, delay, 2, 0, 0, width, height, null);
			return;
		}

		if (pending != null)
			flushPending(frame);

		pending = frame;
		pendingDelay = delay;
	}

	public function finish():Bytes
	{
		if (pending != null)
			flushPending(null);

		output.addByte(0x3B);
		var result = output.getBytes();
		output = null;
		canvas = null;
		return result;
	}

	function normalize(rgba:Bytes):Bytes
	{
		var size = width * height * 4;
		var result = Bytes.alloc(size);
		var position = 0;
		while (position < size)
		{
			if (rgba.get(position + 3) < alphaThreshold)
			{
				result.setInt32(position, 0);
			}
			else
			{
				result.set(position, rgba.get(position));
				result.set(position + 1, rgba.get(position + 1));
				result.set(position + 2, rgba.get(position + 2));
				result.set(position + 3, 255);
			}
			position += 4;
		}
		return result;
	}

	function flushPending(next:Bytes):Void
	{
		var needsClear = false;
		if (next != null)
		{
			var position = 3;
			var size = width * height * 4;
			while (position < size)
			{
				if (next.get(position) == 0 && pending.get(position) != 0)
				{
					needsClear = true;
					break;
				}
				position += 4;
			}
		}

		if (needsClear)
		{
			writeFrame(pending, pendingDelay, 2, 0, 0, width, height, canvas);
			canvas.fill(0, canvas.length, 0);
		}
		else
		{
			var left = width;
			var top = height;
			var right = -1;
			var bottom = -1;
			for (y in 0...height)
			{
				for (x in 0...width)
				{
					var position = (y * width + x) * 4;
					if (pending.getInt32(position) != canvas.getInt32(position))
					{
						if (x < left)
							left = x;
						if (x > right)
							right = x;
						if (y < top)
							top = y;
						if (y > bottom)
							bottom = y;
					}
				}
			}

			if (right < 0)
			{
				left = 0;
				top = 0;
				right = 0;
				bottom = 0;
			}

			writeFrame(pending, pendingDelay, 1, left, top, right - left + 1, bottom - top + 1, canvas);
			canvas = pending;
		}

		pending = null;
	}

	function writeFrame(frame:Bytes, delay:Int, disposal:Int, regionX:Int, regionY:Int, regionWidth:Int, regionHeight:Int, compare:Bytes):Void
	{
		var count = regionWidth * regionHeight;
		var colors = new Vector<Int>(count);
		var hasTransparency = false;
		var exact = new Map<Int, Int>();
		var exactCount = 0;
		var exactFits = true;

		for (row in 0...regionHeight)
		{
			for (column in 0...regionWidth)
			{
				var n = row * regionWidth + column;
				var position = ((regionY + row) * width + regionX + column) * 4;
				var value = frame.getInt32(position);
				if (frame.get(position + 3) == 0 || (compare != null && compare.getInt32(position) == value))
				{
					colors[n] = -1;
					hasTransparency = true;
					continue;
				}

				var key = (frame.get(position) << 16) | (frame.get(position + 1) << 8) | frame.get(position + 2);
				colors[n] = key;
				if (exactFits && !exact.exists(key))
				{
					exact.set(key, exactCount++);
					if (exactCount > 256)
						exactFits = false;
				}
			}
		}

		var maxColors = hasTransparency ? 255 : 256;
		if (exactCount > maxColors)
			exactFits = false;

		var palette = new Array<Int>();
		var lookup:Vector<Int> = null;

		if (exactFits)
		{
			var ordered = new Vector<Int>(exactCount);
			for (key => index in exact)
				ordered[index] = key;
			for (key in ordered)
			{
				palette.push((key >> 16) & 0xFF);
				palette.push((key >> 8) & 0xFF);
				palette.push(key & 0xFF);
			}
		}
		else
		{
			var histogram = new Vector<Int>(32768 * 4);
			for (i in 0...histogram.length)
				histogram[i] = 0;

			for (i in 0...count)
			{
				var color = colors[i];
				if (color < 0)
					continue;
				var r = (color >> 16) & 0xFF;
				var g = (color >> 8) & 0xFF;
				var b = color & 0xFF;
				var key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
				histogram[key * 4] += r;
				histogram[key * 4 + 1] += g;
				histogram[key * 4 + 2] += b;
				histogram[key * 4 + 3]++;
			}

			var entries = new Array<ColorEntry>();
			for (key in 0...32768)
			{
				var total = histogram[key * 4 + 3];
				if (total == 0)
					continue;
				entries.push(new ColorEntry(Std.int(histogram[key * 4] / total), Std.int(histogram[key * 4 + 1] / total), Std.int(histogram[key * 4 + 2] / total), total));
			}

			medianCut(entries, maxColors, palette);

			lookup = new Vector<Int>(32768);
			for (key in 0...32768)
			{
				var total = histogram[key * 4 + 3];
				lookup[key] = total == 0 ? -1 : nearestColor(palette, Std.int(histogram[key * 4] / total), Std.int(histogram[key * 4 + 1] / total), Std.int(histogram[key * 4 + 2] / total));
			}
		}

		var colorCount = Std.int(palette.length / 3);
		var transparentIndex = -1;
		if (hasTransparency)
		{
			transparentIndex = colorCount;
			palette.push(0);
			palette.push(0);
			palette.push(0);
			colorCount++;
		}

		var tableBits = 1;
		while ((1 << tableBits) < colorCount)
			tableBits++;

		var indices = Bytes.alloc(count);
		if (exactFits)
		{
			for (i in 0...count)
			{
				var color = colors[i];
				indices.set(i, color < 0 ? transparentIndex : exact.get(color));
			}
		}
		else if (dither)
		{
			ditherIndices(colors, regionWidth, regionHeight, palette, lookup, transparentIndex, indices);
		}
		else
		{
			for (i in 0...count)
			{
				var color = colors[i];
				if (color < 0)
				{
					indices.set(i, transparentIndex);
					continue;
				}
				var key = (((color >> 16) & 0xFF) >> 3) << 10 | (((color >> 8) & 0xFF) >> 3) << 5 | ((color & 0xFF) >> 3);
				indices.set(i, lookup[key]);
			}
		}

		while (palette.length < (1 << tableBits) * 3)
			palette.push(0);

		var centiseconds = Std.int((delay + 5) / 10);
		if (centiseconds < 0)
			centiseconds = 0;
		if (centiseconds > 65535)
			centiseconds = 65535;

		output.addByte(0x21);
		output.addByte(0xF9);
		output.addByte(4);
		output.addByte((disposal << 2) | (hasTransparency ? 1 : 0));
		writeShort(centiseconds);
		output.addByte(hasTransparency ? transparentIndex : 0);
		output.addByte(0);

		output.addByte(0x2C);
		writeShort(regionX);
		writeShort(regionY);
		writeShort(regionWidth);
		writeShort(regionHeight);
		output.addByte(0x80 | (tableBits - 1));
		for (value in palette)
			output.addByte(value);

		var minCodeSize = tableBits < 2 ? 2 : tableBits;
		output.addByte(minCodeSize);
		compress(indices, minCodeSize);
	}

	static function ditherIndices(colors:Vector<Int>, regionWidth:Int, regionHeight:Int, palette:Array<Int>, lookup:Vector<Int>, transparentIndex:Int,
			indices:Bytes):Void
	{
		var stride = (regionWidth + 2) * 3;
		var current = new Vector<Float>(stride);
		var next = new Vector<Float>(stride);
		for (i in 0...stride)
		{
			current[i] = 0;
			next[i] = 0;
		}

		for (y in 0...regionHeight)
		{
			for (x in 0...regionWidth)
			{
				var n = y * regionWidth + x;
				var color = colors[n];
				if (color < 0)
				{
					indices.set(n, transparentIndex);
					continue;
				}

				var e = (x + 1) * 3;
				var r = clamp(((color >> 16) & 0xFF) + current[e]);
				var g = clamp(((color >> 8) & 0xFF) + current[e + 1]);
				var b = clamp((color & 0xFF) + current[e + 2]);

				var key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
				var index = lookup[key];
				if (index < 0)
				{
					index = nearestColor(palette, r, g, b);
					lookup[key] = index;
				}
				indices.set(n, index);

				var errorR = r - palette[index * 3];
				var errorG = g - palette[index * 3 + 1];
				var errorB = b - palette[index * 3 + 2];

				current[e + 3] += errorR * 7 / 16;
				current[e + 4] += errorG * 7 / 16;
				current[e + 5] += errorB * 7 / 16;
				next[e - 3] += errorR * 3 / 16;
				next[e - 2] += errorG * 3 / 16;
				next[e - 1] += errorB * 3 / 16;
				next[e] += errorR * 5 / 16;
				next[e + 1] += errorG * 5 / 16;
				next[e + 2] += errorB * 5 / 16;
				next[e + 3] += errorR / 16;
				next[e + 4] += errorG / 16;
				next[e + 5] += errorB / 16;
			}

			var swap = current;
			current = next;
			next = swap;
			for (i in 0...stride)
				next[i] = 0;
		}
	}

	static inline function clamp(value:Float):Int
	{
		var result = Math.round(value);
		return result < 0 ? 0 : (result > 255 ? 255 : result);
	}

	function compress(indices:Bytes, minCodeSize:Int):Void
	{
		var clearCode = 1 << minCodeSize;
		var endCode = clearCode + 1;
		var codeSize = minCodeSize + 1;
		var nextCode = clearCode + 2;

		var dictionary = new Map<Int, Int>();
		var writer = new BitWriter();
		writer.write(clearCode, codeSize);

		var current = indices.get(0);
		for (i in 1...indices.length)
		{
			var value = indices.get(i);
			var key = (current << 8) | value;
			var found = dictionary.get(key);
			if (found != null)
			{
				current = found;
				continue;
			}

			writer.write(current, codeSize);
			dictionary.set(key, nextCode++);

			if (nextCode > (1 << codeSize) && codeSize < 12)
				codeSize++;

			if (nextCode == 4096)
			{
				writer.write(clearCode, codeSize);
				dictionary = new Map<Int, Int>();
				codeSize = minCodeSize + 1;
				nextCode = clearCode + 2;
			}

			current = value;
		}

		writer.write(current, codeSize);
		if (nextCode == (1 << codeSize) && codeSize < 12)
			codeSize++;
		writer.write(endCode, codeSize);
		writer.flush();

		var data = writer.bytes.getBytes();
		var position = 0;
		while (position < data.length)
		{
			var size = data.length - position < 255 ? data.length - position : 255;
			output.addByte(size);
			output.addBytes(data, position, size);
			position += size;
		}
		output.addByte(0);
	}

	static function medianCut(entries:Array<ColorEntry>, maxColors:Int, palette:Array<Int>):Void
	{
		var begins = [0];
		var ends = [entries.length];

		while (begins.length < maxColors)
		{
			var bestBox = -1;
			var bestAxis = 0;
			var bestScore = -1.0;

			for (i in 0...begins.length)
			{
				if (ends[i] - begins[i] < 2)
					continue;

				var minimum = [255, 255, 255];
				var maximum = [0, 0, 0];
				var total = 0.0;
				for (e in begins[i]...ends[i])
				{
					var entry = entries[e];
					for (axis in 0...3)
					{
						var value = entry.channel(axis);
						if (value < minimum[axis])
							minimum[axis] = value;
						if (value > maximum[axis])
							maximum[axis] = value;
					}
					total += entry.count;
				}

				var axis = 0;
				var range = maximum[0] - minimum[0];
				for (a in 1...3)
				{
					if (maximum[a] - minimum[a] > range)
					{
						range = maximum[a] - minimum[a];
						axis = a;
					}
				}

				var score = range * total;
				if (range > 0 && score > bestScore)
				{
					bestScore = score;
					bestBox = i;
					bestAxis = axis;
				}
			}

			if (bestBox < 0)
				break;

			var begin = begins[bestBox];
			var end = ends[bestBox];
			var slice = entries.slice(begin, end);
			var axis = bestAxis;
			haxe.ds.ArraySort.sort(slice, function(a, b) return a.channel(axis) - b.channel(axis));
			for (e in 0...slice.length)
				entries[begin + e] = slice[e];

			var total = 0.0;
			for (e in begin...end)
				total += entries[e].count;

			var half = Math.ffloor(total / 2);
			var accumulated = 0.0;
			var split = begin + 1;
			for (e in begin...end - 1)
			{
				accumulated += entries[e].count;
				split = e + 1;
				if (accumulated >= half)
					break;
			}

			ends[bestBox] = split;
			begins.push(split);
			ends.push(end);
		}

		for (i in 0...begins.length)
		{
			var r = 0.0;
			var g = 0.0;
			var b = 0.0;
			var total = 0.0;
			for (e in begins[i]...ends[i])
			{
				var entry = entries[e];
				r += entry.r * entry.count;
				g += entry.g * entry.count;
				b += entry.b * entry.count;
				total += entry.count;
			}
			if (total == 0)
				total = 1;
			palette.push(Std.int(Math.ffloor((r + Math.ffloor(total / 2)) / total)));
			palette.push(Std.int(Math.ffloor((g + Math.ffloor(total / 2)) / total)));
			palette.push(Std.int(Math.ffloor((b + Math.ffloor(total / 2)) / total)));
		}
	}

	static function nearestColor(palette:Array<Int>, r:Int, g:Int, b:Int):Int
	{
		var best = 0;
		var bestDistance = 0x7FFFFFFF;
		var count = Std.int(palette.length / 3);
		for (i in 0...count)
		{
			var dr = palette[i * 3] - r;
			var dg = palette[i * 3 + 1] - g;
			var db = palette[i * 3 + 2] - b;
			var distance = dr * dr * 2 + dg * dg * 4 + db * db * 3;
			if (distance < bestDistance)
			{
				bestDistance = distance;
				best = i;
				if (distance == 0)
					break;
			}
		}
		return best;
	}
}
