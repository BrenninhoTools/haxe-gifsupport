package gifsupport;

import haxe.io.Bytes;

typedef GifSpriteSheetFrame =
{
	var x:Int;
	var y:Int;
	var delay:Int;
}

class GifSpriteSheet
{
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var frameWidth(default, null):Int;
	public var frameHeight(default, null):Int;
	public var columns(default, null):Int;
	public var rows(default, null):Int;
	public var padding(default, null):Int;
	public var pixels(default, null):Bytes;
	public var frames(default, null):Array<GifSpriteSheetFrame>;
	public var frameRate(default, null):Float;

	function new() {}

	public static function fromGif(gif:Gif, columns:Int = 0, padding:Int = 0):GifSpriteSheet
	{
		var count = gif.frames.length;
		if (count == 0)
			throw new GifException("GIF contains no frames");
		if (padding < 0)
			padding = 0;

		if (columns <= 0)
			columns = Math.ceil(Math.sqrt(count * gif.height / gif.width));
		if (columns > count)
			columns = count;
		if (columns < 1)
			columns = 1;

		var rows = Math.ceil(count / columns);
		var sheetWidth = columns * gif.width + (columns - 1) * padding;
		var sheetHeight = rows * gif.height + (rows - 1) * padding;

		if (sheetWidth * 1.0 * sheetHeight > gifsupport.backend.GifParser.MAX_CANVAS_PIXELS)
			throw new GifException('Sprite sheet too large ${sheetWidth}x$sheetHeight');

		var sheet = new GifSpriteSheet();
		sheet.width = sheetWidth;
		sheet.height = sheetHeight;
		sheet.frameWidth = gif.width;
		sheet.frameHeight = gif.height;
		sheet.columns = columns;
		sheet.rows = rows;
		sheet.padding = padding;
		sheet.frameRate = gif.averageFrameRate;
		sheet.pixels = Bytes.alloc(sheetWidth * sheetHeight * 4);
		sheet.pixels.fill(0, sheet.pixels.length, 0);
		sheet.frames = [];

		var rowBytes = gif.width * 4;
		for (i in 0...count)
		{
			var x = (i % columns) * (gif.width + padding);
			var y = Std.int(i / columns) * (gif.height + padding);
			var source = gif.frames[i].pixels;
			for (row in 0...gif.height)
				sheet.pixels.blit(((y + row) * sheetWidth + x) * 4, source, row * rowBytes, rowBytes);
			sheet.frames.push({x: x, y: y, delay: gif.frames[i].delay});
		}

		return sheet;
	}

	public function toSparrowXml(imagePath:String, prefix:String = "gif"):String
	{
		var buffer = new StringBuf();
		buffer.add('<?xml version="1.0" encoding="utf-8"?>\n');
		buffer.add('<TextureAtlas imagePath="${escape(imagePath)}">\n');
		var name = escape(prefix);
		for (i in 0...frames.length)
		{
			var frame = frames[i];
			buffer.add('\t<SubTexture name="$name${StringTools.lpad(Std.string(i), "0", 4)}" x="${frame.x}" y="${frame.y}" width="$frameWidth" height="$frameHeight"/>\n');
		}
		buffer.add('</TextureAtlas>\n');
		return buffer.toString();
	}

	public function toJson(imagePath:String, prefix:String = "gif"):String
	{
		var entries = new Array<Dynamic>();
		for (i in 0...frames.length)
		{
			var frame = frames[i];
			entries.push({
				filename: prefix + StringTools.lpad(Std.string(i), "0", 4),
				frame: {x: frame.x, y: frame.y, w: frameWidth, h: frameHeight},
				rotated: false,
				trimmed: false,
				spriteSourceSize: {x: 0, y: 0, w: frameWidth, h: frameHeight},
				sourceSize: {w: frameWidth, h: frameHeight},
				duration: frame.delay
			});
		}

		return haxe.Json.stringify({
			frames: entries,
			meta: {
				image: imagePath,
				format: "RGBA8888",
				size: {w: width, h: height},
				scale: "1"
			}
		}, null, "\t");
	}

	static function escape(value:String):String
	{
		return StringTools.htmlEscape(value, true);
	}
}
