package gifsupport.flixel;

#if flixel
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxImageFrame;
import gifsupport.openfl.GifBitmap;
import haxe.io.Bytes;

class FlxGifSprite extends FlxSprite
{
	public var gif(default, null):Gif;
	public var playback(default, null):GifPlayback;
	public var gifFrame(get, never):Int;
	public var gifPlaying(get, never):Bool;
	public var onGifComplete:Void->Void;
	public var onGifLoop:Void->Void;

	var gifGraphics:Array<FlxGraphic> = [];
	var gifImageFrames:Array<FlxImageFrame> = [];

	public function new(x:Float = 0, y:Float = 0, ?gif:Gif, autoPlay:Bool = true)
	{
		super(x, y);
		if (gif != null)
			loadGif(gif, autoPlay);
	}

	public function loadGif(gif:Gif, autoPlay:Bool = true):FlxGifSprite
	{
		var oldGraphics = gifGraphics;

		this.gif = gif;
		gifGraphics = [];
		gifImageFrames = [];

		for (i in 0...gif.frames.length)
		{
			var graphic = FlxGraphic.fromBitmapData(GifBitmap.toBitmapData(gif, i), false, null, false);
			graphic.destroyOnNoUse = false;
			gifGraphics.push(graphic);
			gifImageFrames.push(FlxImageFrame.fromGraphic(graphic));
		}

		frames = gifImageFrames[0];

		for (graphic in oldGraphics)
			graphic.destroy();

		playback = new GifPlayback(gif);
		playback.onComplete = function()
		{
			if (onGifComplete != null)
				onGifComplete();
		};
		playback.onLoop = function()
		{
			if (onGifLoop != null)
				onGifLoop();
		};

		if (autoPlay)
			playback.play();

		return this;
	}

	public function loadGifBytes(bytes:Bytes, autoPlay:Bool = true):FlxGifSprite
	{
		return loadGif(Gif.fromBytes(bytes), autoPlay);
	}

	public function loadGifAsset(id:String, autoPlay:Bool = true):FlxGifSprite
	{
		return loadGifBytes(openfl.utils.Assets.getBytes(id), autoPlay);
	}

	#if sys
	public function loadGifFile(path:String, autoPlay:Bool = true):FlxGifSprite
	{
		return loadGif(Gif.fromFile(path), autoPlay);
	}
	#end

	public function playGif(restart:Bool = false):Void
	{
		if (playback == null)
			return;
		playback.play(restart);
		showGifFrame(playback.frame);
	}

	public function pauseGif():Void
	{
		if (playback != null)
			playback.pause();
	}

	public function stopGif():Void
	{
		if (playback == null)
			return;
		playback.stop();
		showGifFrame(0);
	}

	public function gotoGifFrame(index:Int):Void
	{
		if (playback == null)
			return;
		playback.goto(index);
		showGifFrame(playback.frame);
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (playback != null && playback.update(elapsed * 1000))
			showGifFrame(playback.frame);
	}

	override public function destroy():Void
	{
		super.destroy();

		for (graphic in gifGraphics)
			graphic.destroy();

		gifGraphics = [];
		gifImageFrames = [];
		playback = null;
		gif = null;
	}

	function showGifFrame(index:Int):Void
	{
		if (index < 0 || index >= gifImageFrames.length)
			return;

		var imageFrame = gifImageFrames[index];
		graphic = imageFrame.parent;
		frame = imageFrame.frame;
	}

	function get_gifFrame():Int
	{
		return playback == null ? 0 : playback.frame;
	}

	function get_gifPlaying():Bool
	{
		return playback != null && playback.playing;
	}
}
#end
